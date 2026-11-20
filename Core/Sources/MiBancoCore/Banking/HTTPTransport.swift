import Foundation

public struct HTTPRequest: Equatable, Sendable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?

    public init(method: String, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Equatable, Sendable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// La app pone aquí URLSession; los tests, un transporte falso. Core no abre conexiones.
public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

public enum BankingClientError: Error, Equatable {
    /// Respuesta no 2xx. `code` es el campo `error` de la API (p. ej. `EXPIRED_AUTHORIZATION_CODE`).
    case api(SyncProblem, code: String?)
    case offline
    case tooManyPages
    case badResponse
}
