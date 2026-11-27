import CryptoKit
import Foundation
import ImageIO
import MiBancoCore

/// Busca en internet el logo de un comercio que el directorio no conoce, fuera del hilo principal.
/// Prueba `<slug>.es` y luego `<slug>.com` en el servicio de favicons, una vez; acepta solo una imagen
/// real de 64 a 512 px (y como mucho 256 000 bytes). Guarda el acierto (PNG) y el fallo DEFINITIVO (404 o imagen
/// que no vale; 30 días) en Caches/Logos con protección de fichero y nombres por hash SHA-256 (sin el nombre del
/// comercio en claro). Sin red, un tiempo de espera o un 5xx no se guardan como fallo: se vuelve a probar en otra
/// sesión. Sin reintentos en bucle y sin registrar nada.
actor LogoFetcher {
    private static let negativeLifetime: TimeInterval = 30 * 24 * 3600
    private static let minimumSide = 64
    private static let maximumSide = 512
    private static let maximumBytes = LogoCachePolicy.maxDownloadBytes
    private static let writeOptions: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]

    /// Resultado de pedir un dominio: logo, "no hay" seguro, o un fallo pasajero que no se recuerda.
    private enum Fetch {
        case logo(Data)
        case definitiveMiss
        case transient
    }

    private let directory: URL?
    private let session: URLSession
    private var inFlight: [String: Task<Data?, Never>] = [:]
    private var cleanedLegacyCache = false

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
        cleanLegacyCacheIfNeeded(in: directory)
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
                try? png.write(to: hit, options: Self.writeOptions)
                try? files.removeItem(at: miss)
                return png
            case .definitiveMiss:
                continue
            case .transient:
                sawTransient = true
            }
        }
        // Solo un "no hay" seguro en los dos dominios se recuerda (escribir atómicamente renueva su fecha y protección).
        if !sawTransient { try? Data().write(to: miss, options: Self.writeOptions) }
        return nil
    }

    /// Borra una sola vez los archivos heredados con el nombre del comercio en claro en `Caches/Logos`.
    func cleanLegacyCache() {
        guard let directory else { return }
        cleanLegacyCacheIfNeeded(in: directory)
    }

    private func cleanLegacyCacheIfNeeded(in directory: URL) {
        guard !cleanedLegacyCache else { return }
        cleanedLegacyCache = true
        let files = FileManager.default
        guard let entries = try? files.contentsOfDirectory(atPath: directory.path) else { return }
        for old in LogoCachePolicy.legacyFilesToRemove(in: entries) {
            try? files.removeItem(at: directory.appending(path: old))
        }
    }

    private func fetch(domain: String) async -> Fetch {
        var components = URLComponents(string: "https://www.google.com/s2/favicons")
        components?.queryItems = [URLQueryItem(name: "domain", value: domain), URLQueryItem(name: "sz", value: "128")]
        guard let url = components?.url else { return .definitiveMiss }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.httpShouldHandleCookies = false
        // Sin red, tiempo agotado, cancelado...: pasajero.
        guard case let (bytes, response)? = try? await session.bytes(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return .transient }
        switch status {
        case 200:
            do {
                // SEC-07: corta la descarga en streaming en cuanto supera `maximumBytes`.
                let data = try await collectCapped(
                    bytes,
                    expectedLength: response.expectedContentLength,
                    limit: Self.maximumBytes
                )
                return Self.isRealLogo(data) ? .logo(data) : .definitiveMiss
            } catch CappedDownloadError.tooLarge {
                return .definitiveMiss
            } catch {
                return .transient
            }
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

    /// Nombre de archivo por hash SHA-256 de la clave normalizada (nunca el nombre del comercio en claro).
    private static func fileName(for key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return LogoCachePolicy.fileName(forHashHex: hex)
    }
}
