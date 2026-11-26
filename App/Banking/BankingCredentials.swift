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
    case demo
    case keychain(KeychainError)

    var message: String {
        switch self {
        case .publicKeyGiven:
            "Este archivo es la clave pública. Elige el .pem que se descargó al registrar la app."
        case .encrypted:
            "Esta clave está protegida con contraseña. Vuelve a crear la app en Enable Banking con «generar en el navegador»."
        case .demo:
            "En modo de prueba no se conecta con bancos reales."
        case .keychain:
            bankingCredentialMessage(.keychain)
        default:
            bankingCredentialMessage(.invalidKey)
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

        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            throw BankingCredentialsError.unreadable
        }
        guard size <= maxKeyFileBytes else {
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
        #if DEBUG
        if DemoMode.isActive { throw BankingCredentialsError.demo }
        #endif
        guard isValidApplicationID(appID) else { throw BankingCredentialsError.invalidAppID }
        do {
            try KeychainVault.savePrivateKey(pkcs1DER: pkcs1DER)
            try KeychainVault.set(Data(appID.lowercased().utf8), for: .appID)
        } catch is RSASignerError {
            throw BankingCredentialsError.invalidKey
        } catch let error as KeychainError {
            throw BankingCredentialsError.keychain(error)
        }
    }

    static var isReady: Bool {
        #if DEBUG
        if DemoMode.isActive { return DemoMode.banksConnected }
        #endif
        guard let id = try? KeychainVault.data(for: .appID), !id.isEmpty,
              KeychainVault.hasPrivateKey() else { return false }
        return true
    }

    static func client() throws -> EnableBankingClient {
        #if DEBUG
        if DemoMode.isActive { throw BankingCredentialsError.demo }
        #endif
        guard let idData = try KeychainVault.data(for: .appID), let appID = String(data: idData, encoding: .utf8),
              let key = try KeychainVault.loadPrivateKey() else {
            throw BankingCredentialsError.invalidKey
        }
        return EnableBankingClient(
            transport: URLSessionTransport(), signer: RSASigner(key: key), appID: appID,
            now: { Date() })
    }

    /// Orden estricto (U43): primero lee los ids de sesión, borra TODO el Llavero y desvincula el libro en el iPhone,
    /// devuelve la UI a su estado normal, y SOLO DESPUÉS intenta cerrar las sesiones remotas (mejor esfuerzo).
    static func forgetEverything() async {
        #if DEBUG
        if DemoMode.isActive { return }
        #endif
        await MainActor.run {
            BankConnector.shared.isForgetting = true
        }
        let remoteClient = try? client()
        await forgetEverythingPlan(
            readSessionIDs: {
                BankID.allCases.compactMap { bank in
                    (try? KeychainVault.codable(StoredSession.self, for: KeychainVault.session(for: bank)))?.sessionID
                }
            },
            deleteLocal: {
                await MainActor.run {
                    BankConnector.shared.resetForForgetEverything()
                }
                try? KeychainVault.deleteAll()
            },
            unlinkLedger: {
                _ = try? SharedStore.make().update { ledger in
                    for bank in BankID.allCases {
                        ledger.setLink(bank, nil)
                        if let balance = ledger.state.balances[bank], balance.origin == .bank {
                            ledger.adoptBalance(bank, cents: balance.cents, at: balance.setAt, origin: .manual)
                        }
                    }
                }
                await BankReminders.reschedule(links: [:])
                NotificationCenter.default.post(name: .ledgerDidSyncFromBank, object: nil)
                await MainActor.run {
                    BankConnector.shared.isForgetting = false
                }
            },
            deleteRemote: { sessionID in
                if let remoteClient {
                    try? await remoteClient.deleteSession(id: sessionID)
                }
            }
        )
    }
}
