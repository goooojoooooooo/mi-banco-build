import Foundation

// MARK: Números

/// Texto -> Decimal. Acepta "10.5", "10,5", "-955.00", "1.234,56" y "1,234.56". Con los dos separadores manda el último
/// (el otro es de miles); con uno solo repetido es de miles; con uno solo una vez es el decimal. Vacío, letras,
/// exponentes o más de 30 dígitos -> nil.
public func parseDecimal(_ raw: String) -> Decimal? {
    var s = raw.replacingOccurrences(of: "\u{2212}", with: "-").filter { !$0.isWhitespace }
    var negative = false
    if s.hasPrefix("-") {
        negative = true
        s.removeFirst()
    } else if s.hasPrefix("+") {
        s.removeFirst()
    }
    guard !s.isEmpty, s.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "." || $0 == ",") }) else { return nil }
    let digits = s.filter { $0.isNumber }
    guard !digits.isEmpty, digits.count <= 30 else { return nil }
    let lastComma = s.lastIndex(of: ","), lastDot = s.lastIndex(of: ".")
    var decimalSeparator: Character?
    switch (lastComma, lastDot) {
    case let (c?, d?): decimalSeparator = c > d ? "," : "."
    case (_?, nil): decimalSeparator = s.filter { $0 == "," }.count == 1 ? "," : nil
    case (nil, _?): decimalSeparator = s.filter { $0 == "." }.count == 1 ? "." : nil
    default: break
    }
    var integer = "", fraction = ""
    var inFraction = false
    for ch in s {
        if ch == "," || ch == "." {
            if ch == decimalSeparator { inFraction = true }
        } else if inFraction {
            fraction.append(ch)
        } else {
            integer.append(ch)
        }
    }
    // Un separador de miles repetido tras el decimal ("1.2.3,4") no es un número.
    if decimalSeparator != nil, s.filter({ $0 == decimalSeparator }).count != 1 { return nil }
    guard let value = Decimal(string: (integer.isEmpty ? "0" : integer) + (fraction.isEmpty ? "" : "." + fraction), locale: nil),
          value.isFinite else { return nil }
    return negative ? -value : value
}

/// Decimal -> entero redondeando las mitades hacia fuera del cero; nil si no es finito o no cabe con holgura.
func roundedInt(_ value: Decimal) -> Int? {
    guard value.isFinite else { return nil }
    var input = value
    var output = Decimal()
    NSDecimalRound(&output, &input, 0, .plain)
    guard output.isFinite, output.magnitude < Decimal(1_000_000_000_000) else { return nil }
    return NSDecimalNumber(decimal: output).intValue
}

/// `numerator / denominator` redondeado con las mitades hacia fuera del cero; nil si el divisor es 0.
func roundedQuotient(_ numerator: Int, _ denominator: Int) -> Int? {
    guard denominator != 0 else { return nil }
    let q = Int((numerator.magnitude * 2 + denominator.magnitude) / (denominator.magnitude * 2))
    return (numerator < 0) != (denominator < 0) ? -q : q
}

// MARK: Lectura/escritura tolerante

/// Decodifica un valor sin fallar nunca: si no se entiende queda en nil (y se descarta al filtrar).
private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
}

private extension KeyedDecodingContainer {
    /// Decimal guardado como texto (exacto) o como número; nunca NaN.
    func decimal(_ key: Key) throws -> Decimal {
        if let text = try? decode(String.self, forKey: key), let d = Decimal(string: text, locale: nil), d.isFinite { return d }
        let d = try decode(Decimal.self, forKey: key)
        guard d.isFinite else { throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "no finito") }
        return d
    }

    func decimalIfPresent(_ key: Key) -> Decimal? { try? decimal(key) }
}

private func text(_ d: Decimal) -> String { "\(d)" }

// MARK: Operaciones

