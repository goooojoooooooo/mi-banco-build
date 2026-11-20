import Foundation

private let typeAliases = ["type", "tipo"]
private let productAliases = ["product", "producto"]
private let startedAliases = ["started date", "fecha de inicio"]
private let completedAliases = ["completed date", "fecha de finalizacion", "fecha de finalización"]
private let descriptionAliases = ["description", "descripcion"]
private let amountAliases = ["amount", "importe"]
private let feeAliases = ["fee", "comision"]
private let currencyAliases = ["currency", "divisa"]
private let stateAliases = ["state", "estado"]
private let balanceAliases = ["balance", "saldo"]

/// Revolut (cabeceras de los lectores de la comunidad, sin verificar en español): se mantienen las filas completadas
/// de la cuenta corriente en euros; importe = importe − comisión; hora exacta de inicio en el calendario dado.
func parseRevolutStatement(_ table: CSVTable, calendar: Calendar) throws -> ParsedStatement {
    let started = table.column(startedAliases)
    let amount = table.column(amountAliases)
    let state = table.column(stateAliases)
    let currency = table.column(currencyAliases)
    var missing: [String] = []
    if started == nil { missing.append("fecha") }
    if amount == nil { missing.append("importe") }
    if state == nil { missing.append("estado") }
    if currency == nil { missing.append("divisa") }
    guard missing.isEmpty else { throw StatementError.missingColumns(missing) }

    let type = table.column(typeAliases)
    let product = table.column(productAliases)
    let completed = table.column(completedAliases)
    let description = table.column(descriptionAliases)
    let fee = table.column(feeAliases)
    let balance = table.column(balanceAliases)

    var records: [BankRecord] = []
    var ignored = 0
    var counter = OccurrenceCounter()
    var latest: (date: Date, cents: Int)?

    for row in table.rows {
        let stateText = normalizeHeader(row.cell(state))
        let productText = normalizeHeader(row.cell(product))
        guard ["completed", "completado"].contains(stateText),
              product == nil || productText.isEmpty || ["current", "actual", "corriente"].contains(productText),
              row.cell(currency).uppercased() == "EUR",
              let startedAt = parseStatementTimestamp(row.cell(started), calendar: calendar),
              let gross = parseStatementDecimal(row.cell(amount)) else {
            ignored += 1
            continue
        }
        var feeCents = 0
        if fee != nil, !row.cell(fee).isEmpty {
            guard let f = parseStatementDecimal(row.cell(fee)) else {
                ignored += 1
                continue
            }
            feeCents = f
        }
        let cents = gross - feeCents
        let text = row.cell(description)
        let name = cleanBankMerchant(text)
        let typeText = normalizeHeader(row.cell(type))
        let key = [row.cell(started), row.cell(amount), text].joined(separator: "|")
        let ref = "r|" + fnv1aHex(key) + "|" + String(counter.next(key))
        records.append(BankRecord(
            ref: ref, bank: .rev, amountCents: cents, timing: .exact(startedAt), status: .booked,
            merchant: name.isEmpty ? nil : name,
            isShop: typeText.contains("card payment") || typeText.contains("pago con tarjeta")))

        if let b = parseStatementDecimal(row.cell(balance)) {
            let doneAt = parseStatementTimestamp(row.cell(completed), calendar: calendar) ?? startedAt
            if latest == nil || doneAt >= latest!.date { latest = (doneAt, b) }
        }
    }
    return ParsedStatement(format: .revolut, records: records, ignoredRows: ignored,
                           latestBalance: latest.map { StatementBalance(cents: $0.cents, at: $0.date) })
}
