import Foundation

/// Qué le pasa a la conexión con un banco, en términos que la app sabe explicar.
public enum SyncProblem: String, Codable, Equatable, Sendable {
    case consentExpired, rateLimited, bankUnavailable, offline, keyRejected, unknown
}

/// El código `error` de la API manda sobre el estado HTTP; si el cuerpo no es JSON
/// (o el código no se conoce) se decide por el estado.
public func classifyEnableBankingError(status: Int, body: Data) -> SyncProblem {
    if let code = enableBankingErrorCode(body) {
        switch code {
        case "EXPIRED_SESSION", "REVOKED_SESSION", "CLOSED_SESSION", "SESSION_DOES_NOT_EXIST":
            return .consentExpired
        case "ASPSP_RATE_LIMIT_EXCEEDED":
            return .rateLimited
        case "ASPSP_ERROR", "ASPSP_TIMEOUT":
            return .bankUnavailable
        case "UNAUTHORIZED_ACCESS":
            return .keyRejected
        default:
            break
        }
    }
    switch status {
    case 401: return .keyRejected
    case 429: return .rateLimited
    case 408: return .bankUnavailable
    case 500...: return .bankUnavailable
    default: return .unknown
    }
}

/// El valor de `error` del cuerpo de error de la API, si lo hay.
public func enableBankingErrorCode(_ body: Data) -> String? {
    guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
    return object["error"] as? String
}
