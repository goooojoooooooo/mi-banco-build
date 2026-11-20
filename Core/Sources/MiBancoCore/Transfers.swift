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

/// Emparejado voraz de traspasos entre tus cuentas. Candidatos: pagos que no son de tienda, no "no es mío" y sin
/// `ownTransfer == false`, e ingresos de OTRO banco con el mismo importe, sin `ownTransfer == false`, a 3 días o menos.
/// Se toman los pares de menor distancia en el tiempo primero (empate: el más antiguo), y cada movimiento entra en un
/// solo par.
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
    var candidates: [(payment: Movement, income: Movement, gap: TimeInterval)] = []
    for payment in payments {
        for income in incomes[abs(payment.amountCents)] ?? [] where income.bank != payment.bank {
            let gap = abs(income.date.timeIntervalSince(payment.date))
            if gap <= transferWindow { candidates.append((payment, income, gap)) }
        }
    }
    candidates.sort { a, b in
        if a.gap != b.gap { return a.gap < b.gap }
        if a.payment.id != b.payment.id { return order(a.payment, b.payment) }
        return order(a.income, b.income)
    }
    var used = Set<UUID>()
    var pairs: [OwnTransferPair] = []
    for c in candidates where !used.contains(c.payment.id) && !used.contains(c.income.id) {
        used.insert(c.payment.id)
        used.insert(c.income.id)
        pairs.append(OwnTransferPair(paymentID: c.payment.id, incomeID: c.income.id))
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
