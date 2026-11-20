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
    var latest: (day: Date, cents: Int)?

    for row in table.rows {
        guard let iso = isoDay(fromSpanish: row.cell(date)), let day = noonOfDay(iso, calendar: calendar),
              let cents = parseSignedEuropeanAmount(row.cell(amount)) else {
            ignored += 1
            continue
        }
        let raw = row.cell(text)
        let merchant = cleanBankMerchant(raw)
        let key = [row.cell(date), row.cell(amount), raw, row.cell(balance)].joined(separator: "|")
        let ref = "c|" + fnv1aHex(key) + "|" + String(counter.next(key))
        records.append(BankRecord(
            ref: ref, bank: .ima, amountCents: cents, timing: .transactionDay(day.date), status: .booked,
            merchant: merchant.isEmpty ? nil : merchant,
            isShop: !merchant.isEmpty && merchantDomain(for: merchant) != nil))

        // La fecha más reciente; con empate, la primera fila del fichero.
        if let b = parseSignedEuropeanAmount(row.cell(balance)), latest == nil || day.date > latest!.day {
            latest = (day.date, b)
        }
    }
    var latestBalance: StatementBalance?
    if let latest {
        let start = calendar.startOfDay(for: latest.day)
        let endOfDay = (calendar.date(byAdding: .day, value: 1, to: start) ?? latest.day).addingTimeInterval(-1)
        latestBalance = StatementBalance(cents: latest.cents, at: min(now, endOfDay))
    }
    return ParsedStatement(format: .caixabank, records: records, ignoredRows: ignored, latestBalance: latestBalance)
}
