import Foundation

public enum BankingConstants {
    public static let apiBase = URL(string: "https://api.enablebanking.com")!
    public static let redirectURL = URL(string: "https://goooojoooooooo.github.io/mi-banco-build/cb/")!
    public static let callbackScheme = "mibanco"
    public static let country = "ES"
    public static let maxPages = 50
    public static let maxResponseBytes = 10 * 1024 * 1024
    public static let jwtLifetime: TimeInterval = enableBankingDefaultJWTLifetime
}

public enum TransactionStrategy: String, Sendable {
    case standard = "default"
    case longest
}

/// Lo recibido de una cuenta. `complete == false`: se cortó (límite de páginas o clave repetida); lo recibido sirve.
public struct TransactionFetch: Equatable, Sendable {
    public let transactions: [EBTransaction]
    public let complete: Bool

    public init(transactions: [EBTransaction], complete: Bool) {
        self.transactions = transactions
        self.complete = complete
    }
}

/// Cliente de solo lectura (AIS) de Enable Banking. Cada petición lleva un JWT nuevo de 300 s.
public struct EnableBankingClient: Sendable {
    private let transport: any HTTPTransport
    private let signer: any JWTSigner
    private let appID: String
    private let now: @Sendable () -> Date

    public init(
        transport: any HTTPTransport, signer: any JWTSigner, appID: String,
        now: @escaping @Sendable () -> Date
    ) {
        self.transport = transport
        self.signer = signer
        self.appID = appID
        self.now = now
    }

    public func aspsps(country: String) async throws -> [EBASPSP] {
        struct Response: Decodable { let aspsps: [EBASPSP] }
        let data = try await call("GET", "/aspsps", query: [("country", country)])
        return try decode(Response.self, from: data).aspsps
    }

    /// Devuelve la dirección del banco donde el usuario da su consentimiento.
    public func startAuth(aspsp: EBASPSP, validUntil: Date, state: String) async throws -> URL {
        struct Response: Decodable { let url: String }
        let body: [String: Any] = [
            "access": ["valid_until": enableBankingTimestamp(validUntil)],
            "aspsp": ["name": aspsp.name, "country": aspsp.country],
            "state": state,
            "redirect_url": BankingConstants.redirectURL.absoluteString,
            "psu_type": "personal",
            "language": "es",
        ]
        let data = try await call("POST", "/auth", body: try jsonBody(body))
        let text = try decode(Response.self, from: data).url
        guard let url = URL(string: text), url.scheme?.lowercased() == "https", url.host != nil else {
            throw BankingClientError.badResponse
        }
        return url
    }

    public func createSession(code: String) async throws -> EBSession {
        try await authorizeSession(code: code).session
    }

    /// Crea la sesión con el banco y extrae aparte (sin tocar `EBSession` ni `EBAccount`) el IBAN principal en euros, si es inequívoco.
    public func authorizeSession(code: String) async throws -> EBSessionAuthorization {
        let data = try await call("POST", "/sessions", body: try jsonBody(["code": code]))
        let session = try decode(EBSession.self, from: data)
        return EBSessionAuthorization(session: session, primaryEuroIBAN: extractPrimaryEuroIBAN(fromSessionData: data))
    }

    public func balances(
        accountUID: String, psuHeaders: [String: String]? = nil
    ) async throws -> [EBBalance] {
        struct Response: Decodable { let balances: [EBBalance] }
        let data = try await call("GET", "/accounts/\(escape(accountUID))/balances", psuHeaders: psuHeaders)
        return try decode(Response.self, from: data).balances
    }

    /// Sigue `continuation_key` hasta agotarlo; más de `maxPages` páginas es `.tooManyPages`.
    /// `dateFrom` es `yyyy-MM-dd` (lo formatea quien llama). Quien quiera quedarse con lo recibido usa `fetchTransactions`.
    public func transactions(
        accountUID: String, dateFrom: String, strategy: TransactionStrategy,
        psuHeaders: [String: String]? = nil
    ) async throws -> [EBTransaction] {
        let fetch = try await fetchTransactions(
            accountUID: accountUID, dateFrom: dateFrom, strategy: strategy, psuHeaders: psuHeaders)
        guard fetch.complete else { throw BankingClientError.tooManyPages }
        return fetch.transactions
    }

