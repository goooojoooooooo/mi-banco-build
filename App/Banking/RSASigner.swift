import Foundation
import MiBancoCore
import Security

enum RSASignerError: Error, Equatable {
    case invalidKey
    case signingFailed
}

/// Firma RS256 (RSASSA-PKCS1-v1_5 con SHA-256) con Security.framework.
/// Guarda los bytes de la clave y crea la `SecKey` en cada firma: no queda ningún objeto de clave en memoria.
struct RSASigner: JWTSigner, CustomStringConvertible, CustomDebugStringConvertible {
    private let pkcs1DER: Data

    /// Falla si los bytes no son una clave RSA privada PKCS#1 utilizable.
    init(pkcs1DER: Data) throws {
        _ = try Self.makeKey(pkcs1DER)
        self.pkcs1DER = pkcs1DER
    }

    func signRS256(_ message: Data) throws -> Data {
        let key = try Self.makeKey(pkcs1DER)
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

    private static func makeKey(_ der: Data) throws -> SecKey {
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
