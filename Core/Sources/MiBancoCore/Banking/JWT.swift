import Foundation

/// Firma RSASSA-PKCS1-v1_5 con SHA-256. La implementa la app (Security.framework); Core no hace criptografía.
public protocol JWTSigner: Sendable {
    func signRS256(_ message: Data) throws -> Data
}

/// Base64 URL-safe sin relleno.
public func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

/// Vida por defecto de cada JWT de Enable Banking (300 s, margen amplio para deriva de reloj; SEC-10).
public let enableBankingDefaultJWTLifetime: TimeInterval = 300

/// "cabecera.reclamaciones" en base64url, con claves ordenadas para que sea estable byte a byte.
/// La vida máxima de un JWT de Enable Banking es 86400 s.
public func enableBankingJWTSigningInput(appID: String, now: Date, lifetime: TimeInterval) -> String {
    let iat = Int(now.timeIntervalSince1970.rounded(.down))
    // NaN o infinito no deben tumbar la app: se usa la vida por defecto.
    let safeLifetime = lifetime.isFinite ? lifetime : enableBankingDefaultJWTLifetime
    let life = Int(min(max(safeLifetime, 1), 86_400))
    let header: [String: Any] = ["typ": "JWT", "alg": "RS256", "kid": appID]
    let claims: [String: Any] = [
        "iss": "enablebanking.com", "aud": "api.enablebanking.com", "iat": iat, "exp": iat + life,
    ]
    func encode(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return base64URL(data)
    }
    return encode(header) + "." + encode(claims)
}

public func enableBankingJWT(
    appID: String, now: Date, lifetime: TimeInterval = enableBankingDefaultJWTLifetime, signer: any JWTSigner
) throws -> String {
    let input = enableBankingJWTSigningInput(appID: appID, now: now, lifetime: lifetime)
    let signature = try signer.signRS256(Data(input.utf8))
    return input + "." + base64URL(signature)
}