public struct InvestmentTransaction: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let date: Date
    public let instrument: String
    public let name: String
    public let assetClass: String?
    /// Positivo entra, negativo sale.
    public let shares: Decimal
    /// Importe + comisión + impuesto, en céntimos y con su signo.
    public let cashCents: Int
    public let priceEUR: Decimal?

    public init(id: String, date: Date, instrument: String, name: String, assetClass: String?, shares: Decimal, cashCents: Int,
                priceEUR: Decimal?) {
        self.id = id
        self.date = date
        self.instrument = instrument
        self.name = name
        self.assetClass = assetClass
        self.shares = shares
        self.cashCents = cashCents
        self.priceEUR = priceEUR
    }

    private enum Keys: String, CodingKey { case id, date, instrument, name, assetClass, shares, cashCents, priceEUR }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        instrument = try c.decode(String.self, forKey: .instrument)
        name = (try? c.decode(String.self, forKey: .name)) ?? instrument
        assetClass = try? c.decodeIfPresent(String.self, forKey: .assetClass)
        shares = try c.decimal(.shares)
        cashCents = (try? c.decode(Int.self, forKey: .cashCents)) ?? 0
        priceEUR = c.decimalIfPresent(.priceEUR)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(id, forKey: .id)
        try c.encode(date, forKey: .date)
        try c.encode(instrument, forKey: .instrument)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(assetClass, forKey: .assetClass)
        try c.encode(text(shares), forKey: .shares)
        try c.encode(cashCents, forKey: .cashCents)
        try c.encodeIfPresent(priceEUR.map(text), forKey: .priceEUR)
    }
}

public struct InvestmentExtract: Equatable, Sendable {
    public let transactions: [InvestmentTransaction]
    public let ignoredRows: Int
    public let unreadableRows: Int
}

