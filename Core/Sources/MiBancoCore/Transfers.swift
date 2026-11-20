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
    // Cada candidato se ordena por (días de Madrid, segundos) sea cual sea el tipo de fila: una fila de solo día a 0 días
    // no le quita el par a una contraparte con hora a dos minutos.
    var candidates: [(payment: Movement, income: Movement, days: Int, seconds: TimeInterval)] = []
    for payment in payments {
        for income in incomes[abs(payment.amountCents)] ?? [] where income.bank != payment.bank {
            let days = abs(madridCalendar.dateComponents(
                [.day], from: madridCalendar.startOfDay(for: payment.date),
                to: madridCalendar.startOfDay(for: income.date)).day ?? Int.max / 2)
            let seconds = abs(income.date.timeIntervalSince(payment.date))
            let wording = hasTransferWording(payment.merchant) || hasTransferWording(income.merchant)
            let close: Bool
            if payment.dayOnly || income.dayOnly {
                // Filas del banco de solo día (guardadas a mediodía): se cuentan días de Madrid, como en la conciliación.
                // 1 día equivale a la ventana de 36 horas; 3 días, a la de las palabras de traspaso.
                close = days <= 1 || (days <= 3 && wording)
            } else {
                close = seconds <= transferWindow || (seconds <= transferWindowWithWording && wording)
            }
            if close { candidates.append((payment, income, days, seconds)) }
        }
    }
    candidates.sort { a, b in
        if a.days != b.days { return a.days < b.days }
        if a.seconds != b.seconds { return a.seconds < b.seconds }
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
/// lo pasa en `notSpending` (con el libro entero, `spendingExclusions(in:now:)`, que también quita los capturados sin confirmar).
public func spendingMovements(in movements: [Movement], notSpending ownTransfers: Set<UUID>? = nil) -> [Movement] {
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

/// Capturados sin enlazar que casi seguro son el mismo pago que una fila del banco (R35): propina, preautorización,
/// redondeo. Pareja probable = fila de un banco (API o extracto) del mismo banco, también un pago, a un día de Madrid o
/// menos, con un importe entre un 5 % menos y un 30 % más que el del capturado. El emparejado es uno a uno, primero los
/// de importe más cercano. Solo para las SUMAS DE GASTO: la etiqueta «Sin confirmar» sigue siendo la definición de 7 días
/// (`unconfirmedCaptureIDs`). Los ids de `skip` (traspasos, capturados ya sin confirmar) ni se emparejan ni sirven de
/// pareja; una operación de valores nunca es pareja.
public func probableTwinCaptureIDs(in movements: [Movement], skipping skip: Set<UUID> = []) -> Set<UUID> {
    let captures = movements.filter {
        $0.kind == .payment && !$0.source.isBankSourced && $0.bankRef == nil && $0.statementRef == nil
            && !$0.flaggedNotMine && !$0.excludedFromSpending && !skip.contains($0.id)
    }
    guard !captures.isEmpty else { return [] }
    // Filas candidatas por (banco, día de Madrid): cada capturado mira solo los tres días que le valen. Una fila cuyo texto
    // marca una operación que no es de tarjeta (recibo, transferencia...) o que el dueño dice que no es suya no es pareja.
    struct DayKey: Hashable { let bank: BankID; let day: Date }
    var rows: [DayKey: [Movement]] = [:]
    for row in movements where row.kind == .payment && row.source.isBankSourced && !row.excludedFromSpending
        && !row.flaggedNotMine && !skip.contains(row.id) && !marksNonCardOperation(row.merchant) {
        rows[DayKey(bank: row.bank, day: madridCalendar.startOfDay(for: row.date)), default: []].append(row)
    }
    var candidates: [(capture: Movement, row: Movement, diff: Int, days: Int, seconds: TimeInterval)] = []
    for capture in captures {
        let cents = abs(capture.amountCents)
        guard cents > 0 else { continue }
        let day = madridCalendar.startOfDay(for: capture.date)
        for offset in -1...1 {
            guard let neighbour = madridCalendar.date(byAdding: .day, value: offset, to: day) else { continue }
            for row in rows[DayKey(bank: capture.bank, day: madridCalendar.startOfDay(for: neighbour))] ?? [] {
                let other = abs(row.amountCents)
                guard other * 100 >= cents * 95, other * 100 <= cents * 130 else { continue }
                candidates.append((capture, row, abs(other - cents), abs(offset), abs(row.date.timeIntervalSince(capture.date))))
            }
        }
    }
    candidates.sort { a, b in
        if a.diff != b.diff { return a.diff < b.diff }
        if a.days != b.days { return a.days < b.days }
        if a.seconds != b.seconds { return a.seconds < b.seconds }
        if a.capture.id != b.capture.id { return a.capture.id.uuidString < b.capture.id.uuidString }
        return a.row.id.uuidString < b.row.id.uuidString
    }
    var usedCaptures = Set<UUID>()
    var usedRows = Set<UUID>()
    for c in candidates where !usedCaptures.contains(c.capture.id) && !usedRows.contains(c.row.id) {
        usedCaptures.insert(c.capture.id)
        usedRows.insert(c.row.id)
    }
    return usedCaptures
}

/// Ids que nunca suman como gasto aunque sean pagos: los traspasos entre tus cuentas, los capturados sin confirmar
/// (definición de 7 días de Plan 2) y los capturados con pareja probable en una fila del banco (R35, ya el mismo día).
/// Se calcula una vez por reconstrucción y se pasa a todas las sumas (parámetros `notSpending:`).
/// `ownTransfers`: el resultado de `ownTransferIDs(in:)` si quien llama ya lo tiene (la instantánea lo necesita aparte
/// para la lista de traspasos): así el emparejado no se repite.
public func spendingExclusions(in state: LedgerState, now: Date, ownTransfers: Set<UUID>? = nil) -> Set<UUID> {
    let transfers = ownTransfers ?? ownTransferIDs(in: state.movements)
    let unconfirmed = unconfirmedCaptureIDs(in: state, now: now)
    return transfers.union(unconfirmed)
        .union(probableTwinCaptureIDs(in: state.movements, skipping: transfers.union(unconfirmed)))
}

/// Palabras que marcan una operación que no es un pago con tarjeta (R40): una fila así no puede ser la pareja de un
/// capturado. Coincidencia por palabra entera, sin mayúsculas ni tildes.
private let nonCardWords: Set<String> = [
    "recibo", "domiciliacion", "adeudo", "transferencia", "traspaso", "bizum", "cajero", "comision",
]

private func marksNonCardOperation(_ text: String?) -> Bool {
    guard let text else { return false }
    let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    return folded.components(separatedBy: CharacterSet.alphanumerics.inverted).contains { nonCardWords.contains($0) }
}
