import Foundation

/// Copia de seguridad completa del libro (ver spec de los planes 3 y 4, §2.6).
public struct BackupFile: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var app: String
    public var version: Int
    public var exportedAt: Date
    public var ledger: LedgerState

    public init(app: String = "MiBanco", version: Int = BackupFile.currentVersion, exportedAt: Date, ledger: LedgerState) {
        self.app = app
        self.version = version
        self.exportedAt = exportedAt
        self.ledger = ledger
    }
}

public enum BackupError: Error, Equatable, Sendable {
    /// El fichero no es una copia de Mi Banco (otro JSON, texto cualquiera...).
    case notABackup
    /// La copia viene de una versión más nueva de la app: no se toca nada.
    case newerVersion(Int)
}

/// JSON con claves ordenadas; fechas con la estrategia por defecto para que la ida y vuelta sea exacta.
public func encodeBackup(_ state: LedgerState, exportedAt: Date) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    return try encoder.encode(BackupFile(exportedAt: exportedAt, ledger: state))
}

private struct BackupHeader: Decodable {
    let app: String
    let version: Int
}

/// Decodifica primero solo `{app, version}`: así una copia de una versión futura (con otra forma) se rechaza por versión
/// y un fichero ajeno por `notABackup`, siempre antes de tocar nada.
public func decodeBackup(_ data: Data) throws -> BackupFile {
    guard let header = try? JSONDecoder().decode(BackupHeader.self, from: data), header.app == "MiBanco" else {
        throw BackupError.notABackup
    }
    if header.version > BackupFile.currentVersion { throw BackupError.newerVersion(header.version) }
    guard let file = try? JSONDecoder().decode(BackupFile.self, from: data) else { throw BackupError.notABackup }
    return file
}

private func datePart(_ date: Date, calendar: Calendar) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
}

public func backupFileName(exportedAt: Date, calendar: Calendar) -> String {
    "MiBanco-\(datePart(exportedAt, calendar: calendar)).json"
}

public func movementsCSVFileName(exportedAt: Date, calendar: Calendar) -> String {
    "MiBanco-movimientos-\(datePart(exportedAt, calendar: calendar)).csv"
}

/// Hora del movimiento para el CSV. Vacía cuando el movimiento no tiene hora real (R13): filas del banco de solo día.
private func csvTime(of movement: Movement, calendar: Calendar) -> String {
    if movement.dayOnly { return "" }
    let c = calendar.dateComponents([.hour, .minute], from: movement.date)
    return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
}

/// Importe en euros con coma decimal y sin separador de miles ("-12,50").
private func csvAmount(_ cents: Int) -> String {
    let rest = cents.magnitude % 100
    return "\(cents < 0 ? "-" : "")\(cents.magnitude / 100),\(rest < 10 ? "0" : "")\(rest)"
}

private func csvField(_ value: String) -> String {
    guard value.contains(where: { $0 == ";" || $0 == "\"" || $0 == "\r" || $0 == "\n" }) else { return value }
    return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}

/// Texto libre (comercio, nota, categoría, banco) que un banco o un tercero puede haber escrito: si empieza por `=`, `+`, `-`,
/// `@`, tabulador o retorno de carro, una hoja de cálculo lo evaluaría como fórmula. Se neutraliza con un apóstrofo delante.
/// Solo para columnas de texto: el importe no pasa por aquí (un `-12,50` legítimo debe seguir siendo numérico).
func csvText(_ value: String) -> String {
    guard let first = value.unicodeScalars.first, "=+-@\t\r".unicodeScalars.contains(first) else { return value }
    return "'" + value
}

/// Todos los movimientos, por fecha ascendente, separados por `;` (Excel en español), con fin de línea CRLF.
public func movementsCSV(_ state: LedgerState, now: Date, calendar: Calendar) -> String {
    let transfers = ownTransferIDs(in: state.movements)
    // La categoría de un pago de suscripción sale de las suscripciones detectadas, que van sobre el gasto real: el
    // conjunto completo (traspasos, sin confirmar, pareja probable), una vez.
    let keys = subscriptionKeys(in: state, now: now, calendar: calendar, notSpending: spendingExclusions(in: state, now: now))
    var lines = ["Fecha;Hora;Banco;Tipo;Comercio;Categoría;Importe;Nota;No es mío;Traspaso propio"]
    let sorted = state.movements.sorted { $0.date != $1.date ? $0.date < $1.date : $0.id.uuidString < $1.id.uuidString }
    for m in sorted {
        let category = categoryOf(m, in: state, subscriptionKeys: keys)?.displayName ?? ""
        let fields = [
            datePart(m.date, calendar: calendar),
            csvTime(of: m, calendar: calendar),
            csvText(m.bank.displayName),
            m.kind == .payment ? "Pago" : "Ingreso",
            csvText(m.merchant ?? ""),
            csvText(category),
            csvAmount(m.amountCents),
            csvText(m.note ?? ""),
            m.flaggedNotMine ? "sí" : "",
            transfers.contains(m.id) ? "sí" : "",
        ]
        lines.append(fields.map(csvField).joined(separator: ";"))
    }
    return lines.joined(separator: "\r\n") + "\r\n"
}

/// El mismo CSV con la marca de orden de bytes UTF-8 delante, para que Excel respete las tildes.
public func movementsCSVData(_ state: LedgerState, now: Date, calendar: Calendar) -> Data {
    Data([0xEF, 0xBB, 0xBF]) + Data(movementsCSV(state, now: now, calendar: calendar).utf8)
}
