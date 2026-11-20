import Foundation

/// Una tabla CSV leída tal cual: cabeceras y filas de texto. Las columnas se buscan por nombre (con alias), nunca por
/// posición, y las desconocidas se ignoran: ningún formato de banco está confirmado con un fichero real.
public struct CSVTable: Equatable, Sendable {
    public let headers: [String]
    public let rows: [[String]]

    public init(headers: [String], rows: [[String]]) {
        self.headers = headers
        self.rows = rows
    }

    /// UTF-8 (sin BOM) o, si no lo es, Windows-1252; UTF-16 con BOM también. El separador es el más frecuente de la
    /// cabecera (`,`, `;` o tabulador) fuera de comillas. Comillas RFC 4180 (`""`), `\r\n` o `\n`, líneas en blanco fuera.
    /// Sin cabecera -> `.empty`.
    public static func parse(_ data: Data) throws -> CSVTable {
        guard let text = decodeCSVText(data) else { throw StatementError.unreadable }
        let scalars = Array(text.unicodeScalars)
        let delimiter = detectDelimiter(scalars)
        let records = splitRecords(scalars, delimiter: delimiter)
        guard let header = records.first else { throw StatementError.empty }
        return CSVTable(headers: header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }, rows: Array(records.dropFirst()))
    }

    /// Índice de la primera columna cuyo nombre normalizado coincide con algún alias (se prueban en orden).
    public func column(_ aliases: [String]) -> Int? {
        let names = headers.map(normalizeHeader)
        for alias in aliases {
            let wanted = normalizeHeader(alias)
            if let i = names.firstIndex(of: wanted) { return i }
        }
        return nil
    }
}

/// Minúsculas, sin tildes, recortado, espacios interiores colapsados y `_` como espacio.
public func normalizeHeader(_ s: String) -> String {
    let cleaned = s.replacingOccurrences(of: "\u{FEFF}", with: "").replacingOccurrences(of: "_", with: " ")
    let folded = cleaned.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    return folded.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

/// Importe con signo en formato europeo o con punto ("-23,45", "1.250,00", "+5,00", "7", "12.50", "23,45-") -> céntimos.
public func parseSignedEuropeanAmount(_ raw: String) -> Int? {
    var s = raw.replacingOccurrences(of: "\u{2212}", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
    var negative = false
    if s.hasPrefix("-") {
        negative = true
        s.removeFirst()
    } else if s.hasPrefix("+") {
        s.removeFirst()
    } else if s.hasSuffix("-") {
        negative = true
        s.removeLast()
    }
    guard let cents = parseAmountToCents(Substring(s)) else { return nil }
    return negative ? -cents : cents
}

/// Importe de un extracto con punto decimal (Revolut, Trade Republic); si trae coma se lee como europeo.
func parseStatementDecimal(_ raw: String) -> Int? {
    let s = raw.replacingOccurrences(of: "\u{2212}", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !s.isEmpty else { return nil }
    if s.contains(",") { return parseSignedEuropeanAmount(s) }
    return centsFromDecimalString(s)
}

extension Array where Element == String {
    /// Celda recortada de la columna, o "" si no hay columna o la fila es más corta.
    func cell(_ column: Int?) -> String {
        guard let column, column < count else { return "" }
        return self[column].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: Decodificación

private let windows1252High: [UInt32] = [
    0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
    0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178,
]

private func decodeCSVText(_ data: Data) -> String? {
    let bytes = [UInt8](data)
    if bytes.starts(with: [0xFF, 0xFE]) { return String(data: Data(bytes.dropFirst(2)), encoding: .utf16LittleEndian) }
    if bytes.starts(with: [0xFE, 0xFF]) { return String(data: Data(bytes.dropFirst(2)), encoding: .utf16BigEndian) }
    let body = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? Array(bytes.dropFirst(3)) : bytes
    if let utf8 = String(data: Data(body), encoding: .utf8) { return utf8 }
    // Windows-1252 a mano: idéntico en Linux e iOS.
    var scalars = String.UnicodeScalarView()
    for b in body {
        let value: UInt32 = (b >= 0x80 && b <= 0x9F) ? windows1252High[Int(b) - 0x80] : UInt32(b)
        if let scalar = Unicode.Scalar(value) { scalars.append(scalar) }
    }
    return String(scalars)
}

private func detectDelimiter(_ scalars: [Unicode.Scalar]) -> Unicode.Scalar {
    var counts: [Unicode.Scalar: Int] = [",": 0, ";": 0, "\t": 0]
    var inQuotes = false
    for s in scalars {
        if s == "\"" { inQuotes.toggle(); continue }
        if inQuotes { continue }
        if s == "\n" || s == "\r" {
            // La primera línea no vacía es la cabecera.
            if counts.values.reduce(0, +) > 0 { break }
            continue
        }
        if counts[s] != nil { counts[s]! += 1 }
    }
    var best: Unicode.Scalar = ","
    for candidate in [",", ";", "\t"] as [Unicode.Scalar] where counts[candidate]! > counts[best]! { best = candidate }
    return best
}

private func splitRecords(_ scalars: [Unicode.Scalar], delimiter: Unicode.Scalar) -> [[String]] {
    var records: [[String]] = []
    var row: [String] = []
    var field = String.UnicodeScalarView()
    var inQuotes = false
    var quoted = false
    var blankWasQuoted = false

    func endField() {
        row.append(String(field))
        field = String.UnicodeScalarView()
        quoted = false
    }
    func endRecord() {
        endField()
        // Línea en blanco: un solo campo vacío sin comillas.
        if !(row.count == 1 && row[0].isEmpty && !blankWasQuoted) { records.append(row) }
        row = []
        blankWasQuoted = false
    }
    var i = 0
    while i < scalars.count {
        let s = scalars[i]
        if inQuotes {
            if s == "\"" {
                if i + 1 < scalars.count, scalars[i + 1] == "\"" {
                    field.append("\"")
                    i += 1
                } else {
                    inQuotes = false
                }
            } else {
                field.append(s)
            }
        } else if s == "\"" && field.isEmpty && !quoted {
            inQuotes = true
            quoted = true
            blankWasQuoted = true
        } else if s == delimiter {
            endField()
        } else if s == "\n" || s == "\r" {
            if s == "\r", i + 1 < scalars.count, scalars[i + 1] == "\n" { i += 1 }
            endRecord()
        } else {
            field.append(s)
        }
        i += 1
    }
    if !field.isEmpty || !row.isEmpty || quoted { endRecord() }
    return records
}
