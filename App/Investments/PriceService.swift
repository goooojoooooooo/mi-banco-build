import Foundation
import MiBancoCore

/// Consulta de precios de mercado en Yahoo Finance (sin clave, solo con el ISIN o el símbolo).
/// Sesión efímera, sin cookies ni caché, tiempo máximo de 10 s. Nunca envía importes, acciones ni nombres.
struct PriceService: Sendable {
    typealias Fetch = @Sendable (URL) async throws -> Data

    private enum FetchFailure: Error {
        /// Fallo de red, tiempo agotado o límite de peticiones (429/5xx): no merece encadenar más consultas.
        case transport
        /// El símbolo no existe o la respuesta no trae precio usable: se puede probar otro candidato.
        case notFound
    }

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
    /// Ante un error de red, cancelación o 429 detiene enseguida la búsqueda para no saturar ni agotar el refresco.
    func quote(for instrument: String, assetClass: String?, knownSymbol: String?) async -> (symbol: String, quote: Quote)? {
        #if DEBUG
        if DemoMode.isActive { return nil }
        #endif
        guard !Task.isCancelled else { return nil }

        var tried = Set<String>()

        do {
            if let known = knownSymbol, !known.isEmpty {
                tried.insert(known)
                if let q = try await fetchChart(symbol: known) {
                    return (known, q)
                }
            }

            if let crypto = cryptoSymbol(instrument: instrument, assetClass: assetClass),
               tried.insert(crypto).inserted {
                if let q = try await fetchChart(symbol: crypto) {
                    return (crypto, q)
                }
            }

            if isISIN(instrument), let searchURL = yahooSearchURL(isin: instrument) {
                guard !Task.isCancelled else { return nil }
                if let data = try await fetchPayload(from: searchURL) {
                    let candidates = preferredSymbols(yahooSearchCandidates(data)).prefix(Self.maxCandidates)
                    for candidate in candidates {
                        guard !Task.isCancelled else { return nil }
                        guard tried.insert(candidate).inserted else { continue }
                        if let q = try await fetchChart(symbol: candidate) {
                            return (candidate, q)
                        }
                    }
                }
            } else if tried.insert(instrument).inserted {
                if let q = try await fetchChart(symbol: instrument) {
                    return (instrument, q)
                }
            }
        } catch {
            // Fallo de transporte, cancelación o 429: salimos sin cascada de reintentos.
            return nil
        }

        return nil
    }

    private func fetchChart(symbol: String) async throws -> Quote? {
        guard !Task.isCancelled else { throw FetchFailure.transport }
        guard let url = yahooChartURL(symbol: symbol) else { return nil }
        guard let data = try await fetchPayload(from: url) else { return nil }
        switch yahooChartQuote(data, fetchedAt: Date()) {
        case .success(let quote):
            return quote
        case .failure:
            return nil
        }
    }

    private func fetchPayload(from url: URL) async throws -> Data? {
        do {
            return try await fetch(url)
        } catch FetchFailure.notFound {
            return nil
        } catch {
            throw FetchFailure.transport
        }
    }

    private static func defaultFetch(_ url: URL) async throws -> Data {
        #if DEBUG
        if DemoMode.isActive { throw FetchFailure.transport }
        #endif
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 10
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FetchFailure.transport
        }
        if http.statusCode == 404 {
            throw FetchFailure.notFound
        }
        guard (200...299).contains(http.statusCode), data.count <= maxResponseBytes else {
            throw FetchFailure.transport
        }
        return data
    }
}
