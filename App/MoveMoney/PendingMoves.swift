import Foundation
import MiBancoCore

/// Petición para abrir la hoja «Mover dinero» (desde acciones rápidas, el calendario o el resumen diario).
struct MoveRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    var from: BankID?
    var target: MoveTarget?
    var amountCents: Int?
    #if DEBUG
    var demoStep: Int?
    #endif

    init(
        id: UUID = UUID(),
        from: BankID? = nil,
        target: MoveTarget? = nil,
        amountCents: Int? = nil,
        demoStep: Int? = nil
    ) {
        self.id = id
        self.from = from
        self.target = target
        self.amountCents = amountCents
        #if DEBUG
        self.demoStep = demoStep
        #endif
    }
}

/// Traspasos preparados que esperan confirmación del banco. Solo guarda `PendingMove` (nunca IBAN, teléfono ni nombre)
/// en el almacén protegido (`pending-moves.json`); migra una vez desde `UserDefaults.standard` si hubiera datos previos.
enum PendingMoves {
    private static let legacyStorageKey = "pendingMoves"
    private static var store: PendingMovesStore { SharedStore.makePendingMovesStore() }

    #if DEBUG
    private final class DemoBox: @unchecked Sendable {
        private let lock = NSLock()
        private var seeded = false
        private var items: [PendingMove] = []

        func all() -> [PendingMove] {
            lock.lock()
            defer { lock.unlock() }
            if !seeded {
                seeded = true
                items = DemoMode.initialPendingMoves()
            }
            return items
        }

        func set(_ next: [PendingMove]) {
            lock.lock()
            defer { lock.unlock() }
            seeded = true
            items = next
        }
    }

    private static let demo = DemoBox()
    #endif

    static func all() -> [PendingMove] {
        #if DEBUG
        if DemoMode.isActive { return demo.all() }
        #endif
        let defaults = UserDefaults.standard
        return store.migrateLegacy(
            readLegacy: { defaults.data(forKey: legacyStorageKey) },
            clearLegacy: { defaults.removeObject(forKey: legacyStorageKey) }
        )
    }

    static func add(_ move: PendingMove) {
        #if DEBUG
        if DemoMode.isActive {
            var list = demo.all()
            list.removeAll { $0.id == move.id }
            list.insert(move, at: 0)
            demo.set(list)
            return
        }
        #endif
        let defaults = UserDefaults.standard
        if defaults.object(forKey: legacyStorageKey) != nil {
            _ = all()
        }
        do {
            try store.add(move)
            clearLegacyIfPersisted(defaults, ignoring: nil)
        } catch {
            // Si pending-moves.json es ilegible o está corrupto, no se destruye ni se borra la clave heredada (M-11).
        }
    }

    static func remove(_ id: UUID) {
        #if DEBUG
        if DemoMode.isActive {
            var list = demo.all()
            list.removeAll { $0.id == id }
            demo.set(list)
            return
        }
        #endif
        let defaults = UserDefaults.standard
        if defaults.object(forKey: legacyStorageKey) != nil {
            _ = all()
        }
        do {
            try store.remove(id)
            clearLegacyIfPersisted(defaults, ignoring: id)
        } catch {
            // Si pending-moves.json es ilegible o está corrupto, no se destruye ni se borra la clave heredada (M-11).
        }
    }

    /// Solo borra la clave heredada si sus traspasos ya están en el archivo protegido (N-3).
    private static func clearLegacyIfPersisted(_ defaults: UserDefaults, ignoring removed: UUID?) {
        store.clearLegacyIfPersisted(
            ignoring: removed,
            readLegacy: { defaults.data(forKey: legacyStorageKey) },
            clearLegacy: { defaults.removeObject(forKey: legacyStorageKey) }
        )
    }

    static func save(_ moves: [PendingMove]) {
        #if DEBUG
        if DemoMode.isActive {
            demo.set(moves)
            return
        }
        #endif
        do {
            try store.save(moves)
            UserDefaults.standard.removeObject(forKey: legacyStorageKey)
        } catch {
            // Si el disco falla al guardar, no se borra la clave heredada si aún existiera.
        }
    }
}
