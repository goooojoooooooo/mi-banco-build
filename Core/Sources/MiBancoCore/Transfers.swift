import Foundation

/// Un pago de un banco y el ingreso del mismo importe en otro banco: el mismo dinero cambiando de cuenta.
public struct OwnTransferPair: Equatable, Sendable {
    public let paymentID: UUID
    public let incomeID: UUID

    public init(paymentID: UUID, incomeID: UUID) {
        self.paymentID = paymentID
        self.incomeID = incomeID
    }
}

/// Ventana máxima entre el pago y el ingreso de un traspaso: 3 días.
private let transferWindow: TimeInterval = 259_200

/// Emparejado voraz de traspasos entre tus cuentas. Pagos candidatos (no tienda, no "no es mío", sin `ownTransfer == false`)
/// por fecha ascendente; cada uno toma el ingreso libre de OTRO banco con el mismo importe, a menos de 3 días, que esté
/// más cerca en el tiempo (empate: el más antiguo). Cada movimiento entra en un solo par.
public func ownTransferPairs(in movements: [Movement]) -> [OwnTransferPair] {
    func order(_ a: Movement, _ b: Movement) -> Bool {
        a.date != b.date ? a.date < b.date : a.id.uuidString < b.id.uuidString
    }
    let payments = movements
        .filter { $0.kind == .payment && !$0.isShop && !$0.flaggedNotMine && $0.ownTransfer != false }
        .sorted(by: order)
    var incomes: [Int: [Movement]] = [:]
    for m in movements where m.kind == .income && !m.flaggedNotMine && m.ownTransfer != false {
        incomes[abs(m.amountCents), default: []].append(m)
    }
    var used = Set<UUID>()
    var pairs: [OwnTransferPair] = []
    for payment in payments {
        let candidates = (incomes[abs(payment.amountCents)] ?? []).filter {
            !used.contains($0.id) && $0.bank != payment.bank
                && abs($0.date.timeIntervalSince(payment.date)) <= transferWindow
        }
        let best = candidates.min { a, b in
            let da = abs(a.date.timeIntervalSince(payment.date)), db = abs(b.date.timeIntervalSince(payment.date))
            return da != db ? da < db : order(a, b)
        }
        guard let best else { continue }
        used.insert(best.id)
        pairs.append(OwnTransferPair(paymentID: payment.id, incomeID: best.id))
    }
    return pairs
}

/// Ids de los movimientos que son traspasos: los de los pares más los que el dueño marcó con `ownTransfer == true`.
public func ownTransferIDs(in movements: [Movement]) -> Set<UUID> {
    var ids = Set<UUID>()
    for pair in ownTransferPairs(in: movements) {
        ids.insert(pair.paymentID)
        ids.insert(pair.incomeID)
    }
    for m in movements where m.ownTransfer == true { ids.insert(m.id) }
    return ids
}

/// Lo que cuenta como gasto: pagos, sin los "no es mío" y sin los traspasos entre tus cuentas.
public func spendingMovements(in movements: [Movement]) -> [Movement] {
    let transfers = ownTransferIDs(in: movements)
    return movements.filter { $0.kind == .payment && !$0.flaggedNotMine && !transfers.contains($0.id) }
}
