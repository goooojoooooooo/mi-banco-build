import Foundation
import Observation
import Security
import MiBancoCore

/// Único almacén de IBAN propios, colchones mínimos y contactos: solo el Llavero de este iPhone,
/// accesible únicamente desbloqueado y sin sincronizar con iCloud. Nunca entra en el libro ni en copias.
struct AccountBookStore {
    static let service = "com.mibanco.accounts"
    static let account = "book"

    #if DEBUG
    private final class DemoBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: AccountBook?

        func load() -> AccountBook {
            lock.lock()
            defer { lock.unlock() }
            if let stored { return stored }
            let initial = DemoMode.accountBook()
            stored = initial
            return initial
        }

        func save(_ book: AccountBook) {
            lock.lock()
            defer { lock.unlock() }
            stored = book
        }
    }

    private static let demo = DemoBox()
    #endif

    static func load() -> AccountBook {
        (try? loadThrowing()) ?? AccountBook()
    }

    /// Lectura que distingue ausencia real (`errSecItemNotFound` → libro vacío) de un error temporal del Llavero
    /// (p. ej. `errSecInteractionNotAllowed`), para que `reload()` nunca borre el estado en memoria por un fallo transitorio.
    static func loadThrowing() throws -> AccountBook {
        #if DEBUG
        if DemoMode.isActive { return demo.load() }
        #endif
        var request = baseQuery()
        request[kSecReturnData] = true
        request[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let decoded = try? JSONDecoder().decode(AccountBook.self, from: data) else {
                throw KeychainError.decoding
            }
            return decoded
        case errSecItemNotFound:
            return AccountBook()
        default:
            throw KeychainError.status(status)
        }
    }

    static func save(_ book: AccountBook) throws {
        #if DEBUG
        if DemoMode.isActive {
            demo.save(book)
            return
        }
        #endif
        guard let data = try? JSONEncoder().encode(book) else {
            throw KeychainError.encoding
        }
        let update: [CFString: Any] = [kSecValueData: data]
        var status = SecItemUpdate(baseQuery() as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = baseQuery()
            attributes[kSecValueData] = data
            attributes[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(attributes as CFDictionary, nil)
            if status == errSecDuplicateItem {
                status = SecItemUpdate(baseQuery() as CFDictionary, update as CFDictionary)
            }
        }
        guard status == errSecSuccess else {
            throw KeychainError.status(status)
        }
    }

    private static func baseQuery() -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: false,
        ]
    }
}

/// Estado observable del cuaderno de cuentas (respaldado únicamente por `AccountBookStore` en el Llavero).
@MainActor @Observable
final class AccountBookModel {
    private(set) var book: AccountBook

    init() {
        self.book = AccountBookStore.load()
    }

    func reload() {
        guard let loaded = try? AccountBookStore.loadThrowing() else { return }
        if loaded != book { book = loaded }
    }

    func setIBAN(_ raw: String?, for bank: BankID) throws {
        var next = book
        if let raw {
            let clean = normalizeIBAN(raw)
            if clean.isEmpty {
                next.ibans.removeValue(forKey: bank)
            } else {
                next.ibans[bank] = clean
            }
        } else {
            next.ibans.removeValue(forKey: bank)
        }
        try AccountBookStore.save(next)
        book = next
    }

    func setFloor(_ cents: Int?, for bank: BankID) throws {
        var next = book
        if let cents, cents > 0 {
            next.floors[bank] = cents
        } else {
            next.floors.removeValue(forKey: bank)
        }
        try AccountBookStore.save(next)
        book = next
    }

    func addPayee(_ payee: Payee) throws {
        var next = book
        next.payees.append(payee)
        try AccountBookStore.save(next)
        book = next
    }

    func deletePayee(id: UUID) throws {
        var next = book
        next.payees.removeAll { $0.id == id }
        try AccountBookStore.save(next)
        book = next
    }

    func payee(id: UUID) -> Payee? {
        book.payees.first { $0.id == id }
    }

    func displayName(for target: MoveTarget) -> String {
        switch target {
        case .own(let bank): bank.displayName
        case .payee(let id): payee(id: id)?.name ?? "Contacto"
        }
    }
}
