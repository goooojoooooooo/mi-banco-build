import Foundation

private let dateAliases = ["fecha", "fecha operacion", "fecha de operacion"]
private let textAliases = ["movimiento", "concepto", "descripcion"]
private let moreAliases = ["mas datos"]
private let amountAliases = ["importe"]
private let balanceAliases = ["saldo"]

/// "18/11/2026" (también con `-` o `.`) -> "2026-11-18".
private func isoDay(fromSpanish raw: String) -> String? {
    let parts = raw.trimmingCharacters(in: .whitespaces).split(whereSeparator: { "/-.".contains($0) })
    guard parts.count == 3, let d = Int(parts[0]), let m = Int(parts[1]), var y = Int(parts[2]) else { return nil }
    if parts[2].count == 2 { y += 2000 }
    guard parts[2].count == 2 || parts[2].count == 4 else { return nil }
    func pad(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
    return "\(y)-\(pad(m))-\(pad(d))"
}

/// imagin / CaixaBank (sin verificar con un fichero real): fechas dd/MM/yyyy, solo día; importes europeos.
func parseCaixaBankStatement(_ table: CSVTable, now: Date, calendar: Calendar) throws -> ParsedStatement {
    let date = table.column(dateAliases)
    let text = table.column(textAliases)
    let amount = table.column(amountAliases)
    var missing: [String] = []
    if date == nil { missing.append("fecha") }
    if text == nil { missing.append("movimiento") }
    if amount == nil { missing.append("importe") }
    guard missing.isEmpty else { throw StatementError.missingColumns(missing) }
    let balance = table.column(balanceAliases)


    var records: [BankRecord] = []
    var ignored = 0
    var counter = OccurrenceCounter()
    var legacyCounter = OccurrenceCounter()
    // Las filas con saldo, en el orden del fichero.
    var withBalance: [(day: Date, amount: Int, balance: Int)] = []

    for row in table.rows {
        guard let iso = isoDay(fromSpanish: table.cell(row, date)), let day = noonOfDay(iso, calendar: calendar),
              let cents = parseSignedEuropeanAmount(table.cell(row, amount)) else {
            ignored += 1
            continue
        }
        let raw = table.cell(row, text)
        let merchant = cleanBankMerchant(raw)
        // La clave sale de los valores LEÍDOS (día, céntimos, texto normalizado): otro formato de fecha o de número en
        // una reexportación da la misma clave.
        let key = [day.day, String(cents), normalizedStatementText(raw)].joined(separator: "|")
        let ref = "c|" + fnv1aHex(key) + "|" + String(counter.next(key))
        // La clave de la versión anterior (texto de las celdas), para reconocer filas ya importadas con ella.
        let legacyKey = [table.cell(row, date), table.cell(row, amount), raw, table.cell(row, balance)].joined(separator: "|")
        let legacyRef = "c|" + fnv1aHex(legacyKey) + "|" + String(legacyCounter.next(legacyKey))
        records.append(BankRecord(
            ref: ref, bank: .ima, amountCents: cents, timing: .transactionDay(day.date), status: .booked,
            merchant: merchant.isEmpty ? nil : merchant,
            isShop: !merchant.isEmpty && merchantDomain(for: merchant) != nil,
            legacyRefs: legacyRef == ref ? [] : [legacyRef]))

        if let b = parseSignedEuropeanAmount(table.cell(row, balance)) { withBalance.append((day.date, cents, b)) }
    }

    var latestBalance: StatementBalance?
    if let newestDay = withBalance.map(\.day).max() {
        let sameDay = withBalance.filter { $0.day == newestDay }
        // El saldo de cierre es el de la ÚLTIMA fila del día más reciente EN EL TIEMPO: según el orden del fichero eso es
        // la primera (más nuevo primero) o la última (más antiguo primero) de las de ese día.
        let closing = fileIsOldestFirst(withBalance) ? sameDay.last! : sameDay.first!
        let start = calendar.startOfDay(for: newestDay)
        let endOfDay = (calendar.date(byAdding: .day, value: 1, to: start) ?? newestDay).addingTimeInterval(-1)
        latestBalance = StatementBalance(cents: closing.balance, at: min(now, endOfDay))
    }
    return ParsedStatement(format: .caixabank, records: records, ignoredRows: ignored, latestBalance: latestBalance)
}

/// ¿Viene el fichero del más antiguo al más nuevo? Primero por la cadena del saldo (entre filas contiguas, saldo anterior
/// + importe siguiente = saldo siguiente si va hacia delante, o al revés si va hacia atrás: sirve aunque todas las filas
/// sean del mismo día); si no concluye, por las fechas de la primera y la última fila; si tampoco, el orden habitual de
/// los bancos: el más nuevo primero.
private func fileIsOldestFirst(_ rows: [(day: Date, amount: Int, balance: Int)]) -> Bool {
    var forward = 0
    var backward = 0
    for i in rows.indices.dropLast() {
        let a = rows[i], b = rows[i + 1]
        if a.balance + b.amount == b.balance { forward += 1 }
        if b.balance + a.amount == a.balance { backward += 1 }
    }
    if forward != backward { return forward > backward }
    if let first = rows.first, let last = rows.last, first.day != last.day { return first.day < last.day }
    return false
}
