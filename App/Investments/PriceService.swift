import Foundation
import MiBancoCore

/// Consulta de precios de mercado en Yahoo Finance (sin clave, solo con el ISIN o el símbolo).
/// Sesión efímera, sin cookies ni caché, tiempo máximo de 10 s. Nunca envía importes, acciones ni nombres.
struct PriceService: Sendable {
    typealias Fetch = @Sendable (URL) async throws -> Data

    private static let maxResponseBytes = 2_000_000
    private static let maxCandidates = 6

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }()

    private let fetch: Fetch

    init(fetch: @escaping Fetch = PriceService.defaultFetch) {
        self.fetch = fetch
    }

    /// Busca el precio actual en euros de un instrumento y devuelve el símbolo resuelto junto con su cotización.
    /// Prueba primero el símbolo ya recordado, luego el símbolo cripto si procede y por último la búsqueda por ISIN.
    func quote(for instrument: String, assetClass: String?, knownSymbol: String?) async -> (symbol: String, quote: Quote)? {
        #if DEBUG
        if DemoMode.isActive { return nil }
        #endif
        guard !Task.isCancelled else { return nil }

        var tried = Set<String>()

        if let known = knownSymbol, !known.isEmpty {
            tried.insert(known)
            if let q = await fetchChart(symbol: known) {
                return (known, q)
            }
        }

        if let crypto = cryptoSymbol(instrument: instrument, assetClass: assetClass),
           tried.insert(crypto).inserted {
            if let q = await fetchChart(symbol: crypto) {
                return (crypto, q)
            }
        }

        if isISIN(instrument), let searchURL = yahooSearchURL(isin: instrument) {
            guard !Task.isCancelled else { return nil }
            if let data = try? await fetch(searchURL) {
                let candidates = preferredSymbols(yahooSearchCandidates(data)).prefix(Self.maxCandidates)
                for candidate in candidates {
                    guard !Task.isCancelled else { return nil }
                    guard tried.insert(candidate).inserted else { continue }
                    if let q = await fetchChart(symbol: candidate) {
                        return (candidate, q)
                    }
                }
            }
        } else if tried.insert(instrument).inserted {
            if let q = await fetchChart(symbol: instrument) {
                return (instrument, q)
            }
        }

        return nil
    }

    private func fetchChart(symbol: String) async -> Quote? {
        guard !Task.isCancelled, let url = yahooChartURL(symbol: symbol) else { return nil }
        guard let data = try? await fetch(url) else { return nil }
        switch yahooChartQuote(data, fetchedAt: Date()) {
        case .success(let quote):
            return quote
        case .failure:
            return nil
        }
    }

    private static func defaultFetch(_ url: URL) async throws -> Data {
        #if DEBUG
        if DemoMode.isActive { throw URLError(.cancelled) }
        #endif
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 10
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              data.count <= maxResponseBytes else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