/// Las operaciones de inversión de las filas ya leídas. Ignorada: sin símbolo o sin acciones (o a cero). Ilegible: sin
/// identificador, sin fecha, acciones que no son un número o divisa que no es el euro (no se mezclan monedas).
/// Signo: acciones negativas = venta; positivas con importe positivo = venta (se guarda en negativo); si no, compra.
public func investmentTransactions(from rows: [TradeRepublicRow]) -> InvestmentExtract {
    var result: [InvestmentTransaction] = []
    var ignored = 0, unreadable = 0
    for row in rows {
        let symbol = (row.symbol ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let sharesText = (row.shares ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if symbol.isEmpty || sharesText.isEmpty {
            ignored += 1
            continue
        }
        guard let parsed = parseDecimal(sharesText) else {
            unreadable += 1
            continue
        }
        if parsed == 0 {
            ignored += 1
            continue
        }
        let currency = (row.currency ?? "").uppercased()
        guard let id = row.transactionID, !id.isEmpty, let date = row.datetime ?? row.date,
              currency.isEmpty || currency == "EUR" else {
            unreadable += 1
            continue
        }
        let amount = row.amountCents ?? 0
        let shares: Decimal = parsed < 0 ? parsed : (amount > 0 ? -parsed : parsed)
        let price = row.price.flatMap(parseDecimal).flatMap { $0 > 0 ? $0 : nil }
        let name = (row.name ?? "").isEmpty ? symbol : row.name!
        result.append(InvestmentTransaction(id: id, date: date, instrument: symbol, name: name, assetClass: row.assetClass,
                                            shares: shares, cashCents: row.cashEffectCents, priceEUR: price))
    }
    return InvestmentExtract(transactions: result, ignoredRows: ignored, unreadableRows: unreadable)
}

// MARK: Precios y cartera

public struct Quote: Codable, Equatable, Sendable {
    public let priceEUR: Decimal
    public let previousCloseEUR: Decimal?
    public let fetchedAt: Date

    public init(priceEUR: Decimal, previousCloseEUR: Decimal?, fetchedAt: Date) {
        self.priceEUR = priceEUR
        self.previousCloseEUR = previousCloseEUR
        self.fetchedAt = fetchedAt
    }

    private enum Keys: String, CodingKey { case priceEUR, previousCloseEUR, fetchedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        priceEUR = try c.decimal(.priceEUR)
        previousCloseEUR = c.decimalIfPresent(.previousCloseEUR)
        fetchedAt = try c.decode(Date.self, forKey: .fetchedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(text(priceEUR), forKey: .priceEUR)
        try c.encodeIfPresent(previousCloseEUR.map(text), forKey: .previousCloseEUR)
        try c.encode(fetchedAt, forKey: .fetchedAt)
    }
}

public struct ManualPrice: Codable, Equatable, Sendable {
    public let priceEUR: Decimal
    public let setAt: Date

    public init(priceEUR: Decimal, setAt: Date) {
        self.priceEUR = priceEUR
        self.setAt = setAt
    }

    private enum Keys: String, CodingKey { case priceEUR, setAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        priceEUR = try c.decimal(.priceEUR)
        setAt = try c.decode(Date.self, forKey: .setAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(text(priceEUR), forKey: .priceEUR)
        try c.encode(setAt, forKey: .setAt)
    }
}

public struct ImportSummary: Equatable, Sendable {
    public let added: Int
    public let alreadyThere: Int
    public let ignoredRows: Int
    public let unreadableRows: Int

    public init(added: Int, alreadyThere: Int, ignoredRows: Int, unreadableRows: Int) {
        self.added = added
        self.alreadyThere = alreadyThere
        self.ignoredRows = ignoredRows
        self.unreadableRows = unreadableRows
    }
}

/// Todo lo guardado de inversiones. `quotes` y `manualPrices` van por instrumento (el símbolo de la exportación);
/// `symbols` guarda el símbolo de consulta de precios ya resuelto para cada instrumento.
public struct Portfolio: Codable, Equatable, Sendable {
    public var transactions: [InvestmentTransaction]
    public var quotes: [String: Quote]
    public var manualPrices: [String: ManualPrice]
    public var symbols: [String: String]
    public var lastImport: Date?

    public init() {
        transactions = []
        quotes = [:]
        manualPrices = [:]
        symbols = [:]
        lastImport = nil
    }

    private enum Keys: String, CodingKey { case transactions, quotes, manualPrices, symbols, lastImport }

    /// Tolerante: un campo que falta o no se entiende queda vacío y una entrada rota se descarta; el resto se conserva.
    /// Lo descartado se recupera volviendo a importar la exportación.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: Keys.self)
        transactions = ((try? c.decode([Lossy<InvestmentTransaction>].self, forKey: .transactions)) ?? []).compactMap(\.value)
        quotes = ((try? c.decode([String: Lossy<Quote>].self, forKey: .quotes)) ?? [:]).compactMapValues(\.value)
        manualPrices = ((try? c.decode([String: Lossy<ManualPrice>].self, forKey: .manualPrices)) ?? [:]).compactMapValues(\.value)
        symbols = ((try? c.decode([String: Lossy<String>].self, forKey: .symbols)) ?? [:]).compactMapValues(\.value)
        lastImport = try? c.decodeIfPresent(Date.self, forKey: .lastImport)
    }

    /// Añade las operaciones nuevas (por identificador), deja la lista por fecha e identificador y anota la importación.
    public mutating func merge(_ extract: InvestmentExtract, now: Date) -> ImportSummary {
        var known = Set(transactions.map(\.id))
        var added = 0, already = 0
        for t in extract.transactions {
            if known.insert(t.id).inserted {
                transactions.append(t)
                added += 1
            } else {
                already += 1
            }
        }
        transactions.sort { $0.date != $1.date ? $0.date < $1.date : $0.id < $1.id }
        lastImport = now
        return ImportSummary(added: added, alreadyThere: already, ignoredRows: extract.ignoredRows,
                             unreadableRows: extract.unreadableRows)
    }
}

// MARK: Posiciones

public struct Position: Equatable, Sendable, Identifiable {
    public let instrument: String
    public let name: String
    public let assetClass: String?
    public let shares: Decimal
    public let costCents: Int
    public var id: String { instrument }
}

/// Posiciones abiertas con coste medio: la compra suma acciones y su coste (el efectivo que salió; si fue 0, acciones ×
/// precio); la venta quita el coste proporcional. Vender más de lo que hay deja la posición a cero. Orden por nombre.
public func positions(from transactions: [InvestmentTransaction]) -> [Position] {
    struct Acc { var name: String; var assetClass: String?; var shares: Decimal = 0; var cost: Int = 0 }
    var byInstrument: [String: Acc] = [:]
    let ordered = transactions.enumerated().sorted {
        $0.element.date != $1.element.date ? $0.element.date < $1.element.date : $0.offset < $1.offset
    }.map(\.element)
    for t in ordered {
        var acc = byInstrument[t.instrument] ?? Acc(name: t.name, assetClass: t.assetClass)
        if !t.name.isEmpty { acc.name = t.name }
        if let a = t.assetClass, !a.isEmpty { acc.assetClass = a }
        if t.shares > 0 {
            var add = max(0, -t.cashCents)
            if t.cashCents == 0, let price = t.priceEUR { add = roundedInt(t.shares * price * 100) ?? 0 }
            acc.shares += t.shares
            acc.cost += add
        } else if t.shares < 0, acc.shares > 0 {
            let sold = -t.shares
            if sold >= acc.shares {
                acc.shares = 0
                acc.cost = 0
            } else {
                acc.cost -= roundedInt(Decimal(acc.cost) * sold / acc.shares) ?? acc.cost
                acc.shares -= sold
            }
        }
        byInstrument[t.instrument] = acc
    }
    return byInstrument.filter { $0.value.shares > 0 }
        .map { Position(instrument: $0.key, name: $0.value.name, assetClass: $0.value.assetClass, shares: $0.value.shares,
                        costCents: max(0, $0.value.cost)) }
        .sorted {
            let a = $0.name.lowercased(), b = $1.name.lowercased()
            return a != b ? a < b : $0.instrument < $1.instrument
        }
}

// MARK: Valoración

public enum PriceOrigin: Equatable, Sendable {
    case market(Date), manual(Date), none
}

public struct PositionValue: Equatable, Sendable, Identifiable {
    public let position: Position
    public let priceEUR: Decimal?
    public let origin: PriceOrigin
    public let valueCents: Int?
    public let todayChangeCents: Int?
    public let gainCents: Int?
    public let gainTenths: Int?
    public var id: String { position.id }
}

public struct PortfolioSummary: Equatable, Sendable {
    /// Valor de las posiciones con precio.
    public let valueCents: Int
    public let todayChangeCents: Int
    public let todayChangeTenths: Int?
    /// Coste de todas las posiciones; la ganancia solo compara las que tienen precio.
    public let costCents: Int
    public let gainCents: Int
    public let gainTenths: Int?
    /// El precio más reciente de los usados.
    public let pricedAt: Date?
    public let missingPrices: Int
    public let positions: [PositionValue]
}

private func value(of position: Position, in portfolio: Portfolio) -> PositionValue {
    var price: Decimal?
    var origin = PriceOrigin.none
    var previous: Decimal?
    let quote = portfolio.quotes[position.instrument].flatMap { $0.priceEUR > 0 ? $0 : nil }
    let manual = portfolio.manualPrices[position.instrument].flatMap { $0.priceEUR > 0 ? $0 : nil }
    if let manual, quote == nil || manual.setAt > quote!.fetchedAt {
        price = manual.priceEUR
        origin = .manual(manual.setAt)
    } else if let quote {
        price = quote.priceEUR
        origin = .market(quote.fetchedAt)
        previous = quote.previousCloseEUR.flatMap { $0 > 0 ? $0 : nil }
    }
    guard let price, let valueCents = roundedInt(position.shares * price * 100) else {
        return PositionValue(position: position, priceEUR: nil, origin: .none, valueCents: nil, todayChangeCents: nil,
                             gainCents: nil, gainTenths: nil)
    }
    let today = previous.flatMap { roundedInt(position.shares * (price - $0) * 100) }
    let gain = valueCents - position.costCents
    return PositionValue(position: position, priceEUR: price, origin: origin, valueCents: valueCents, todayChangeCents: today,
                         gainCents: gain, gainTenths: roundedQuotient(1000 * gain, position.costCents))
}

/// Resumen de la cartera; nil si no hay posiciones abiertas. Describe, no recomienda.
public func portfolioSummary(_ portfolio: Portfolio) -> PortfolioSummary? {
    let values = positions(from: portfolio.transactions).map { value(of: $0, in: portfolio) }
    guard !values.isEmpty else { return nil }
    let priced = values.filter { $0.valueCents != nil }
    let totalValue = priced.reduce(0) { $0 + ($1.valueCents ?? 0) }
    let pricedCost = priced.reduce(0) { $0 + $1.position.costCents }
    let withToday = priced.filter { $0.todayChangeCents != nil }
    let today = withToday.reduce(0) { $0 + ($1.todayChangeCents ?? 0) }
    let valueWithToday = withToday.reduce(0) { $0 + ($1.valueCents ?? 0) }
    let gain = totalValue - pricedCost
    let dates: [Date] = priced.compactMap {
        switch $0.origin {
        case .market(let d), .manual(let d): return d
        case .none: return nil
        }
    }
    return PortfolioSummary(
        valueCents: totalValue, todayChangeCents: today,
        todayChangeTenths: withToday.isEmpty ? nil : roundedQuotient(1000 * today, valueWithToday - today),
        costCents: values.reduce(0) { $0 + $1.position.costCents }, gainCents: gain,
        gainTenths: roundedQuotient(1000 * gain, pricedCost), pricedAt: dates.max(),
        missingPrices: values.count - priced.count, positions: values)
}
