import Foundation
import Observation
import Security
import MiBancoCore

extension Notification.Name {
    /// La libreta de cuentas del Llavero ha cambiado fuera de la vista actual (p. ej. IBAN rellenado al conectar un banco).
    static let accountBookDidChange = Notification.Name("com.mibanco.accountBookDidChange")
}

/// Único almacén de IBAN propios, colchones mínimos y contactos: solo el Llavero de este iPhone,
/// accesible únicamente desbloqueado y sin sincronizar con iCloud. Nunca entra en el libro ni en copias.
struct AccountBookStore {
    static let service = "com.mibanco.accounts"
    static let account = "book"

    #if DEBUG
    private final class DemoBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: AccountBook?
        /// `-MiBancoDemoKeychainFails`: el Llavero falla en TODA lectura (arranque y cada vuelta a primer plano) hasta la
        /// primera lectura para escribir, que también falla; desde ahí lee bien. Así la prueba de U28 no depende de cuántas
        /// veces se active la escena antes de tocar «Guardar» (A-D1).
        private var failing: Bool?

        func loadThrowing(forWrite: Bool) throws -> AccountBook {
            lock.lock()
            defer { lock.unlock() }
            if failing == nil {
                failing = DemoMode.keychainFailCount > 0
            }
            if failing == true {
                if forWrite { failing = false }
                throw KeychainError.status(errSecInteractionNotAllowed)
            }
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
    static func loadThrowing(forWrite: Bool = false, service: String = AccountBookStore.service) throws -> AccountBook {
        #if DEBUG
        if DemoMode.isActive && service == AccountBookStore.service {
            return try demo.loadThrowing(forWrite: forWrite)
        }
        #endif
        var request = baseQuery(service: service)
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

    static func save(_ book: AccountBook, service: String = AccountBookStore.service) throws {
        #if DEBUG
        if DemoMode.isActive && service == AccountBookStore.service {
            demo.save(book)
            return
        }
        #endif
        guard let data = try? JSONEncoder().encode(book) else {
            throw KeychainError.encoding
        }
        let update: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        var status = SecItemUpdate(baseQuery(service: service) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = baseQuery(service: service)
            attributes[kSecValueData] = data
            attributes[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(attributes as CFDictionary, nil)
            if status == errSecDuplicateItem {
                status = SecItemUpdate(baseQuery(service: service) as CFDictionary, update as CFDictionary)
            }
        }
        guard status == errSecSuccess else {
            throw KeychainError.status(status)
        }
    }

    /// Rellena el IBAN de un banco conectado solo si está vacío y el IBAN es válido; nunca pisa uno existente,
    /// nunca toca Trade Republic y nunca falla la conexión si el Llavero no está accesible (p. ej. teléfono bloqueado).
    @discardableResult
    static func fillIBANIfEmpty(_ raw: String, for bank: BankID, service: String = AccountBookStore.service) -> Bool {
        guard var book = try? loadThrowing(forWrite: true, service: service) else {
            return false
        }
        guard book.fillIBANIfEmpty(raw, for: bank) else {
            return false
        }
        guard (try? save(book, service: service)) != nil else {
            return false
        }
        if service == AccountBookStore.service {
            NotificationCenter.default.post(name: .accountBookDidChange, object: nil)
        }
        return true
    }

    private static func baseQuery(service: String = AccountBookStore.service) -> [CFString: Any] {
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
    @ObservationIgnored private let service: String
    @ObservationIgnored private var loadFailed = false
    @ObservationIgnored private var observer: Task<Void, Never>?

    init(service: String = AccountBookStore.service) {
        self.service = service
        do {
            self.book = try AccountBookStore.loadThrowing(service: service)
            self.loadFailed = false
        } catch {
            self.book = AccountBook()
            self.loadFailed = true
        }
        guard service == AccountBookStore.service else { return }
        #if DEBUG
        if DemoMode.isActive { return }
        #endif
        observer = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .accountBookDidChange) {
                guard let self else { break }
                self.reload()
            }
        }
    }

    func reload() {
        guard let loaded = try? AccountBookStore.loadThrowing(service: service) else { return }
        loadFailed = false
        if loaded != book { book = loaded }
    }

    /// Recarga el cuaderno actual del Llavero antes de escribir para no pisar un IBAN recién rellenado
    /// antes de que llegue `.accountBookDidChange` (M2). Si la lectura inicial falló, exige leer del Llavero
    /// antes de escribir para nunca pisar datos del dueño con un cuaderno vacío (U28).
    private func baseBookForWrite() throws -> AccountBook {
        if loadFailed {
            let loaded = try AccountBookStore.loadThrowing(forWrite: true, service: service)
            loadFailed = false
            book = loaded
            return loaded
        }
        return (try? AccountBookStore.loadThrowing(forWrite: true, service: service)) ?? book
    }

    func setIBAN(_ raw: String?, for bank: BankID) throws {
        var next = try baseBookForWrite()
        next.setIBAN(raw, for: bank)
        try AccountBookStore.save(next, service: service)
        book = next
    }

    func setFloor(_ cents: Int?, for bank: BankID) throws {
        var next = try baseBookForWrite()
        if let cents, cents > 0 {
            next.floors[bank] = cents
        } else {
            next.floors.removeValue(forKey: bank)
        }
        try AccountBookStore.save(next, service: service)
        book = next
    }

    func addPayee(_ payee: Payee) throws {
        var next = try baseBookForWrite()
        next.payees.append(payee)
        try AccountBookStore.save(next, service: service)
        book = next
    }

    func deletePayee(id: UUID) throws {
        var next = try baseBookForWrite()
        next.payees.removeAll { $0.id == id }
        try AccountBookStore.save(next, service: service)
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
