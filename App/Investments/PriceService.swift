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
        // U16: cabeceras genéricas, sin nombre/versión de la app ni idioma del iPhone.
        config.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0", "Accept-Language": "en"]
        return URLSession(configuration: config)
    }()

    private let fetch: Fetch

    init(fetch: @escaping Fetch = PriceService.defaultFetch) {
        self.fetch = fetch
    }

    /// Busca el precio actual en euros de un instrumento y devuelve el símbolo resuelto junto con su cotización.
    /// Prueba primero el símbolo ya recordado, luego el símbolo cripto si procede y por último la búsqueda por ISIN.
    /// Solo sale de este iPhone un código validado por `yahooQueryTerm` (U16).
    func quote(for instrument: String, assetClass: String?, knownSymbol: String?) async -> (symbol: String, quote: Quote)? {
        #if DEBUG
        if DemoMode.isActive { return nil }
        #endif
        guard !Task.isCancelled else { return nil }

        var tried = Set<String>()

        do {
            if let known = knownSymbol, !known.isEmpty,
               let safeKnown = yahooQueryTerm(for: instrument, assetClass: assetClass, rememberedSymbol: known) {
                tried.insert(safeKnown)
                if let q = try await fetchChart(symbol: safeKnown) {
                    return (safeKnown, q)
                }
            }

            if let crypto = cryptoSymbol(instrument: instrument, assetClass: assetClass),
               tried.insert(crypto).inserted {
                if let q = try await fetchChart(symbol: crypto) {
                    return (crypto, q)
                }
            }

            if isISIN(instrument), let safeISIN = yahooQueryTerm(for: instrument),
               let searchURL = yahooSearchURL(isin: safeISIN) {
                guard !Task.isCancelled else { return nil }
                if let data = try await fetchPayload(from: searchURL) {
                    let candidates = preferredSymbols(yahooSearchCandidates(data)).prefix(Self.maxCandidates)
                    for candidate in candidates {
                        guard !Task.isCancelled else { return nil }
                        guard let safeCandidate = yahooQueryTerm(for: candidate),
                              tried.insert(safeCandidate).inserted else { continue }
                        if let q = try await fetchChart(symbol: safeCandidate) {
                            return (safeCandidate, q)
                        }
                    }
                }
            } else if let safeTerm = yahooQueryTerm(for: instrument, assetClass: assetClass),
                      tried.insert(safeTerm).inserted {
                if let q = try await fetchChart(symbol: safeTerm) {
                    return (safeTerm, q)
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
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FetchFailure.transport
        }
        if http.statusCode == 404 {
            throw FetchFailure.notFound
        }
        guard (200...299).contains(http.statusCode) else {
            throw FetchFailure.transport
        }
        do {
            // U10: corta la descarga en cuanto supera `maxResponseBytes`, antes de acumularla entera en memoria.
            return try await collectCapped(bytes, expectedLength: response.expectedContentLength, limit: maxResponseBytes)
        } catch {
            throw FetchFailure.transport
        }
    }
}
