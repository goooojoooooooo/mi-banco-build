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

/// Lectura española para el precio a mano (U9): «,» es decimal; «.» seguido de 3 cifras son miles;
/// un único «.» seguido de 1, 2 o 4+ cifras (o tras «0.») sin coma se lee como decimal. Quita espacios y «€».
public func parseManualPriceES(_ raw: String) -> Decimal? {
    let s = raw.filter { !$0.isWhitespace && $0 != "€" }
    guard !s.isEmpty, s.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "." || $0 == ",") }) else { return nil }
    let digits = s.filter { $0.isNumber }
    guard !digits.isEmpty, digits.count <= 30 else { return nil }

    if s.contains(",") {
        guard s.filter({ $0 == "," }).count == 1 else { return nil }
        let parts = s.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { return nil }
        let intPart = parts[0], fracPart = parts[1]
        guard !intPart.isEmpty, !fracPart.isEmpty, fracPart.allSatisfy(\.isNumber) else { return nil }
        let cleanInt: String
        if intPart.contains(".") {
            let groups = intPart.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard groups.count >= 2,
                  (1...3).contains(groups[0].count), !groups[0].hasPrefix("0"), groups[0].allSatisfy(\.isNumber),
                  groups.dropFirst().allSatisfy({ $0.count == 3 && $0.allSatisfy(\.isNumber) }) else { return nil }
            cleanInt = groups.joined()
        } else {
            guard intPart.allSatisfy(\.isNumber) else { return nil }
            cleanInt = intPart
        }
        guard let d = Decimal(string: "\(cleanInt).\(fracPart)", locale: nil), d.isFinite else { return nil }
        return d
    }

    if s.contains(".") {
        let groups = s.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard groups.count >= 2, groups.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        if (1...3).contains(groups[0].count), !groups[0].hasPrefix("0"),
           groups.dropFirst().allSatisfy({ $0.count == 3 }) {
            guard let d = Decimal(string: groups.joined(), locale: nil), d.isFinite else { return nil }
            return d
        }
        if groups.count == 2 && (groups[1].count != 3 || groups[0] == "0") {
            guard let d = Decimal(string: "\(groups[0]).\(groups[1])", locale: nil), d.isFinite else { return nil }
            return d
        }
        return nil
    }

    guard let d = Decimal(string: s, locale: nil), d.isFinite else { return nil }
    return d
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
    /// true = las acciones entraron sin ser una compra (entrega gratuita, traspaso de entrada, saveback, redondeo): su coste es
    /// el importe de la fila si lo trae y, si no, desconocido (0), y la posición no cuenta ganancia.
    public let acquired: Bool
    /// true = las acciones salieron por traspaso (`TRANSFER_OUT`), no por una venta (U14).
    public let disposed: Bool

    public init(id: String, date: Date, instrument: String, name: String, assetClass: String?, shares: Decimal, cashCents: Int,
                priceEUR: Decimal?, acquired: Bool = false, disposed: Bool = false) {
        self.id = id
        self.date = date
        self.instrument = instrument
        self.name = name
        self.assetClass = assetClass
        self.shares = shares
        self.cashCents = cashCents
        self.priceEUR = priceEUR
        self.acquired = acquired
        self.disposed = disposed
    }

    private enum Keys: String, CodingKey { case id, date, instrument, name, assetClass, shares, cashCents, priceEUR, acquired, disposed }

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
        acquired = ((try? c.decodeIfPresent(Bool.self, forKey: .acquired)) ?? nil) ?? false
        disposed = ((try? c.decodeIfPresent(Bool.self, forKey: .disposed)) ?? nil) ?? false
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
        if acquired { try c.encode(true, forKey: .acquired) }
        if disposed { try c.encode(true, forKey: .disposed) }
    }
}

public struct InvestmentExtract: Equatable, Sendable {
    public let transactions: [InvestmentTransaction]
    public let ignoredRows: Int
    public let unreadableRows: Int
    /// Filas con símbolo y acciones que NO son compra ni venta (dividendo, devolución de impuestos, split, traspaso...):
    /// no cambian ninguna posición y se cuentan aparte para decírselo al dueño.
    public let notTradeRows: Int
    /// Los nombres distintos de esos tipos (en mayúsculas y ordenados), para decirle al dueño cuáles no se aplicaron.
    public let notTradeTypes: [String]

