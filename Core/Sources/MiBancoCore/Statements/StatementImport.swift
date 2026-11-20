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
        if let balance = statement.latestBalance, state.balances[bank].map({ balance.at >= $0.setAt }) ?? true {
            adoptBalance(bank, cents: balance.cents, at: balance.at, origin: .statement)
        }
        return report
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
