import Foundation

public enum StatementError: Error, Equatable, Sendable {
    case unreadable
    case empty
    case unknownFormat
    /// Nombres en español de las columnas que faltan ("fecha", "importe", "movimiento", "estado", "divisa", "transaction_id").
    case missingColumns([String])
    case wrongBank(detected: BankID)
}

public struct StatementBalance: Equatable, Sendable {
    public let cents: Int
    public let at: Date

    public init(cents: Int, at: Date) {
        self.cents = cents
        self.at = at
    }
}

public struct ParsedStatement: Equatable, Sendable {
    public let format: StatementFormat
    public let records: [BankRecord]
    public let ignoredRows: Int
    public let latestBalance: StatementBalance?
    public let firstDate: Date?
    public let lastDate: Date?

    public init(format: StatementFormat, records: [BankRecord], ignoredRows: Int, latestBalance: StatementBalance?) {
        self.format = format
        self.records = records
        self.ignoredRows = ignoredRows
        self.latestBalance = latestBalance
        self.firstDate = records.map(\.timing.date).min()
        self.lastDate = records.map(\.timing.date).max()
    }
}

public enum StatementFormat: String, Sendable {
    case revolut, caixabank, tradeRepublic

    public var bank: BankID {
        switch self {
        case .revolut: .rev
        case .caixabank: .ima
        case .tradeRepublic: .tr
        }
    }

    /// Decide el banco por unas pocas columnas FIRMA de cada uno, no por las obligatorias: un fichero al que le falta
    /// otra columna se reconoce igual y el error nombra la que falta.
    public static func detect(_ table: CSVTable) -> StatementFormat? {
        let trSignatures = ["transaction_id", "counterparty_name", "mcc_code", "asset_class", "account_type", "datetime"]
        if trSignatures.filter({ table.column([$0]) != nil }).count >= 2 { return .tradeRepublic }

        let revolutSignatures = [
            ["started date", "fecha de inicio"], ["completed date", "fecha de finalizacion"],
            ["state", "estado"], ["product", "producto"],
        ]
        if revolutSignatures.filter({ table.column($0) != nil }).count >= 2 { return .revolut }

        if table.column(["movimiento", "concepto"]) != nil, table.column(["saldo"]) != nil || table.column(["fecha valor"]) != nil {
            return .caixabank
        }
        return nil
    }
}

/// Lee un extracto CSV del banco esperado. Orden de errores: sin filas -> `.empty`; comilla sin cerrar -> `.unreadable`; formato no reconocido ->
/// `.unknownFormat`; de otro banco -> `.wrongBank`; faltan columnas -> `.missingColumns`.
public func parseStatement(_ data: Data, expected bank: BankID, now: Date, calendar: Calendar) throws -> ParsedStatement {
    let table = try CSVTable.parse(data)
    guard !table.rows.isEmpty || table.malformedRows > 0 else { throw StatementError.empty }
    guard let format = StatementFormat.detect(table) else { throw StatementError.unknownFormat }
    guard format.bank == bank else { throw StatementError.wrongBank(detected: format.bank) }
    let parsed: ParsedStatement
    switch format {
    case .revolut: parsed = try parseRevolutStatement(table, calendar: calendar)
    case .caixabank: parsed = try parseCaixaBankStatement(table, now: now, calendar: calendar)
    case .tradeRepublic: parsed = try parseTradeRepublicStatement(table, calendar: calendar)
    }
    // Las filas con un número de celdas distinto al de la cabecera no se leyeron: cuentan como ignoradas.
    guard table.malformedRows > 0 else { return parsed }
    return ParsedStatement(format: parsed.format, records: parsed.records, ignoredRows: parsed.ignoredRows + table.malformedRows,
                           latestBalance: parsed.latestBalance)
}

// MARK: Ayudantes comunes

/// "2026-11-18 13:05:11", "2026-11-18T09:15:00Z", "2026-11-18T09:15:00.123+01:00". Sin zona: la del calendario dado.
func parseStatementTimestamp(_ raw: String, calendar: Calendar) -> Date? {
    let c = Array(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    func num(_ from: Int, _ count: Int) -> Int? {
        guard from + count <= c.count else { return nil }
        let text = String(c[from..<(from + count)])
        return text.allSatisfy({ $0.isASCII && $0.isNumber }) ? Int(text) : nil
    }
    guard c.count >= 16, c[4] == "-", c[7] == "-", c[10] == "T" || c[10] == " ", c[13] == ":",
          let y = num(0, 4), let mo = num(5, 2), let d = num(8, 2), let h = num(11, 2), let mi = num(14, 2) else { return nil }
    var i = 16
    var sec = 0
    if i < c.count, c[i] == ":" {
        guard let s = num(i + 1, 2) else { return nil }
        sec = s
        i += 3
        if i < c.count, c[i] == "." || c[i] == "," {
            i += 1
            while i < c.count, c[i].isASCII, c[i].isNumber { i += 1 }
        }
    }
    var offset: Int?
    while i < c.count, c[i] == " " { i += 1 }
    if i < c.count {
        if c[i] == "Z" || c[i] == "z" {
            offset = 0
            i += 1
        } else if c[i] == "+" || c[i] == "-" {
            let sign = c[i] == "-" ? -1 : 1
            guard let oh = num(i + 1, 2) else { return nil }
            i += 3
            if i < c.count, c[i] == ":" { i += 1 }
            let om = num(i, 2) ?? 0
            offset = sign * (oh * 3600 + om * 60)
        } else {
            return nil
        }
    }
    var cal = calendar
    if offset != nil { cal.timeZone = .gmt }
    var comps = DateComponents()
    comps.year = y; comps.month = mo; comps.day = d; comps.hour = h; comps.minute = mi; comps.second = sec
    guard let date = cal.date(from: comps) else { return nil }
    let back = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    guard back.year == y, back.month == mo, back.day == d, back.hour == h, back.minute == mi, back.second == sec else { return nil }
    return offset.map { date.addingTimeInterval(-TimeInterval($0)) } ?? date
}

/// Texto de una fila para su clave: sin mayúsculas ni tildes y con los espacios colapsados, para que dos exportaciones
/// de la misma fila con otro formato de espacios o mayúsculas den la misma clave.
func normalizedStatementText(_ s: String) -> String {
    s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        .split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
}

/// Cuenta repeticiones para que dos filas idénticas del mismo fichero tengan claves distintas y estables.
struct OccurrenceCounter {
    private var seen: [String: Int] = [:]
    mutating func next(_ key: String) -> Int {
        let n = seen[key, default: 0]
        seen[key] = n + 1
        return n
    }
}