    public init(transactions: [InvestmentTransaction], ignoredRows: Int, unreadableRows: Int, notTradeRows: Int = 0,
                notTradeTypes: [String] = []) {
        self.transactions = transactions
        self.ignoredRows = ignoredRows
        self.unreadableRows = unreadableRows
        self.notTradeRows = notTradeRows
        self.notTradeTypes = notTradeTypes
    }
}

/// Tipo de una fila. BUY, SELL, SAVINGS_PLAN (y sus grafías: "SAVINGS PLAN", "SavingsPlan") y TRADE son operaciones;
/// FREE_RECEIPT, TRANSFER_IN, SAVEBACK y ROUND_UP añaden acciones sin ser una compra (`acquire`); TRANSFER_OUT las quita como
/// una venta (sin ganancia que contar); cualquier otro tipo no mueve nada. Tipo vacío o ausente -> nil (se decide por el signo).
private enum RowKind { case buy, sell, dispose, trade, acquire, other }

private func rowKind(_ type: String?) -> RowKind? {
    let folded = (type ?? "").uppercased().filter { $0.isLetter || $0.isNumber }
    if folded.isEmpty { return nil }
    switch folded {
    case "BUY", "SAVINGSPLAN": return .buy
    case "SELL": return .sell
    case "TRANSFEROUT": return .dispose
    case "FREERECEIPT", "TRANSFERIN", "SAVEBACK", "SAVEBACKS", "ROUNDUP", "ROUNDUPS": return .acquire
    case "TRADE": return .trade
    default: return .other
    }
}

