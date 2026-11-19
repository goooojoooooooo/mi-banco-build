import Foundation
import ImageIO

/// Busca en internet el logo de un comercio que el directorio no conoce, fuera del hilo principal.
/// Prueba `<slug>.es` y luego `<slug>.com` en el servicio de favicons, una vez; acepta solo una imagen
/// real de 64 a 512 px (y como mucho 256 000 bytes). Guarda el acierto (PNG) y el fallo DEFINITIVO (404 o imagen
/// que no vale; 30 días) en Caches/Logos, por comercio normalizado. Sin red, un tiempo de espera o un 5xx no se
/// guardan como fallo: se vuelve a probar en otra sesión. Sin reintentos en bucle y sin registrar nada.
actor LogoFetcher {
    private static let negativeLifetime: TimeInterval = 30 * 24 * 3600
    private static let minimumSide = 64
    private static let maximumSide = 512
    private static let maximumBytes = 256_000

    /// Resultado de pedir un dominio: logo, "no hay" seguro, o un fallo pasajero que no se recuerda.
    private enum Fetch {
        case logo(Data)
        case definitiveMiss
        case transient
    }

    private let directory: URL?
    private let session: URLSession
    private var inFlight: [String: Task<Data?, Never>] = [:]

    init() {
        directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "Logos", directoryHint: .isDirectory)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.httpShouldSetCookies = false
        // Agente genérico: la petición no lleva el nombre de la app.
        config.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0"]
        session = URLSession(configuration: config)
    }

    /// PNG del logo, o nil si no hay (o ya se sabe que no hay).
    func logo(key: String, slug: String) async -> Data? {
        if let running = inFlight[key] { return await running.value }
        let task = Task { await self.load(key: key, slug: slug) }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    private func load(key: String, slug: String) async -> Data? {
        guard let directory else { return nil }
        let name = Self.fileName(for: key)
        let hit = directory.appending(path: name + ".png")
        let miss = directory.appending(path: name + ".none")
        let files = FileManager.default

        if let data = try? Data(contentsOf: hit) { return data }
        if let date = (try? files.attributesOfItem(atPath: miss.path))?[.modificationDate] as? Date,
           Date().timeIntervalSince(date) < Self.negativeLifetime {
            return nil
        }
        try? files.createDirectory(at: directory, withIntermediateDirectories: true)
        var sawTransient = false
        for domain in ["\(slug).es", "\(slug).com"] {
            switch await fetch(domain: domain) {
            case .logo(let png):
                try? png.write(to: hit, options: .atomic)
                try? files.removeItem(at: miss)
                return png
            case .definitiveMiss:
                continue
            case .transient:
                sawTransient = true
            }
        }
        // Solo un "no hay" seguro en los dos dominios se recuerda (crear el archivo renueva su fecha).
        if !sawTransient { files.createFile(atPath: miss.path, contents: Data()) }
        return nil
    }

    private func fetch(domain: String) async -> Fetch {
        var components = URLComponents(string: "https://www.google.com/s2/favicons")
        components?.queryItems = [URLQueryItem(name: "domain", value: domain), URLQueryItem(name: "sz", value: "128")]
        guard let url = components?.url else { return .definitiveMiss }
        // Sin red, tiempo agotado, cancelado...: pasajero.
        guard case let (data, response)? = try? await session.data(from: url),
              let status = (response as? HTTPURLResponse)?.statusCode else { return .transient }
        switch status {
        case 200:
            return Self.isRealLogo(data) ? .logo(data) : .definitiveMiss
        case 404, 410:
            return .definitiveMiss
        default:
            // 5xx, 429 y demás: no se sabe si hay logo.
            return .transient
        }
    }

    /// Imagen legible de 64 a 512 px por lado y de 256 000 bytes como mucho (el globo genérico es más pequeño).
    private static func isRealLogo(_ data: Data) -> Bool {
        guard data.count <= maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else { return false }
        return min(width, height) >= minimumSide && max(width, height) <= maximumSide
    }

    /// "casa lola" -> "casa-lola" (la clave ya solo tiene letras, cifras y espacios).
    private static func fileName(for key: String) -> String {
        String(key.replacingOccurrences(of: " ", with: "-").prefix(64))
    }
}
