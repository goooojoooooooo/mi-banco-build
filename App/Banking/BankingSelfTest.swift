#if DEBUG
import Foundation
import MiBancoCore
import Security
import SwiftUI

/// Autoprueba del simulador: prueba que la firma RS256 se produce y se verifica, y que el Llavero guarda y borra.
/// Se abre con el argumento de lanzamiento `-MiBancoSelfTest`. Las claves se generan en ejecución.
enum BankingSelfTest {
    static let testService = "com.mibanco.banking.selftest"

    static func run() async -> String {
        // 1. Clave RSA-2048 en memoria (no permanente) y su PKCS#1.
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048,
            kSecAttrIsPermanent: false,
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey),
              let pkcs1 = SecKeyCopyExternalRepresentation(privateKey, &error) as Data?
        else { return failure("clave") }

        // 2. PKCS#8 y PEM, con la misma estructura DER que el test de Core; el PEM se monta por concatenación.
        let pkcs8 = der(0x30, [0x02, 0x01, 0x00] + der(0x30, rsaOID + [0x05, 0x00]) + der(0x04, [UInt8](pkcs1)))
        let b64 = Data(pkcs8).base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        let label = "PRIVATE KEY"
        let pem = "-----BEGIN " + label + "-----\n" + b64 + "\n-----END " + label + "-----\n"

        // 3. El PEM vuelve a los mismos bytes.
        guard let back = try? rsaPKCS1DER(fromPEM: pem), back == pkcs1 else { return failure("pem") }

        // 4. JWT firmado y verificado con la clave pública.
        guard let signer = try? RSASigner(pkcs1DER: back) else { return failure("firmante") }
        let appID = "00000000-0000-4000-8000-000000000001"
        let now = Date()
        guard let jwt = try? enableBankingJWT(appID: appID, now: now, signer: signer) else { return failure("firma") }
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return failure("jwt") }
        let input = String(parts[0]) + "." + String(parts[1])
        guard input == enableBankingJWTSigningInput(appID: appID, now: now, lifetime: BankingConstants.jwtLifetime),
              let signature = base64URLDecode(String(parts[2])) else { return failure("jwt") }
        let signedInput = Data(input.utf8)
        guard SecKeyVerifySignature(
            publicKey, .rsaSignatureMessagePKCS1v15SHA256, signedInput as CFData, signature as CFData, &error)
        else { return failure("verificacion") }
        // Una firma sobre otro texto no debe verificar.
        let other = Data("otro".utf8)
        if SecKeyVerifySignature(
            publicKey, .rsaSignatureMessagePKCS1v15SHA256, other as CFData, signature as CFData, nil) {
            return failure("verificacion")
        }

        // 5. Llavero con otro servicio: guardar, leer, actualizar, borrar.
        let secret = Data("valor-de-prueba".utf8)
        do {
            try KeychainVault.set(secret, for: .appID, service: testService)
            guard try KeychainVault.data(for: .appID, service: testService) == secret else {
                try? KeychainVault.deleteAll(service: testService)
                return failure("llavero (lectura distinta)")
            }
            try KeychainVault.set(Data("otro".utf8), for: .appID, service: testService)
            guard try KeychainVault.data(for: .appID, service: testService) == Data("otro".utf8) else {
                try? KeychainVault.deleteAll(service: testService)
                return failure("llavero (actualizacion distinta)")
            }
            try KeychainVault.delete(.appID, service: testService)
            guard try KeychainVault.data(for: .appID, service: testService) == nil else { return failure("llavero (borrado sin efecto)") }

            // 5b. Migración automática de clave privada heredada (generic password -> kSecClassKey) y firma directa.
            try KeychainVault.deleteAll(service: testService)
            try KeychainVault.set(back, for: .privateKey, service: testService)
            guard KeychainVault.hasPrivateKey(service: testService) else {
                try? KeychainVault.deleteAll(service: testService)
                return failure("llavero (clave heredada ausente)")
            }
            guard let migratedKey = try KeychainVault.loadPrivateKey(service: testService) else {
                try? KeychainVault.deleteAll(service: testService)
                return failure("llavero (migracion a kSecClassKey)")
            }
            // El elemento heredado debe desaparecer tras migrar a kSecClassKey.
            guard try KeychainVault.data(for: .privateKey, service: testService) == nil else {
                try? KeychainVault.deleteAll(service: testService)
                return failure("llavero (heredado sin borrar)")
            }
            let migratedSigner = RSASigner(key: migratedKey)
            guard let migratedJWT = try? enableBankingJWT(appID: appID, now: now, signer: migratedSigner) else {
                try? KeychainVault.deleteAll(service: testService)
                return failure("firma (clave migrada)")
            }
            let migratedParts = migratedJWT.split(separator: ".", omittingEmptySubsequences: false)
            guard migratedParts.count == 3,
                  let migratedSig = base64URLDecode(String(migratedParts[2])),
                  SecKeyVerifySignature(
                      publicKey, .rsaSignatureMessagePKCS1v15SHA256,
                      Data((String(migratedParts[0]) + "." + String(migratedParts[1])).utf8) as CFData,
                      migratedSig as CFData, &error)
            else {
                try? KeychainVault.deleteAll(service: testService)
                return failure("verificacion (clave migrada)")
            }

            // 5c. Guardado directo de kSecClassKey, sustitución y borrado completo.
            try KeychainVault.savePrivateKey(pkcs1DER: back, service: testService)
            guard let reloadedKey = try KeychainVault.loadPrivateKey(service: testService),
                  let reloadedJWT = try? enableBankingJWT(appID: appID, now: now, signer: RSASigner(key: reloadedKey)),
                  reloadedJWT.split(separator: ".").count == 3
            else {
                try? KeychainVault.deleteAll(service: testService)
                return failure("llavero (recarga kSecClassKey)")
            }
            try KeychainVault.deleteAll(service: testService)
            guard !KeychainVault.hasPrivateKey(service: testService) else {
                return failure("llavero (deleteAll no borro kSecClassKey)")
            }
        } catch {
            try? KeychainVault.deleteAll(service: testService)
            // El código del sistema (OSStatus) no es secreto y dice por qué falla el Llavero.
            if case KeychainError.status(let code) = error { return failure("llavero (\(code))") }
            return failure("llavero (\(error))")
        }

        // 6. El transporte se construye (no se envía nada).
        _ = URLSessionTransport()
        return "Autoprueba: OK"
    }

    private static func failure(_ step: String) -> String { "Autoprueba: falla en \(step)" }

    private static let rsaOID: [UInt8] = [0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01]

    private static func der(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
        let n = content.count
        if n < 128 { return [tag, UInt8(n)] + content }
        if n < 256 { return [tag, 0x81, UInt8(n)] + content }
        if n < 65_536 { return [tag, 0x82, UInt8(n >> 8), UInt8(n & 0xff)] + content }
        return [tag, 0x83, UInt8(n >> 16), UInt8((n >> 8) & 0xff), UInt8(n & 0xff)] + content
    }

    private static func base64URLDecode(_ text: String) -> Data? {
        var s = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }
}

struct BankingSelfTestView: View {
    @State private var result = "Autoprueba: en curso"

    var body: some View {
        Text(result)
            .padding()
            .task { result = await BankingSelfTest.run() }
    }
}
#endif