    /// Como `transactions`, pero con el límite de páginas o una clave de continuación repetida (el banco da vueltas) se
    /// para y devuelve lo recibido con `complete == false`, en vez de tirarlo. Un fallo de red o de la API sí se propaga.
    public func fetchTransactions(
        accountUID: String, dateFrom: String, strategy: TransactionStrategy,
        psuHeaders: [String: String]? = nil
    ) async throws -> TransactionFetch {
        struct Page: Decodable {
            let transactions: [EBTransaction]?
            let continuationKey: String?
            enum CodingKeys: String, CodingKey {
                case transactions
                case continuationKey = "continuation_key"
            }
        }
        var all: [EBTransaction] = []
        var key: String?
        var seenKeys = Set<String>()
        for _ in 0..<BankingConstants.maxPages {
            var query = [("date_from", dateFrom), ("strategy", strategy.rawValue)]
            if let key { query.append(("continuation_key", key)) }
            let data = try await call(
                "GET", "/accounts/\(escape(accountUID))/transactions", query: query, psuHeaders: psuHeaders)
            let page = try decode(Page.self, from: data)
            all += page.transactions ?? []
            guard let next = page.continuationKey, !next.isEmpty else {
                return TransactionFetch(transactions: all, complete: true)
            }
            // Una clave ya vista en cualquier página anterior: el banco da vueltas y no avanza.
            guard seenKeys.insert(next).inserted else {
                return TransactionFetch(transactions: all, complete: false)
            }
            key = next
        }
        return TransactionFetch(transactions: all, complete: false)
    }

    public func deleteSession(id: String) async throws {
        _ = try await call("DELETE", "/sessions/\(escape(id))")
    }

    // MARK: - Interno

    private func call(
        _ method: String, _ path: String, query: [(String, String)] = [], body: Data? = nil,
        psuHeaders: [String: String]? = nil
    ) async throws -> Data {
        let token: String
        do {
            token = try enableBankingJWT(appID: appID, now: now(), lifetime: BankingConstants.jwtLifetime, signer: signer)
        } catch {
            // La firma falla cuando la clave guardada no sirve.
            throw BankingClientError.api(.keyRejected, code: nil)
        }
        var text = BankingConstants.apiBase.absoluteString + path
        if !query.isEmpty {
            text += "?" + query.map { "\(escape($0.0))=\(escape($0.1))" }.joined(separator: "&")
        }
        guard let url = URL(string: text) else { throw BankingClientError.badResponse }
        var headers: [String: String] = [
            "Accept": "application/json",
            "Authorization": "Bearer " + token,
            "Content-Type": "application/json",
        ]
        if let psuHeaders {
            for (name, value) in sanitizePSUHeaders(psuHeaders) {
                headers[name] = value
            }
        }
        let request = HTTPRequest(method: method, url: url, headers: headers, body: body)
        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where error.code == .dataLengthExceedsMaximum {
            throw BankingClientError.badResponse
        } catch {
            throw BankingClientError.offline
        }
        guard (200..<300).contains(response.status) else {
            throw BankingClientError.api(
                classifyEnableBankingError(status: response.status, body: response.body),
                code: enableBankingErrorCode(response.body))
        }
        return response.body
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw BankingClientError.badResponse
        }
    }

    private func jsonBody(_ object: [String: Any]) throws -> Data {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            throw BankingClientError.badResponse
        }
        return data
    }

    /// Escapa para ruta y consulta: solo quedan letras, cifras y `-._~`.
    private func escape(_ s: String) -> String {
        // Conjunto ASCII explícito: `alphanumerics` deja pasar letras y cifras no ASCII.
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

/// "2027-05-19T11:00:00+00:00" (UTC, sin fracción), a mano para no depender de la plataforma.
func enableBankingTimestamp(_ date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    func two(_ n: Int?) -> String {
        let v = n ?? 0
        return v < 10 ? "0\(v)" : "\(v)"
    }
    return "\(c.year ?? 1970)-\(two(c.month))-\(two(c.day))T\(two(c.hour)):\(two(c.minute)):\(two(c.second))+00:00"
}
