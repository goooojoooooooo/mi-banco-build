import Foundation

public enum MoveTarget: Codable, Equatable, Hashable, Sendable {
    case own(BankID)
    case payee(UUID)
}

/// Un traspaso que el usuario ha empezado en su banco. Nunca lleva IBAN ni teléfono ni nombre:
/// solo el banco de origen, a quién (por id) y cuánto.
public struct PendingMove: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let from: BankID
    public let target: MoveTarget
    public let amountCents: Int
    public let createdAt: Date

    public init(id: UUID = UUID(), from: BankID, target: MoveTarget, amountCents: Int, createdAt: Date) {
        self.id = id
        self.from = from
        self.target = target
        self.amountCents = amountCents
        self.createdAt = createdAt
    }
}

public enum MoveState: Equatable, Sendable {
    case waiting
    case done(movementID: UUID)
    case expired
}

private let moveLookBack: TimeInterval = 300
private let moveLifetime: TimeInterval = 3 * 86_400

/// El traspaso está hecho cuando llega el pago del mismo importe desde ese banco
/// (hasta 5 min antes de crearlo y 3 días después); pasados los 3 días sin él, caduca.
public func moveState(_ move: PendingMove, movements: [Movement], now: Date) -> MoveState {
    let from = move.createdAt.addingTimeInterval(-moveLookBack)
    let to = move.createdAt.addingTimeInterval(moveLifetime)
    let hit = movements.first {
        $0.bank == move.from && $0.kind == .payment && $0.amountCents == -move.amountCents && !$0.flaggedNotMine
            && $0.date >= from && $0.date <= to
    }
    if let hit { return .done(movementID: hit.id) }
    return now > to ? .expired : .waiting
}

/// Lo que el IBAN o el número copiados duran en el portapapeles (segundos).
public let clipboardLifetime: TimeInterval = 180

public enum PasteKind: Sendable { case iban, phone }

/// Dónde tocar en la app del banco. Las rutas están SIN verificar en el iPhone: se corrigen aquí.
public func bankTransferHint(from bank: BankID, kind: PasteKind, amountCents: Int) -> String {
    let amount = formatEUR(amountCents)
    switch (bank, kind) {
    case (.ima, .iban): return "En imagin: Enviar dinero → Transferencia → pega el IBAN y pon \(amount)."
    case (.ima, .phone): return "En imagin: Bizum → Enviar → pega el número y pon \(amount)."
    case (.rev, .iban): return "En Revolut: Pagos → Transferir → Cuenta bancaria → pega el IBAN y pon \(amount)."
    case (.rev, .phone): return "En Revolut: Pagos → Enviar → pega el número y pon \(amount)."
    case (.tr, .iban): return "En Trade Republic: Efectivo → Transferir → Retirar. Solo puedes enviarlo a tu cuenta de referencia."
    case (.tr, .phone): return "En Trade Republic no se puede enviar dinero a un número de teléfono."
    }
}
