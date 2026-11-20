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

/// Un traspaso cuenta si pago e ingreso están a 36 horas o menos; hasta 3 días solo si alguno de los dos textos
/// habla de traspasos o nombra un banco (con muchos meses de historial, "mismo importe en 3 días" solo daría falsos pares).
private let transferWindow: TimeInterval = 129_600
private let transferWindowWithWording: TimeInterval = 259_200

/// Palabras (ya sin mayúsculas ni tildes) que delatan un traspaso entre cuentas o el nombre de un banco.
private let transferWording: [[String]] = [
    ["transferencia"], ["traspaso"], ["transfer"], ["recarga"], ["top", "up"], ["anadir", "dinero"],
    ["revolut"], ["imagin"], ["caixabank"], ["trade", "republic"],
]

private func hasTransferWording(_ merchant: String?) -> Bool {
    let tokens = normalizeMerchant(merchant ?? "").split(separator: " ").map(String.init)
    guard !tokens.isEmpty else { return false }
    return transferWording.contains { words in
        words.count <= tokens.count
            && (0...(tokens.count - words.count)).contains { Array(tokens[$0..<($0 + words.count)]) == words }
    }
}

/// Emparejado voraz de traspasos entre tus cuentas. Candidatos: pagos que no son de tienda, no "no es mío" y sin
/// `ownTransfer == false`, e ingresos de OTRO banco con el mismo importe, sin `ownTransfer == false`, a 36 horas o menos
/// (3 días si alguno de los dos textos habla de traspasos o nombra un banco).
/// Se toman los pares de menor distancia en el tiempo primero (empate: el más antiguo), y cada movimiento entra en un
/// solo par.
public func ownTransferPairs(in movements: [Movement]) -> [OwnTransferPair] {
    func order(_ a: Movement, _ b: Movement) -> Bool {
        a.date != b.date ? a.date < b.date : a.id.uuidString < b.id.uuidString
    }
    // Las operaciones de valores (`excludedFromSpending`) nunca son un traspaso: no son dinero que cambia de cuenta.
    let payments = movements
        .filter { $0.kind == .payment && !$0.isShop && !$0.flaggedNotMine && $0.ownTransfer != false && !$0.excludedFromSpending }
        .sorted(by: order)
    var incomes: [Int: [Movement]] = [:]
    for m in movements where m.kind == .income && !m.flaggedNotMine && m.ownTransfer != false && !m.excludedFromSpending {
        incomes[abs(m.amountCents), default: []].append(m)
    }
    var candidates: [(payment: Movement, income: Movement, gap: TimeInterval)] = []
    for payment in payments {
        for income in incomes[abs(payment.amountCents)] ?? [] where income.bank != payment.bank {
            let gap: TimeInterval
            let close: Bool
            if payment.dayOnly || income.dayOnly {
                // Filas del banco de solo día (guardadas a mediodía): se cuentan días de Madrid, como en la conciliación.
                // 1 día equivale a la ventana de 36 horas; 3 días, a la de las palabras de traspaso.
                let days = abs(madridCalendar.dateComponents(
                    [.day], from: madridCalendar.startOfDay(for: payment.date),
                    to: madridCalendar.startOfDay(for: income.date)).day ?? Int.max / 2)
                gap = TimeInterval(days) * 86_400
                close = days <= 1
                    || (days <= 3 && (hasTransferWording(payment.merchant) || hasTransferWording(income.merchant)))
            } else {
                gap = abs(income.date.timeIntervalSince(payment.date))
                close = gap <= transferWindow
                    || (gap <= transferWindowWithWording && (hasTransferWording(payment.merchant) || hasTransferWording(income.merchant)))
            }
            if close { candidates.append((payment, income, gap)) }
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

/// Lo que cuenta como gasto: pagos, sin los "no es mío", sin las operaciones de valores (`excludedFromSpending`) y sin
/// los traspasos entre tus cuentas. Quien lo llama varias veces sobre los mismos movimientos calcula el conjunto una vez y
/// lo pasa en `excluding` (con el libro entero, `spendingExclusions(in:now:)`, que también quita los capturados sin confirmar).
public func spendingMovements(in movements: [Movement], excluding ownTransfers: Set<UUID>? = nil) -> [Movement] {
    let transfers = ownTransfers ?? ownTransferIDs(in: movements)
    return movements.filter {
        $0.kind == .payment && !$0.flaggedNotMine && !$0.excludedFromSpending && !transfers.contains($0.id)
    }
}

/// Capturados (aviso o Cartera) que el banco conectado ya debería haber confirmado y no confirmó, de todos los bancos
/// (`Ledger.unconfirmedCaptures`). Su pago ya está en la fila del banco (p. ej. con propina: aviso 50 €, banco 55 €),
/// así que no suman como gasto: cuenta la fila del banco. Sin datos del banco de ese periodo, el capturado cuenta como siempre.
public func unconfirmedCaptureIDs(in state: LedgerState, now: Date) -> Set<UUID> {
    let ledger = Ledger(state: state)
    var ids = Set<UUID>()
    for bank in BankID.allCases { ids.formUnion(ledger.unconfirmedCaptures(bank: bank, now: now)) }
    return ids
}

/// Ids que nunca suman como gasto aunque sean pagos: los traspasos entre tus cuentas y los capturados sin confirmar.
/// Se calcula una vez por reconstrucción y se pasa a todas las sumas (parámetros `ownTransferIDs:` / `excluding:`).
public func spendingExclusions(in state: LedgerState, now: Date) -> Set<UUID> {
    ownTransferIDs(in: state.movements).union(unconfirmedCaptureIDs(in: state, now: now))
}
