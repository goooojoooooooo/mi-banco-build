import Foundation

extension Ledger {
    /// Lo que pasaría al importar, sin tocar el libro.
    public func previewImport(_ statement: ParsedStatement, now: Date, calendar: Calendar) -> ReconcileReport {
        var copy = self
        return copy.importStatement(statement, now: now, calendar: calendar)
    }

    /// Concilia las filas del extracto (sin duplicar lo que ya hay, de la API o capturado) y adopta su último saldo,
    /// salvo que la lectura de saldo que ya hay (de cualquier origen, también la puesta a mano) sea más reciente: importar
    /// el extracto de un periodo pasado no debe pisar el saldo de hoy.
    @discardableResult
    public mutating func importStatement(_ statement: ParsedStatement, now: Date, calendar: Calendar) -> ReconcileReport {
        let bank = statement.format.bank
        var report = reconcile(statement.records, bank: bank, channel: .statement, coverage: nil, now: now, calendar: calendar)
        report.ignoredRows = statement.ignoredRows
        recordStatementCoverage(statement, bank: bank, now: now)
        if let balance = statement.latestBalance, state.balances[bank].map({ balance.at >= $0.setAt }) ?? true {
            adoptBalance(bank, cents: balance.cents, at: balance.at, origin: .statement)
        }
        return report
    }

    /// Guarda el periodo que cubre este extracto: desde el día de su primera fila hasta el final de su último día, pero
    /// nunca el día en que se importó ni los siguientes (ese día aún puede haber pagos que el extracto no trae). Las
    /// filas de un día sin cerrar no cubren nada más allá.
    private mutating func recordStatementCoverage(_ statement: ParsedStatement, bank: BankID, now: Date) {
        guard let first = statement.firstDate, let last = statement.lastDate else { return }
        let start = madridCalendar.startOfDay(for: first)
        let afterLast = madridCalendar.date(byAdding: .day, value: 1, to: madridCalendar.startOfDay(for: last)) ?? last
        let end = min(afterLast, madridCalendar.startOfDay(for: now))
        guard end > start else { return }
        let interval = DateInterval(start: start, end: end)
        if state.statementCoverage[bank]?.contains(interval) != true {
            state.statementCoverage[bank, default: []].append(interval)
        }
    }
}

/// "123 movimientos nuevos, 40 ya estaban, 2 filas ignoradas" (las partes en 0 salvo las nuevas se omiten).
public func importSummary(_ report: ReconcileReport) -> String {
    var parts = [report.added == 1 ? "1 movimiento nuevo" : "\(report.added) movimientos nuevos"]
    let already = report.alreadyThere
    if already > 0 { parts.append(already == 1 ? "1 ya estaba" : "\(already) ya estaban") }
    if report.ignoredRows > 0 { parts.append(report.ignoredRows == 1 ? "1 fila ignorada" : "\(report.ignoredRows) filas ignoradas") }
    return parts.joined(separator: ", ")
}

/// Nota cuando un extracto no trae movimientos nuevos ni enlazados (U47).
public func statementZeroNewNote(_ report: ReconcileReport) -> String {
    // Stub temporal para prueba roja U47 (comportamiento antiguo).
    "Los movimientos ya estaban, pero al importar se actualiza el periodo cubierto y el saldo del extracto."
}

/// Texto del periodo de la vista previa del extracto (U51: incluye el año cuando hace falta).
public func statementRangeText(first: Date, last: Date, now: Date, calendar: Calendar) -> String {
    // Stub temporal para prueba roja U51 (comportamiento antiguo: withYear siempre false).
    "Del \(shortSpanishDate(first, calendar: calendar, withYear: false)) al \(shortSpanishDate(last, calendar: calendar, withYear: false))"
}
