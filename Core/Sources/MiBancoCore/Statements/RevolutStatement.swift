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
    var legacyCounter = OccurrenceCounter()
    var latest: (date: Date, cents: Int)?

    for row in table.rows {
        let stateText = normalizeHeader(table.cell(row, state))
        let productText = normalizeHeader(table.cell(row, product))
        guard ["completed", "completado"].contains(stateText),
              product == nil || productText.isEmpty || ["current", "actual", "corriente"].contains(productText),
              table.cell(row, currency).uppercased() == "EUR",
              let startedAt = parseStatementTimestamp(table.cell(row, started), calendar: calendar),
              let gross = parseStatementDecimal(table.cell(row, amount)) else {
            ignored += 1
            continue
        }
        var feeCents = 0
        if fee != nil, !table.cell(row, fee).isEmpty {
            guard let f = parseStatementDecimal(table.cell(row, fee)) else {
                ignored += 1
                continue
            }
            feeCents = f
        }
        let cents = gross - feeCents
        let text = table.cell(row, description)
        let name = cleanBankMerchant(text)
        let typeText = normalizeHeader(table.cell(row, type))
        // La clave sale de los valores LEÍDOS (segundos, céntimos, descripción normalizada), no del texto de las celdas:
        // la misma exportación con otro formato de fecha o de número da la misma clave.
        let key = [String(Int(startedAt.timeIntervalSince1970)), String(cents), normalizedStatementText(text)]
            .joined(separator: "|")
        let ref = "r|" + fnv1aHex(key) + "|" + String(counter.next(key))
        // La clave de la versión anterior (texto de las celdas), para reconocer filas ya importadas con ella.
        let legacyKey = [table.cell(row, started), table.cell(row, amount), text].joined(separator: "|")
        let legacyRef = "r|" + fnv1aHex(legacyKey) + "|" + String(legacyCounter.next(legacyKey))
        let isShop = typeText.contains("card payment") || typeText.contains("pago con tarjeta")
        // Un envío: tipo «Transfer»/«Transferencia» o descripción «To Ana» (lo que Revolut escribe al enviar a alguien).
        // No a tus bolsillos ni a tus cuentas en otra divisa: «To USD», «To EUR Savings», «To pocket …» (M-1).
        let saysTransfer = typeText.contains("transfer") || normalizeHeader(text).hasPrefix("to ")
        let words = foldedWords(text)
        let toOwnPocket = mentionsOwnAccount(text) || (words.first == "to" && words.count > 1 && currencyCodes.contains(words[1]))
        records.append(BankRecord(
            ref: ref, bank: .rev, amountCents: cents, timing: .exact(startedAt), status: .booked,
            merchant: name.isEmpty ? nil : name,
            isShop: isShop,
            legacyRefs: legacyRef == ref ? [] : [legacyRef],
            personPayment: cents < 0 && !isShop && saysTransfer && !toOwnPocket))

        if let b = parseStatementDecimal(table.cell(row, balance)) {
            let doneAt = parseStatementTimestamp(table.cell(row, completed), calendar: calendar) ?? startedAt
            if latest == nil || doneAt >= latest!.date { latest = (doneAt, b) }
        }
    }
    return ParsedStatement(format: .revolut, records: records, ignoredRows: ignored,
                           latestBalance: latest.map { StatementBalance(cents: $0.cents, at: $0.date) })
}

/// Códigos de divisa (en minúsculas) que Revolut pone tras «To» cuando el dinero va a tu propia cuenta en otra divisa.
/// Sin «ron» (también es un nombre).
private let currencyCodes: Set<String> = [
    "eur", "usd", "gbp", "chf", "jpy", "cad", "aud", "nzd", "sek", "nok", "dkk", "pln", "czk", "huf", "bgn", "try",
    "mxn", "brl", "ars", "clp", "cop", "pen", "cny", "hkd", "sgd", "inr", "aed", "sar", "zar", "ils", "thb", "krw",
    "xau", "xag", "btc", "eth",
]
