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

/// Traspasos preparados que esperan confirmación del banco. Solo guarda `PendingMove` (nunca IBAN, teléfono ni nombre).
enum PendingMoves {
    private static let storageKey = "pendingMoves"

    #if DEBUG
    private final class DemoBox: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [PendingMove] = []

        func all() -> [PendingMove] {
            lock.lock()
            defer { lock.unlock() }
            return items
        }

        func set(_ next: [PendingMove]) {
            lock.lock()
            defer { lock.unlock() }
            items = next
        }
    }

    private static let demo = DemoBox()
    #endif

    static func all() -> [PendingMove] {
        #if DEBUG
        if DemoMode.isActive { return demo.all() }
        #endif
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PendingMove].self, from: data) else {
            return []
        }
        return decoded
    }

    static func add(_ move: PendingMove) {
        var list = all()
        list.removeAll { $0.id == move.id }
        list.insert(move, at: 0)
        save(list)
    }

    static func remove(_ id: UUID) {
        var list = all()
        list.removeAll { $0.id == id }
        save(list)
    }

    static func save(_ moves: [PendingMove]) {
        #if DEBUG
        if DemoMode.isActive {
            demo.set(moves)
            return
        }
        #endif
        if moves.isEmpty {
            UserDefaults.standard.removeObject(forKey: storageKey)
        } else if let data = try? JSONEncoder().encode(moves) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
