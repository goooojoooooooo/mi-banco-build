import Foundation
import MiBancoCore
import Security

enum RSASignerError: Error, Equatable {
    case invalidKey
    case signingFailed
}

/// Firma RS256 (RSASSA-PKCS1-v1_5 con SHA-256) con Security.framework.
/// Conserva únicamente la referencia `SecKey` (preferiblemente del Llavero, `kSecClassKey`): nunca retiene bytes DER
/// en el heap de Swift (SEC-10). `SecKey` es inmutable y seguro entre hilos según Security.framework.
struct RSASigner: JWTSigner, @unchecked Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    private let key: SecKey

    /// Crea un firmante a partir de una referencia `SecKey` (p. ej. obtenida del Llavero con `kSecReturnRef`).
    init(key: SecKey) {
        self.key = key
    }

    /// Valida bytes RSA PKCS#1 DER y construye una `SecKey` sin retener los bytes DER.
    init(pkcs1DER: Data) throws {
        self.key = try Self.makeKey(pkcs1DER)
    }

    func signRS256(_ message: Data) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            key, .rsaSignatureMessagePKCS1v15SHA256, message as CFData, &error) else {
            _ = error?.takeRetainedValue()
            throw RSASignerError.signingFailed
        }
        return signature as Data
    }

    // Nada sensible en las descripciones.
    var description: String { "RSASigner" }
    var debugDescription: String { "RSASigner" }

    static func makeKey(_ der: Data) throws -> SecKey {
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, &error) else {
            _ = error?.takeRetainedValue()
            throw RSASignerError.invalidKey
        }
        return key
    }
}
