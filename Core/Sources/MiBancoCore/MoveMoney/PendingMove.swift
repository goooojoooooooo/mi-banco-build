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

private struct LossyPendingMove: Decodable {
    let value: PendingMove?
    init(from decoder: Decoder) throws { value = try? PendingMove(from: decoder) }
}

/// Decodifica una lista de traspasos pendientes elemento a elemento, saltando los corruptos (U31),
/// pero lanzando error si el documento entero no es un array JSON válido (p. ej. archivo truncado o corrupto).
public func decodePendingMovesThrowing(_ data: Data) throws -> [PendingMove] {
    let items = try JSONDecoder().decode([LossyPendingMove].self, from: data)
    return items.compactMap(\.value)
}

/// Decodifica una lista de traspasos pendientes elemento a elemento, saltando los corruptos (U31).
public func decodePendingMoves(_ data: Data) -> [PendingMove] {
    (try? decodePendingMovesThrowing(data)) ?? []
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
/// No cuentan las compras en tienda, los movimientos marcados «no es mío», los fechados después de `now` ni los que
/// ya reclama otro traspaso (`claimed`). `.done` trae el id del movimiento: quien llama lo anota como reclamado.
public func moveState(_ move: PendingMove, movements: [Movement], now: Date, claimed: Set<UUID> = []) -> MoveState {
    let from = move.createdAt.addingTimeInterval(-moveLookBack)
    let to = move.createdAt.addingTimeInterval(moveLifetime)
    let hit = movements.filter {
        $0.bank == move.from && $0.kind == .payment && $0.amountCents == -move.amountCents && !$0.flaggedNotMine
            && !$0.isShop && $0.date <= now && $0.date >= from && $0.date <= to && !claimed.contains($0.id)
    }.min { $0.date < $1.date }
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
    case (.tr, .phone): return "No encuentro cómo enviar dinero a un teléfono desde Trade Republic. Usa su IBAN."
    }
}
