import Foundation
import MiBancoCore

/// Rechaza cualquier redirección HTTP 3xx para no reenviar cabeceras `Authorization` ni seguir destinos inesperados.
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// Transporte HTTP real. Sesión efímera: sin caché, sin cookies, sin credenciales en disco,
/// sin redirecciones automáticas y con tope de tamaño de respuesta en streaming (SEC-09).
struct URLSessionTransport: HTTPTransport {
    private static let noRedirectDelegate = NoRedirectDelegate()
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        session = URLSession(configuration: configuration)
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        do {
            let (bytes, response) = try await session.bytes(for: urlRequest, delegate: Self.noRedirectDelegate)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if (300..<400).contains(http.statusCode) {
                return HTTPResponse(status: http.statusCode, body: Data())
            }
            let data: Data
            do {
                data = try await collectCapped(
                    bytes,
                    expectedLength: response.expectedContentLength,
                    limit: BankingConstants.maxResponseBytes
                )
            } catch CappedDownloadError.tooLarge {
                throw URLError(.dataLengthExceedsMaximum)
            }
            return HTTPResponse(status: http.statusCode, body: data)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        }
    }
}
