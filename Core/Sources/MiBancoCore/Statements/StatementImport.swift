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
        report.addsPeriod = recordStatementCoverage(statement, bank: bank, now: now)
        if let balance = statement.latestBalance {
            let existing = state.balances[bank]
            let isSameStatement = existing.map { $0.origin == .statement && $0.setAt == balance.at && $0.cents == balance.cents } ?? false
            if existing.map({ balance.at >= $0.setAt }) ?? true, !isSameStatement {
                adoptBalance(bank, cents: balance.cents, at: balance.at, origin: .statement)
                report.adoptsBalance = true
            }
        }
        return report
    }

    /// Guarda el periodo que cubre este extracto: desde el día de su primera fila hasta el final de su último día, pero
    /// nunca el día en que se importó ni los siguientes (ese día aún puede haber pagos que el extracto no trae). Las
    /// filas de un día sin cerrar no cubren nada más allá. Devuelve true si añade un periodo nuevo.
    @discardableResult
    private mutating func recordStatementCoverage(_ statement: ParsedStatement, bank: BankID, now: Date) -> Bool {
        guard let first = statement.firstDate, let last = statement.lastDate else { return false }
        let start = madridCalendar.startOfDay(for: first)
        let afterLast = madridCalendar.date(byAdding: .day, value: 1, to: madridCalendar.startOfDay(for: last)) ?? last
        let end = min(afterLast, madridCalendar.startOfDay(for: now))
        guard end > start else { return false }
        let interval = DateInterval(start: start, end: end)
        if state.statementCoverage[bank]?.contains(interval) != true {
            state.statementCoverage[bank, default: []].append(interval)
            return true
        }
        return false
    }
}

/// "14 movimientos nuevos, 6 operaciones de inversión nuevas, 40 ya estaban, 2 filas ignoradas" (U46).
public func importSummary(_ report: ReconcileReport) -> String {
    let regularAdded = max(0, report.added - report.addedInvestments)
    var parts = [regularAdded == 1 ? "1 movimiento nuevo" : "\(regularAdded) movimientos nuevos"]
    if report.addedInvestments > 0 {
        parts.append(report.addedInvestments == 1 ? "1 operación de inversión nueva"
                     : "\(report.addedInvestments) operaciones de inversión nuevas")
    }
    let already = report.alreadyThere
    if already > 0 { parts.append(already == 1 ? "1 ya estaba" : "\(already) ya estaban") }
    if report.ignoredRows > 0 { parts.append(report.ignoredRows == 1 ? "1 fila ignorada" : "\(report.ignoredRows) filas ignoradas") }
    return parts.joined(separator: ", ")
}

/// Nota cuando un extracto no trae movimientos nuevos ni enlazados (U47).
public func statementZeroNewNote(_ report: ReconcileReport) -> String {
    switch (report.addsPeriod, report.adoptsBalance) {
    case (true, true):
        return "Los movimientos ya estaban, pero al importar se actualiza el periodo cubierto y el saldo del extracto."
    case (true, false):
        return "Los movimientos ya estaban, pero al importar se actualiza el periodo cubierto."
    case (false, true):
        return "Los movimientos ya estaban, pero al importar se actualiza el saldo con el del extracto."
    case (false, false):
        return "Nada nuevo que importar: todo esto ya estaba."
    }
}

/// Texto del periodo de la vista previa del extracto (U51: incluye el año cuando hace falta).
public func statementRangeText(first: Date, last: Date, now: Date, calendar: Calendar) -> String {
    let firstYear = calendar.component(.year, from: first)
    let lastYear = calendar.component(.year, from: last)
    let nowYear = calendar.component(.year, from: now)
    let showYear = firstYear != lastYear || firstYear != nowYear
    return "Del \(shortSpanishDate(first, calendar: calendar, withYear: showYear)) al \(shortSpanishDate(last, calendar: calendar, withYear: showYear))"
}
