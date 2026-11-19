import UIKit
import MiBancoCore

/// Logos que viajan dentro de la app (carpeta `Logos` del paquete, ver tools/fetch_logos.py): sin red.
/// También lo usa la notificación ampliada, que lleva su propia copia de la carpeta.
enum BundledLogos {
    @MainActor private static var cache: [String: UIImage] = [:]
    @MainActor private static var missing: Set<String> = []

    /// "mercadona.es" -> su logo, o nil si no se bajó (entonces se queda el monograma).
    @MainActor static func image(domain: String) -> UIImage? {
        if let hit = cache[domain] { return hit }
        if missing.contains(domain) { return nil }
        guard let url = Bundle.main.url(forResource: domain, withExtension: "png", subdirectory: "Logos"),
              let image = UIImage(contentsOfFile: url.path) else {
            missing.insert(domain)
            return nil
        }
        cache[domain] = image
        return image
    }

    /// Solo lo que ya está en memoria: para las filas, que nunca leen del disco mientras se pintan.
    @MainActor static func cached(domain: String) -> UIImage? { cache[domain] }

    /// Lee y decodifica fuera del hilo principal los logos que aún no están en memoria.
    @MainActor static func prewarm(_ domains: [String]) async {
        let todo = Set(domains).filter { cache[$0] == nil && !missing.contains($0) }
        guard !todo.isEmpty else { return }
        let urls = todo.map { ($0, Bundle.main.url(forResource: $0, withExtension: "png", subdirectory: "Logos")) }
        let loaded: [(String, UIImage?)] = await Task.detached(priority: .userInitiated) {
            urls.map { domain, url in
                (domain, url.flatMap { UIImage(contentsOfFile: $0.path)?.preparingForDisplay() })
            }
        }.value
        for (domain, image) in loaded {
            if let image { cache[domain] = image } else { missing.insert(domain) }
        }
    }
}

extension BankID {
    /// Web del banco: nombre del archivo de su marca en `Logos`.
    var logoDomain: String {
        switch self {
        case .rev: "revolut.com"
        case .ima: "imagin.com"
        case .tr: "traderepublic.com"
        }
    }
}
