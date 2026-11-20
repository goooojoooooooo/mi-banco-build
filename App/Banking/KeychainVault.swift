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
/// Todo es `kSecClassGenericPassword`, sin iCloud y accesible tras el primer desbloqueo (un refresco en segundo plano
/// puede correr con el móvil bloqueado) y solo en este dispositivo (no entra en copias ni migraciones).
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

    /// Añade o actualiza en una sola operación lógica: si la actualización no encuentra el elemento, lo añade.
    /// Nunca hay un instante sin valor (borrar y luego añadir lo dejaría vacío si el proceso muere en medio).
    /// `service` solo cambia en la autoprueba, que usa otro servicio para no tocar los datos reales.
    static func set(_ data: Data, for item: Item, service: String = KeychainVault.service) throws {
        let update: [CFString: Any] = [kSecValueData: data]
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

    /// Intenta borrarlo todo aunque uno falle; después lanza el primer error.
    static func deleteAll(service: String = KeychainVault.service) throws {
        var first: Error?
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

    private static func query(_ item: Item, service: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: item.rawValue,
            kSecAttrSynchronizable: false,
        ]
    }
}