/// Las operaciones de inversión de las filas ya leídas. Ignorada: sin símbolo o sin acciones (o a cero). Ilegible: sin
/// identificador, sin fecha, acciones que no son un número o divisa que no es el euro (no se mezclan monedas).
/// Solo mueve una posición una fila de tipo BUY, SELL o SAVINGS_PLAN (o TRADE con dirección clara); el resto de filas con
/// símbolo y acciones (dividendos, devoluciones, splits, traspasos...) se cuentan en `notTradeRows` y no se aplican.
/// Dirección: SELL o acciones negativas = venta; BUY y SAVINGS_PLAN = compra. Solo sin tipo se deduce del importe:
/// acciones positivas con importe positivo = venta (se guarda en negativo); si no, compra.
public func investmentTransactions(from rows: [TradeRepublicRow]) -> InvestmentExtract {
    var result: [InvestmentTransaction] = []
    var ignored = 0, unreadable = 0, notTrade = 0
    var notTradeTypes = Set<String>()
    func skip(_ row: TradeRepublicRow) {
        notTrade += 1
        let name = (row.type ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !name.isEmpty { notTradeTypes.insert(name) }
    }
    for row in rows {
        let symbol = (row.symbol ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let sharesText = (row.shares ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if symbol.isEmpty || sharesText.isEmpty {
            ignored += 1
            continue
        }
        let kind = rowKind(row.type)
        if kind == .other {
            skip(row)
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
        let shares: Decimal
        switch kind {
        case .sell?, .dispose?:
            shares = -parsed.magnitude
        case .buy?:
            shares = parsed
        case .trade?:
            // TRADE sin dirección en el tipo: solo con señal clara (acciones negativas o efectivo que sale).
            if parsed < 0 || row.cashEffectCents < 0 {
                shares = parsed
            } else {
                skip(row)
                continue
            }
        case .acquire?:
            shares = parsed.magnitude
        case .other?:
            continue
        case nil:
            shares = parsed < 0 ? parsed : (amount > 0 ? -parsed : parsed)
        }
        let price = row.price.flatMap(parseDecimal).flatMap { $0 > 0 ? $0 : nil }
        let name = (row.name ?? "").isEmpty ? symbol : row.name!
        result.append(InvestmentTransaction(id: id, date: date, instrument: symbol, name: name, assetClass: row.assetClass,
                                            shares: shares, cashCents: row.cashEffectCents, priceEUR: price,
                                            acquired: kind == .acquire, disposed: kind == .dispose))
    }
    return InvestmentExtract(transactions: result, ignoredRows: ignored, unreadableRows: unreadable, notTradeRows: notTrade,
                             notTradeTypes: notTradeTypes.sorted())
}

// MARK: Precios y cartera

public struct Quote: Codable, Equatable, Sendable {
    public let priceEUR: Decimal
    public let previousCloseEUR: Decimal?
    public let fetchedAt: Date
    /// La hora del propio precio en el mercado (`regularMarketTime`); la edad del precio se mide con ella, no con la consulta.
    public let marketTime: Date?

    public init(priceEUR: Decimal, previousCloseEUR: Decimal?, fetchedAt: Date, marketTime: Date? = nil) {
        self.priceEUR = priceEUR
        self.previousCloseEUR = previousCloseEUR
        self.fetchedAt = fetchedAt
        self.marketTime = marketTime
    }

    private enum Keys: String, CodingKey { case priceEUR, previousCloseEUR, fetchedAt, marketTime }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        priceEUR = try c.decimal(.priceEUR)
        previousCloseEUR = c.decimalIfPresent(.previousCloseEUR)
        fetchedAt = try c.decode(Date.self, forKey: .fetchedAt)
        marketTime = try? c.decodeIfPresent(Date.self, forKey: .marketTime)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(text(priceEUR), forKey: .priceEUR)
        try c.encodeIfPresent(previousCloseEUR.map(text), forKey: .previousCloseEUR)
        try c.encode(fetchedAt, forKey: .fetchedAt)
        try c.encodeIfPresent(marketTime, forKey: .marketTime)
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
    /// Filas que no son compras ni ventas (dividendos, devoluciones...): no cambian la cartera.
    public let notTradeRows: Int
    /// Los tipos distintos que no se aplicaron (en mayúsculas y ordenados), para nombrarlos en la app.
    public let notAppliedTypes: [String]

    public init(added: Int, alreadyThere: Int, ignoredRows: Int, unreadableRows: Int, notTradeRows: Int = 0,
                notAppliedTypes: [String] = []) {
        self.added = added
        self.alreadyThere = alreadyThere
        self.ignoredRows = ignoredRows
        self.unreadableRows = unreadableRows
        self.notTradeRows = notTradeRows
        self.notAppliedTypes = notAppliedTypes
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
    /// Entradas que la lectura tolerante descartó por no entenderse (una lista con el tipo equivocado cuenta como 1). No se
    /// guarda: sirve para avisar «vuelve a importar tu extracto» tras cargar.
    public internal(set) var droppedEntries: Int = 0

    public static func == (a: Portfolio, b: Portfolio) -> Bool {
        a.transactions == b.transactions && a.quotes == b.quotes && a.manualPrices == b.manualPrices
            && a.symbols == b.symbols && a.lastImport == b.lastImport
    }

    public init() {
        transactions = []
        quotes = [:]
        manualPrices = [:]
        symbols = [:]
        lastImport = nil
    }

    private enum Keys: String, CodingKey { case transactions, quotes, manualPrices, symbols, lastImport }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(transactions, forKey: .transactions)
        try c.encode(quotes, forKey: .quotes)
        try c.encode(manualPrices, forKey: .manualPrices)
        try c.encode(symbols, forKey: .symbols)
        try c.encodeIfPresent(lastImport, forKey: .lastImport)
    }

    /// Tolerante: un campo que falta o no se entiende queda vacío y una entrada rota se descarta; el resto se conserva.
    /// Lo descartado se recupera volviendo a importar la exportación.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: Keys.self)
        var dropped = 0
        func present(_ key: Keys) -> Bool { c.contains(key) && ((try? c.decodeNil(forKey: key)) == false) }
        if let raw = try? c.decode([Lossy<InvestmentTransaction>].self, forKey: .transactions) {
            transactions = raw.compactMap(\.value)
            dropped += raw.count - transactions.count
        } else if present(.transactions) { dropped += 1 }
        if let raw = try? c.decode([String: Lossy<Quote>].self, forKey: .quotes) {
            quotes = raw.compactMapValues(\.value)
            dropped += raw.count - quotes.count
        } else if present(.quotes) { dropped += 1 }
        if let raw = try? c.decode([String: Lossy<ManualPrice>].self, forKey: .manualPrices) {
            manualPrices = raw.compactMapValues(\.value)
            dropped += raw.count - manualPrices.count
        } else if present(.manualPrices) { dropped += 1 }
        if let raw = try? c.decode([String: Lossy<String>].self, forKey: .symbols) {
            symbols = raw.compactMapValues(\.value)
            dropped += raw.count - symbols.count
        } else if present(.symbols) { dropped += 1 }
        droppedEntries = dropped
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
        transactions = orderedTransactions(transactions)
        lastImport = now
        return ImportSummary(added: added, alreadyThere: already, ignoredRows: extract.ignoredRows,
                             unreadableRows: extract.unreadableRows, notTradeRows: extract.notTradeRows,
                             notAppliedTypes: extract.notTradeTypes)
    }
}

// MARK: Posiciones

/// Por fecha; con la misma fecha (o filas de solo día) primero las compras y luego las ventas; si no, se conserva el
/// orden en que llegaron (el de la exportación).
func orderedTransactions(_ list: [InvestmentTransaction]) -> [InvestmentTransaction] {
    list.enumerated().sorted { a, b in
        if a.element.date != b.element.date { return a.element.date < b.element.date }
        let aBuy = a.element.shares > 0, bBuy = b.element.shares > 0
        return aBuy != bBuy ? aBuy : a.offset < b.offset
    }.map(\.element)
}

public struct Position: Equatable, Sendable, Identifiable {
    public let instrument: String
    public let name: String
    public let assetClass: String?
    public let shares: Decimal
    public let costCents: Int
    /// true = alguna entrada de acciones no tiene coste conocido (entrega gratuita sin importe...): no hay ganancia que contar.
    public let costIncomplete: Bool
    public var id: String { instrument }
    /// Con coste conocido y completo hay ganancia que contar; si no, ninguna.
    var hasKnownCost: Bool { costCents > 0 && !costIncomplete }
}

/// Posiciones abiertas con coste medio: la compra suma acciones y su coste (el efectivo que salió; si fue 0, acciones ×
/// precio); la venta quita el coste proporcional. Vender más de lo que hay deja la posición a cero. Orden por nombre.
public func positions(from transactions: [InvestmentTransaction]) -> [Position] {
    struct Acc { var name: String; var assetClass: String?; var shares: Decimal = 0; var cost: Int = 0; var incomplete = false }
    var byInstrument: [String: Acc] = [:]
    let ordered = orderedTransactions(transactions)
    for t in ordered {
        var acc = byInstrument[t.instrument] ?? Acc(name: t.name, assetClass: t.assetClass)
        if !t.name.isEmpty { acc.name = t.name }
        if let a = t.assetClass, !a.isEmpty { acc.assetClass = a }
        if t.shares > 0 {
            var add = max(0, -t.cashCents)
            if t.cashCents == 0, !t.acquired, let price = t.priceEUR { add = roundedInt(t.shares * price * 100) ?? 0 }
            if add == 0 { acc.incomplete = true }
            acc.shares += t.shares
            acc.cost += add
        } else if t.shares < 0, acc.shares > 0 {
            let sold = -t.shares
            if sold >= acc.shares {
                acc.shares = 0
                acc.cost = 0
                acc.incomplete = false
            } else {
                acc.cost -= roundedInt(Decimal(acc.cost) * sold / acc.shares) ?? acc.cost
                acc.shares -= sold
            }
        }
        byInstrument[t.instrument] = acc
    }
    return byInstrument.filter { $0.value.shares > 0 }
        .map { Position(instrument: $0.key, name: $0.value.name, assetClass: $0.value.assetClass, shares: $0.value.shares,
                        costCents: max(0, $0.value.cost), costIncomplete: $0.value.incomplete) }
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

/// Un precio con más de 4 días se considera viejo.
public let stalePriceAge: TimeInterval = 4 * 86_400

public struct PortfolioSummary: Equatable, Sendable {
    /// Valor de las posiciones con precio; nil si ninguna tiene precio (no 0).
    public let valueCents: Int?
    /// nil si ninguna posición con precio trae cierre anterior: no hay cambio de hoy que contar.
    public let todayChangeCents: Int?
    public let todayChangeTenths: Int?
    /// El día de negociación al que pertenece ese cambio (inicio de ese día en Madrid, según la hora del precio más reciente
    /// que lo aporta); nil si no hay cambio. No es «hoy» si el mercado lleva días sin moverse.
    public let changeDay: Date?
    /// Coste de todas las posiciones; la ganancia solo compara las que tienen precio y coste.
    public let costCents: Int
    public let gainCents: Int?
    public let gainTenths: Int?
    /// El precio más reciente de los usados (su hora de mercado si la trae).
    public let pricedAt: Date?
    /// El precio MÁS ANTIGUO de los usados.
    public let oldestPriceAt: Date?
    /// true = algún precio usado tiene más de 4 días.
    public let hasStalePrice: Bool
    public let missingPrices: Int
    public let positions: [PositionValue]
}

private func priceDate(of quote: Quote) -> Date { quote.marketTime ?? quote.fetchedAt }

private func value(of position: Position, in portfolio: Portfolio) -> PositionValue {
    var price: Decimal?
    var origin = PriceOrigin.none
    var previous: Decimal?
    let quote = portfolio.quotes[position.instrument].flatMap { $0.priceEUR > 0 ? $0 : nil }
    let manual = portfolio.manualPrices[position.instrument].flatMap { $0.priceEUR > 0 ? $0 : nil }
    if let manual, quote == nil || manual.setAt > priceDate(of: quote!) {
        price = manual.priceEUR
        origin = .manual(manual.setAt)
    } else if let quote {
        price = quote.priceEUR
        origin = .market(priceDate(of: quote))
        previous = quote.previousCloseEUR.flatMap { $0 > 0 ? $0 : nil }
    }
    guard let price, let valueCents = roundedInt(position.shares * price * 100) else {
        return PositionValue(position: position, priceEUR: nil, origin: .none, valueCents: nil, todayChangeCents: nil,
                             gainCents: nil, gainTenths: nil)
    }
    let today = previous.flatMap { roundedInt(position.shares * (price - $0) * 100) }
    // Sin coste conocido no hay ganancia que contar (no su valor entero).
    let hasCost = position.hasKnownCost
    let gain = valueCents - position.costCents
    return PositionValue(position: position, priceEUR: price, origin: origin, valueCents: valueCents, todayChangeCents: today,
                         gainCents: hasCost ? gain : nil,
                         gainTenths: hasCost ? roundedQuotient(1000 * gain, position.costCents) : nil)
}

/// Resumen de la cartera; nil si no hay posiciones abiertas. Describe, no recomienda. `now` sirve solo para saber si algún
/// precio es viejo. `calendar` (Madrid si no se da) decide el día del cambio.
public func portfolioSummary(_ portfolio: Portfolio, now: Date, calendar: Calendar? = nil) -> PortfolioSummary? {
    let values = positions(from: portfolio.transactions).map { value(of: $0, in: portfolio) }
    guard !values.isEmpty else { return nil }
    let priced = values.filter { $0.valueCents != nil }
    let totalValue = priced.reduce(0) { $0 + ($1.valueCents ?? 0) }
    let cal = calendar ?? madridCalendar
    let withToday = priced.filter { $0.todayChangeCents != nil }
    let changeDates: [Date] = withToday.compactMap {
        if case .market(let d) = $0.origin { return d }
        return nil
    }
    let changeDay = changeDates.max().map { cal.startOfDay(for: $0) }
    // U11 (J10): «hoy» suma SOLO las posiciones cuyo día de cotización de mercado (Madrid) es `changeDay`.
    let withTodayForDay = withToday.filter { pv in
        guard let changeDay, case .market(let d) = pv.origin else { return false }
        return cal.startOfDay(for: d) == changeDay
    }
    let today = withTodayForDay.reduce(0) { $0 + ($1.todayChangeCents ?? 0) }
    let valueWithToday = withTodayForDay.reduce(0) { $0 + ($1.valueCents ?? 0) }
    let withCost = priced.filter { $0.position.hasKnownCost }
    let gain = withCost.reduce(0) { $0 + ($1.valueCents ?? 0) - $1.position.costCents }
    let gainBase = withCost.reduce(0) { $0 + $1.position.costCents }
    let dates: [Date] = priced.compactMap {
        switch $0.origin {
        case .market(let d), .manual(let d): return d
        case .none: return nil
        }
    }
    return PortfolioSummary(
        valueCents: priced.isEmpty ? nil : totalValue,
        todayChangeCents: withTodayForDay.isEmpty ? nil : today,
        todayChangeTenths: withTodayForDay.isEmpty ? nil : roundedQuotient(1000 * today, valueWithToday - today),
        changeDay: changeDay,
        costCents: values.reduce(0) { $0 + $1.position.costCents },
        gainCents: withCost.isEmpty ? nil : gain,
        gainTenths: roundedQuotient(1000 * gain, gainBase), pricedAt: dates.max(), oldestPriceAt: dates.min(),
        hasStalePrice: dates.contains { now.timeIntervalSince($0) > stalePriceAge },
        missingPrices: values.count - priced.count, positions: values)
}
