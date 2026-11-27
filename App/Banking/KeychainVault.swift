import Foundation
import MiBancoCore
import Security

/// Fallo del Llavero. Solo lleva el código del sistema: nunca el dato.
enum KeychainError: Error, Equatable, CustomStringConvertible {
    case status(OSStatus)
    case encoding
    case decoding

    var description: String {
        switch self {
        case .status(let code): "Llavero: error \(code)"
        case .encoding: "Llavero: no se pudo codificar"
        case .decoding: "Llavero: dato ilegible"
        }
    }
}

/// Único sitio donde viven la clave privada, el id de la app, las sesiones de banco y la conexión a medias.
/// Los secretos generales son `kSecClassGenericPassword` y la clave RSA privada vive como referencia `kSecClassKey`
/// (migrada automáticamente una sola vez desde el ítem heredado `private-key`), sin iCloud, accesibles tras el
/// primer desbloqueo (un refresco en segundo plano puede correr con el móvil bloqueado) y solo en este dispositivo.
enum KeychainVault {
    static let service = "com.mibanco.banking"

    enum Item: String, CaseIterable {
        case appID = "app-id"
        case privateKey = "private-key"
        case pendingAuth = "pending-auth"
        case sessionRev = "session.rev"
        case sessionIma = "session.ima"
        case sessionTr = "session.tr"
    }

    static func session(for bank: BankID) -> Item {
        switch bank {
        case .rev: .sessionRev
        case .ima: .sessionIma
        case .tr: .sessionTr
        }
    }

    /// Añade o actualiza en una sola operación lógica (nunca hay un instante sin valor): si la actualización no encuentra
    /// el elemento, lo añade. También fija `kSecAttrAccessible` en `SecItemUpdate` (SEC-10).
    /// `service` solo cambia en la autoprueba, que usa otro servicio para no tocar los datos reales.
    static func set(_ data: Data, for item: Item, service: String = KeychainVault.service) throws {
        let update: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(query(item, service: service) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query(item, service: service)
            attributes[kSecValueData] = data
            attributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(attributes as CFDictionary, nil)
            if status == errSecDuplicateItem {
                // Otro proceso lo creó entre medias: se actualiza.
                status = SecItemUpdate(query(item, service: service) as CFDictionary, update as CFDictionary)
            }
        }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    static func data(for item: Item, service: String = KeychainVault.service) throws -> Data? {
        var request = query(item, service: service)
        request[kSecReturnData] = true
        request[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw KeychainError.status(status)
        }
    }

    static func delete(_ item: Item, service: String = KeychainVault.service) throws {
        let status = SecItemDelete(query(item, service: service) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }

    // MARK: Clave privada RSA (`kSecClassKey`, SEC-10)

    /// Guarda la clave RSA como referencia `kSecClassKey` en el Llavero y elimina el elemento heredado `private-key`
    /// solo tras comprobar que la referencia quedó guardada y legible. Si la sustitución falla, restaura la anterior.
    static func savePrivateKey(pkcs1DER: Data, service: String = KeychainVault.service) throws {
        let secKey = try RSASigner.makeKey(pkcs1DER)
        let previousRef = try? copyPrivateKeyRef(service: service)
        let deleteStatus = SecItemDelete(privateKeyQuery(service: service) as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw KeychainError.status(deleteStatus)
        }
        let addStatus = SecItemAdd(privateKeyAddAttributes(secKey, service: service) as CFDictionary, nil)
        if addStatus != errSecSuccess {
            if let previousRef {
                _ = SecItemAdd(privateKeyAddAttributes(previousRef, service: service) as CFDictionary, nil)
            }
            throw KeychainError.status(addStatus)
        }
        guard (try? copyPrivateKeyRef(service: service)) != nil else {
            throw KeychainError.status(errSecItemNotFound)
        }
        try? delete(.privateKey, service: service)
    }

    /// Devuelve la referencia `SecKey` del Llavero sin cargar bytes DER en memoria.
    /// Si una instalación anterior todavía guarda la clave como `kSecClassGenericPassword` (`private-key`),
    /// la migra automáticamente una sola vez a `kSecClassKey` sin pedir volver a importar el `.pem`.
    static func loadPrivateKey(service: String = KeychainVault.service) throws -> SecKey? {
        if let key = try copyPrivateKeyRef(service: service) {
            return key
        }
        guard let legacyDER = try data(for: .privateKey, service: service), !legacyDER.isEmpty else {
            return nil
        }
        do {
            try savePrivateKey(pkcs1DER: legacyDER, service: service)
            if let migrated = try copyPrivateKeyRef(service: service) {
                return migrated
            }
        } catch {
            // Si el Llavero rechaza la migración, seguimos funcionando sin borrar la clave heredada.
        }
        return try RSASigner.makeKey(legacyDER)
    }

    /// Comprueba si existe clave privada (ya sea como `kSecClassKey` o en el formato heredado aún sin migrar).
    static func hasPrivateKey(service: String = KeychainVault.service) -> Bool {
        if (try? copyPrivateKeyRef(service: service)) != nil { return true }
        if let legacy = try? data(for: .privateKey, service: service), !legacy.isEmpty { return true }
        return false
    }

    static func deletePrivateKey(service: String = KeychainVault.service) throws {
        var first: Error?
        let status = SecItemDelete(privateKeyQuery(service: service) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            first = KeychainError.status(status)
        }
        do { try delete(.privateKey, service: service) } catch { first = first ?? error }
        if let first { throw first }
    }

    /// Intenta borrarlo todo (incluyendo la clave `kSecClassKey`) aunque uno falle; después lanza el primer error.
    static func deleteAll(service: String = KeychainVault.service) throws {
        var first: Error?
        do { try deletePrivateKey(service: service) } catch { first = first ?? error }
        for item in Item.allCases {
            do { try delete(item, service: service) } catch { first = first ?? error }
        }
        if let first { throw first }
    }

    static func setCodable<T: Encodable>(_ value: T, for item: Item, service: String = KeychainVault.service) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { throw KeychainError.encoding }
        try set(data, for: item, service: service)
    }

    static func codable<T: Decodable>(
        _ type: T.Type, for item: Item, service: String = KeychainVault.service
    ) throws -> T? {
        guard let data = try data(for: item, service: service) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let value = try? decoder.decode(type, from: data) else { throw KeychainError.decoding }
        return value
    }

    private static func copyPrivateKeyRef(service: String) throws -> SecKey? {
        var request = privateKeyQuery(service: service)
        request[kSecReturnRef] = true
        request[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let ref = result, CFGetTypeID(ref) == SecKeyGetTypeID() else {
                throw KeychainError.decoding
            }
            return (ref as! SecKey)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.status(status)
        }
    }

    private static func privateKeyAddAttributes(_ key: SecKey, service: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: Data("\(service).\(Item.privateKey.rawValue)".utf8),
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable: false,
            kSecValueRef: key,
        ]
    }

    private static func privateKeyQuery(service: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassKey,
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrApplicationTag: Data("\(service).\(Item.privateKey.rawValue)".utf8),
            kSecAttrSynchronizable: false,
        ]
    }

    private static func query(_ item: Item, service: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: item.rawValue,
            kSecAttrSynchronizable: false,
        ]
    }
}
