import Foundation

/// Una fila de la exportación de Trade Republic con todos los campos útiles (también los de inversión: otro plan
/// los reutiliza). `shares` y `price` quedan como texto; quien los use los interpreta. `counterparty_iban` y
/// `payment_reference` NO se leen a propósito.
public struct TradeRepublicRow: Equatable, Sendable {
    public let datetime: Date?
    public let date: Date?
    public let accountType: String?
    public let category: String?
    public let type: String?
    public let assetClass: String?
    public let name: String?
    public let symbol: String?
    public let shares: String?
    public let price: String?
    public let amountCents: Int?
    public let feeCents: Int?
    public let taxCents: Int?
    public let currency: String?
    public let description: String?
    public let transactionID: String?
    public let counterpartyName: String?
    public let mccCode: String?

    /// Efecto en el efectivo: importe + comisión + impuesto, cada uno opcional y con su signo.
    public var cashEffectCents: Int { (amountCents ?? 0) + (feeCents ?? 0) + (taxCents ?? 0) }

    /// Compra, venta o ejecución de un plan de ahorro: una operación de inversión, no un pago. Mueve el saldo pero no
    /// es gasto. Una fila con MCC o de tipo tarjeta nunca lo es.
    public var isSecuritiesTrade: Bool {
        if let mccCode, !mccCode.isEmpty { return false }
        if (type ?? "").uppercased().contains("CARD") { return false }
        if (category ?? "").uppercased() == "TRADING" { return true }
        if let shares, shares.contains(where: { $0.isNumber && $0 != "0" }) { return true }
        if let assetClass, !["CASH", "CARD"].contains(assetClass.uppercased()) { return true }
        return false
    }
}

private func optionalText(_ row: [String], _ column: Int?) -> String? {
    let t = row.cell(column)
    return t.isEmpty ? nil : t
}

private var utcCalendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = .gmt
    return c
}

/// Las filas de la exportación, por nombre de columna (con `,` o `;`). No descarta ninguna fila.
public func parseTradeRepublicExport(_ table: CSVTable) throws -> [TradeRepublicRow] {
    let datetime = table.column(["datetime"])
    let date = table.column(["date"])
    let amount = table.column(["amount"])
    let currency = table.column(["currency"])
    let id = table.column(["transaction_id"])
    var missing: [String] = []
    if datetime == nil && date == nil { missing.append("fecha") }
    if amount == nil { missing.append("importe") }
    if currency == nil { missing.append("divisa") }
    if id == nil { missing.append("transaction_id") }
    guard missing.isEmpty else { throw StatementError.missingColumns(missing) }

    let accountType = table.column(["account_type"]), category = table.column(["category"]), type = table.column(["type"])
    let assetClass = table.column(["asset_class"]), name = table.column(["name"]), symbol = table.column(["symbol"])
    let shares = table.column(["shares"]), price = table.column(["price"])
    let fee = table.column(["fee"]), tax = table.column(["tax"]), description = table.column(["description"])
    let counterparty = table.column(["counterparty_name"]), mcc = table.column(["mcc_code"])

    return table.rows.map { row in
        let day = noonOfDay(row.cell(date), calendar: madridCalendar)?.date
        return TradeRepublicRow(
            datetime: parseStatementTimestamp(row.cell(datetime), calendar: utcCalendar),
            date: day,
            accountType: optionalText(row, accountType), category: optionalText(row, category), type: optionalText(row, type),
            assetClass: optionalText(row, assetClass), name: optionalText(row, name), symbol: optionalText(row, symbol),
            shares: optionalText(row, shares), price: optionalText(row, price),
            amountCents: parseStatementDecimal(row.cell(amount)), feeCents: parseStatementDecimal(row.cell(fee)),
            taxCents: parseStatementDecimal(row.cell(tax)), currency: optionalText(row, currency),
            description: optionalText(row, description), transactionID: optionalText(row, id),
            counterpartyName: optionalText(row, counterparty), mccCode: optionalText(row, mcc))
    }
}

/// Efectivo de Trade Republic: cada fila en euros con efecto distinto de cero es un movimiento. No hay saldo.
func parseTradeRepublicStatement(_ table: CSVTable, calendar: Calendar) throws -> ParsedStatement {
    let rows = try parseTradeRepublicExport(table)
    var records: [BankRecord] = []
    var ignored = 0
    var usedRefs = Set<String>()
    var counter = OccurrenceCounter()

    for row in rows {
        let timing: RecordTiming
        if let datetime = row.datetime {
            timing = .exact(datetime)
        } else if let day = row.date {
            timing = .transactionDay(day)
        } else {
            ignored += 1
            continue
        }
        let effect = row.cashEffectCents
        guard (row.currency ?? "").uppercased() == "EUR", effect != 0 else {
            ignored += 1
            continue
        }
        var ref: String
        if let id = row.transactionID {
            ref = "tr|" + id
        } else {
            let key = [String(Int(timing.date.timeIntervalSince1970)), String(effect), row.type ?? "", row.name ?? "",
                       row.description ?? ""].joined(separator: "|")
            ref = "tr|" + fnv1aHex(key) + "|" + String(counter.next(key))
        }
        // Un mismo transaction_id repetido en el fichero no debe perder la segunda fila.
        if usedRefs.contains(ref) {
            var n = 2
            while usedRefs.contains(ref + "|" + String(n)) { n += 1 }
            ref += "|" + String(n)
        }
        usedRefs.insert(ref)

        let raw = [row.counterpartyName, row.name, row.description].compactMap { $0 }.first { !$0.isEmpty }
        let merchant = raw.map(cleanBankMerchant).flatMap { $0.isEmpty ? nil : $0 }
        let isShop = (row.mccCode.map { !$0.isEmpty && !nonShopMCC.contains($0) } ?? false)
            || (row.type ?? "").uppercased().contains("CARD")
        records.append(BankRecord(
            ref: ref, bank: .tr, amountCents: effect, timing: timing, status: .booked, merchant: merchant, isShop: isShop,
            excludedFromSpending: row.isSecuritiesTrade))
    }
    return ParsedStatement(format: .tradeRepublic, records: records, ignoredRows: ignored, latestBalance: nil)
}
