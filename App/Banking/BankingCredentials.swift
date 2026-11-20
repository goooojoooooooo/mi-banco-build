import Foundation
import MiBancoCore

/// Por qué no se pudo leer o guardar la clave. El mensaje nunca incluye el contenido del archivo.
enum BankingCredentialsError: Error, Equatable {
    case publicKeyGiven
    case encrypted
    case invalidKey
    case tooLarge
    case unreadable
    case invalidAppID
    case keychain(KeychainError)

    var message: String {
        switch self {
        case .publicKeyGiven:
            "Este archivo es la clave pública. Elige el .pem que se descargó al registrar la app."
        case .encrypted:
            "Esta clave está protegida con contraseña. Vuelve a crear la app en Enable Banking con «generar en el navegador»."
        default:
            "No es una clave válida. Elige el archivo .pem de Enable Banking."
        }
    }
}

/// Alta, uso y baja de las credenciales del banco. Todo secreto va al Llavero; nada se copia a otro sitio.
enum BankingCredentials {
    /// Una clave RSA-4096 en PEM ocupa unos 3,2 KB: 16 KB sobra y corta archivos que no son una clave.
    static let maxKeyFileBytes = 16 * 1024

    /// Lee el archivo elegido con acceso acotado de seguridad, lo valida y devuelve solo los bytes de la clave.
    /// El texto del archivo no sobrevive a esta función.
    static func readKeyFile(_ url: URL) throws -> (pkcs1DER: Data, suggestedAppID: String?) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxKeyFileBytes {
            throw BankingCredentialsError.tooLarge
        }
        guard let data = try? Data(contentsOf: url) else { throw BankingCredentialsError.unreadable }
        guard data.count <= maxKeyFileBytes else { throw BankingCredentialsError.tooLarge }
        guard let text = String(data: data, encoding: .utf8) else { throw BankingCredentialsError.invalidKey }

        let der: Data
        do {
            der = try rsaPKCS1DER(fromPEM: text)
        } catch PrivateKeyPEMError.publicKeyGiven {
            throw BankingCredentialsError.publicKeyGiven
        } catch PrivateKeyPEMError.encrypted {
            throw BankingCredentialsError.encrypted
        } catch {
            throw BankingCredentialsError.invalidKey
        }
        // Que el sistema la acepte como clave RSA privada.
        do { _ = try RSASigner(pkcs1DER: der) } catch { throw BankingCredentialsError.invalidKey }
        return (der, applicationID(fromKeyFileName: url.lastPathComponent))
    }

    static func save(appID: String, pkcs1DER: Data) throws {
        guard isValidApplicationID(appID) else { throw BankingCredentialsError.invalidAppID }
        do {
            try KeychainVault.set(pkcs1DER, for: .privateKey)
            try KeychainVault.set(Data(appID.lowercased().utf8), for: .appID)
        } catch let error as KeychainError {
            throw BankingCredentialsError.keychain(error)
        }
    }

    static var isReady: Bool {
        guard let id = try? KeychainVault.data(for: .appID), !id.isEmpty,
              let key = try? KeychainVault.data(for: .privateKey), !key.isEmpty else { return false }
        return true
    }

    static func client() throws -> EnableBankingClient {
        guard let idData = try KeychainVault.data(for: .appID), let appID = String(data: idData, encoding: .utf8),
              let der = try KeychainVault.data(for: .privateKey) else {
            throw BankingCredentialsError.invalidKey
        }
        return EnableBankingClient(
            transport: URLSessionTransport(), signer: try RSASigner(pkcs1DER: der), appID: appID,
            now: { Date() })
    }

    /// Mejor esfuerzo: cierra las sesiones en el banco, borra todo el Llavero y deja los saldos del banco como
    /// manuales con el mismo valor. Los fallos no se propagan: desconectar nunca debe quedarse a medias.
    static func forgetEverything() async {
        if let client = try? client() {
            for bank in BankID.allCases {
                if let session = try? KeychainVault.codable(StoredSession.self, for: KeychainVault.session(for: bank)) {
                    try? await client.deleteSession(id: session.sessionID)
                }
            }
        }
        try? KeychainVault.deleteAll()
        _ = try? SharedStore.make().update { ledger in
            for bank in BankID.allCases {
                ledger.setLink(bank, nil)
                if let balance = ledger.state.balances[bank], balance.origin == .bank {
                    ledger.adoptBalance(bank, cents: balance.cents, at: balance.setAt, origin: .manual)
                }
            }
        }
    }
}
