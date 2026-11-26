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
    /// true = el importe, la comisión o el impuesto traía texto pero no se pudo leer como número. Esa fila no se importa
    /// (su efecto real es desconocido): nunca se toma el valor ilegible como 0.
    public let hasUnreadableAmount: Bool

    public init(datetime: Date? = nil, date: Date? = nil, accountType: String? = nil, category: String? = nil,
                type: String? = nil, assetClass: String? = nil, name: String? = nil, symbol: String? = nil,
                shares: String? = nil, price: String? = nil, amountCents: Int? = nil, feeCents: Int? = nil,
                taxCents: Int? = nil, currency: String? = nil, description: String? = nil, transactionID: String? = nil,
                counterpartyName: String? = nil, mccCode: String? = nil, hasUnreadableAmount: Bool = false) {
        self.datetime = datetime
        self.date = date
        self.accountType = accountType
        self.category = category
        self.type = type
        self.assetClass = assetClass
        self.name = name
        self.symbol = symbol
        self.shares = shares
        self.price = price
        self.amountCents = amountCents
        self.feeCents = feeCents
        self.taxCents = taxCents
        self.currency = currency
        self.description = description
        self.transactionID = transactionID
        self.counterpartyName = counterpartyName
        self.mccCode = mccCode
        self.hasUnreadableAmount = hasUnreadableAmount
    }

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

/// Las filas de la exportación, por nombre de columna (con `,` o `;`). No descarta ninguna fila de las que tienen el
/// número de celdas de la cabecera (las demás ya las apartó `CSVTable`, ver `malformedRows`). Las fechas sin zona se
/// leen en la del calendario dado.
public func parseTradeRepublicExport(_ table: CSVTable, calendar: Calendar) throws -> [TradeRepublicRow] {
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

    func optionalText(_ row: [String], _ column: Int?) -> String? {
        let t = table.cell(row, column)
        return t.isEmpty ? nil : t
    }

    return table.rows.map { row in
        let day = noonOfDay(table.cell(row, date), calendar: calendar)?.date
        let amountText = table.cell(row, amount), feeText = table.cell(row, fee), taxText = table.cell(row, tax)
        let amountValue = parseStatementDecimal(amountText)
        let feeValue = parseStatementDecimal(feeText)
        let taxValue = parseStatementDecimal(taxText)
        let unreadable = (!amountText.isEmpty && amountValue == nil) || (!feeText.isEmpty && feeValue == nil)
            || (!taxText.isEmpty && taxValue == nil)
        return TradeRepublicRow(
            datetime: parseStatementTimestamp(table.cell(row, datetime), calendar: calendar),
            date: day,
            accountType: optionalText(row, accountType), category: optionalText(row, category), type: optionalText(row, type),
            assetClass: optionalText(row, assetClass), name: optionalText(row, name), symbol: optionalText(row, symbol),
            shares: optionalText(row, shares), price: optionalText(row, price),
            amountCents: amountValue, feeCents: feeValue, taxCents: taxValue, currency: optionalText(row, currency),
            description: optionalText(row, description), transactionID: optionalText(row, id),
            counterpartyName: optionalText(row, counterparty), mccCode: optionalText(row, mcc),
            hasUnreadableAmount: unreadable)
    }
}

/// Igual que la anterior con el calendario de Madrid (el de los extractos de Trade Republic).
public func parseTradeRepublicExport(_ table: CSVTable) throws -> [TradeRepublicRow] {
    try parseTradeRepublicExport(table, calendar: madridCalendar)
}

/// Efectivo de Trade Republic: cada fila en euros con efecto distinto de cero es un movimiento. No hay saldo.
func parseTradeRepublicStatement(_ table: CSVTable, calendar: Calendar) throws -> ParsedStatement {
    let rows = try parseTradeRepublicExport(table, calendar: calendar)
    var records: [BankRecord] = []
    var ignored = 0
    var usedRefs = Set<String>()
    var usedLegacyRefs = Set<String>()
    var counter = OccurrenceCounter()
    var legacyCounter = OccurrenceCounter()

    for row in rows {
        // Un importe, comisión o impuesto con texto que no se entiende: la fila no se importa (nunca como 0).
        if row.hasUnreadableAmount {
            ignored += 1
            continue
        }
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
        var legacyRef: String
        if let id = row.transactionID {
            ref = "tr|" + id
            legacyRef = ref
            // Un mismo transaction_id repetido en el fichero no debe perder la segunda fila: la repetida lleva el efecto
            // en céntimos (estable entre ficheros que se solapan) y, si aun así choca, un contador.
            if usedRefs.contains(ref) {
                ref += "|" + String(effect)
                var n = 2
                while usedRefs.contains(ref) {
                    ref = "tr|" + id + "|" + String(effect) + "|" + String(n)
                    n += 1
                }
            }
            // La versión anterior sufijaba con un contador (2, 3, ...).
            if usedLegacyRefs.contains(legacyRef) {
                var n = 2
                while usedLegacyRefs.contains(legacyRef + "|" + String(n)) { n += 1 }
                legacyRef += "|" + String(n)
            }
        } else {
            let seconds = String(Int(timing.date.timeIntervalSince1970))
            let key = [seconds, String(effect), normalizedStatementText(row.type ?? ""), normalizedStatementText(row.name ?? ""),
                       normalizedStatementText(row.description ?? "")].joined(separator: "|")
            ref = "tr|" + fnv1aHex(key) + "|" + String(counter.next(key))
            let legacyKey = [seconds, String(effect), row.type ?? "", row.name ?? "", row.description ?? ""].joined(separator: "|")
            legacyRef = "tr|" + fnv1aHex(legacyKey) + "|" + String(legacyCounter.next(legacyKey))
        }
        usedRefs.insert(ref)
        usedLegacyRefs.insert(legacyRef)

        let raw = [row.counterpartyName, row.name, row.description].compactMap { $0 }.first { !$0.isEmpty }
        let merchant = raw.map(cleanBankMerchant).flatMap { $0.isEmpty ? nil : $0 }
        let isShop = (row.mccCode.map { !$0.isEmpty && !nonShopMCC.contains($0) } ?? false)
            || (row.type ?? "").uppercased().contains("CARD")
        // Solo el código de comercio: los nombres exactos de `type` de una transferencia no se conocen.
        let personPayment = effect < 0 && !isShop && row.mccCode.map { transferMCC.contains($0) } == true
        records.append(BankRecord(
            ref: ref, bank: .tr, amountCents: effect, timing: timing, status: .booked, merchant: merchant, isShop: isShop,
            excludedFromSpending: row.isSecuritiesTrade, legacyRefs: legacyRef == ref ? [] : [legacyRef],
            personPayment: personPayment))
    }
    return ParsedStatement(format: .tradeRepublic, records: records, ignoredRows: ignored, latestBalance: nil)
}
