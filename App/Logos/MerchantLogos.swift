import SwiftUI
import MiBancoCore

/// Logo de cada fila. Si el directorio conoce el comercio, el del paquete (sin red). Si no, y el ajuste
/// "Descargar logos que falten" está activo, uno buscado por el dominio adivinado (ver `LogoFetcher`).
/// "No usar este logo" lo recuerda por comercio y vuelve al monograma.
@MainActor @Observable
final class MerchantLogos {
    /// Clave de @AppStorage del ajuste; sin valor guardado cuenta como desactivado (opt-in, SEC-07).
    static let downloadsKey = "logoDownloads"
    private static let blockedKey = "logoBlocked"

    private(set) var blocked: Set<String>
    private var downloaded: [String: UIImage] = [:]
    /// Sube cuando `prewarm` deja logos nuevos en memoria: las filas que los leen se vuelven a pintar.
    private(set) var revision = 0
    @ObservationIgnored private var requested: Set<String> = []
    private let fetcher = LogoFetcher()

    /// Copia observada del ajuste (Ajustes lo guarda con @AppStorage y avisa con `setDownloadsEnabled`).
    private(set) var downloadsEnabled: Bool

    init() {
        blocked = Set(UserDefaults.standard.stringArray(forKey: Self.blockedKey) ?? [])
        downloadsEnabled = UserDefaults.standard.object(forKey: Self.downloadsKey) as? Bool
            ?? LogoCachePolicy.defaultDownloadsEnabled
        let fetcher = self.fetcher
        Task {
            #if DEBUG
            if DemoMode.isActive { return }
            #endif
            await fetcher.cleanLegacyCache()
        }
    }

    func setDownloadsEnabled(_ enabled: Bool) {
        downloadsEnabled = enabled
    }

    /// `domain`: el del directorio, ya calculado en el snapshot. Un logo bajado de internet solo se muestra
    /// en un pago en tienda (`isShop`), igual que solo para esos se busca.
    func image(merchant: String?, domain: String?, isShop: Bool) -> UIImage? {
        guard let merchant else { return nil }
        let key = normalizeMerchant(merchant)
        guard !key.isEmpty, !blocked.contains(key) else { return nil }
        if let domain {
            _ = revision
            return BundledLogos.cached(domain: domain)
        }
        return downloadsEnabled && isShop ? downloaded[key] : nil
    }

    /// Solo para un PAGO EN TIENDA (`Movement.isShop`, señal positiva del aviso o Apple Pay): nunca para un
    /// envío, un ingreso o un nombre de persona. Como mucho una búsqueda por comercio y sesión; el disco recuerda
    /// aciertos y fallos definitivos entre sesiones. Solo sale el dominio adivinado ("bershka.es"): nunca importes,
    /// saldos, bancos, a quién envías dinero ni el texto del aviso.
    func requestIfNeeded(for movement: Movement, domain: String?) {
        guard movement.isShop, movement.kind == .payment, domain == nil, downloadsEnabled,
              let merchant = movement.merchant else { return }
        let key = normalizeMerchant(merchant)
        guard !key.isEmpty, !blocked.contains(key), !requested.contains(key),
              let slug = guessedLogoSlug(for: merchant) else { return }
        requested.insert(key)
        Task { [weak self, fetcher] in
            guard let data = await fetcher.logo(key: key, slug: slug), let image = UIImage(data: data) else { return }
            self?.downloaded[key] = image
        }
    }

    /// Logo de un banco (ya en memoria tras `prewarm`).
    func bankImage(_ bank: BankID) -> UIImage? {
        _ = revision
        return BundledLogos.cached(domain: bank.logoDomain)
    }

    /// Carga y decodifica fuera del hilo principal los logos que va a pintar la lista; luego avisa a las filas.
    func prewarm(domains: [String]) async {
        let all = domains + BankID.allCases.map(\.logoDomain)
        let before = all.filter { BundledLogos.cached(domain: $0) != nil }.count
        await BundledLogos.prewarm(all)
        if all.filter({ BundledLogos.cached(domain: $0) != nil }).count != before { revision += 1 }
    }

    func block(merchant: String) {
        let key = normalizeMerchant(merchant)
        guard !key.isEmpty else { return }
        blocked.insert(key)
        UserDefaults.standard.set(blocked.sorted(), forKey: Self.blockedKey)
    }
}
