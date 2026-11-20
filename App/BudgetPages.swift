import Foundation
import MiBancoCore

/// Cabecera de la pantalla de una categoría en un mes, ya redactada.
struct CategoryHeader: Equatable, Sendable {
    let cents: Int
    /// "-30 % frente a octubre" (mes pasado) o "+77 % frente a octubre a estas alturas" (mes en curso); nil sin gasto
    /// previo en la categoría.
    let comparison: String?
}

/// Las filas finales de la pestaña Gasto: su texto de apoyo ya redactado.
struct SpendingLinkTexts: Equatable, Sendable {
    /// "Del mes y 2 categorías", "Sin presupuestos".
    var budgets = "Sin presupuestos"
    /// "2 · no cuentan"; nil si no hay traspasos (la fila se oculta).
    var transfers: String?
    /// "2 · 24,98 € al mes"; "Ninguna todavía".
    var subscriptions = "Ninguna todavía"
}

/// Todo lo que añaden las pantallas de presupuestos y categorías al snapshot.
struct BudgetExtras: Sendable {
    var budgets: [BudgetStatus] = []
    var suggestions: [String: Int] = [:]
    var categoryEntries: [String: [ListEntry]] = [:]
    var categoryHeaders: [String: CategoryHeader] = [:]
    var transferEntries: [ListEntry] = []
    var links = SpendingLinkTexts()
}

extension LedgerSnapshot {
    /// Tope de movimientos que lista la pantalla de traspasos.
    static let maxTransferRows = 200

    /// Clave de `categoryEntries` y `categoryHeaders`: "<año>-<mes>|<categoría>".
    static func categoryKey(month: Date, category: SpendingCategory, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: month)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)|\(category.rawValue)"
    }

    /// Presupuestos, medias, movimientos por categoría y mes, y traspasos: de una sola vez al reconstruir el snapshot.
    /// Lo que no es gasto (`notSpending`, el conjunto completo de `spendingExclusions`), los traspasos solos (`transfers`,
    /// solo para su lista y su cuenta) y las claves de suscripción llegan calculados; los movimientos se recorren una vez.
    static func budgetExtras(state: LedgerState, now: Date, calendar: Calendar, notSpending: Set<UUID>, transfers: Set<UUID>,
                             subscriptions: [Subscription], months: [Date], pages: [Date: SpendingPage]) -> BudgetExtras {
        var out = BudgetExtras()
        let keys = Set(subscriptions.map(\.id))
        let currentStart = months.last ?? now

        out.budgets = budgetStatuses(in: state, month: currentStart, now: now, calendar: calendar,
                                     notSpending: notSpending, subscriptionKeys: keys)

        // Media de los tres meses anteriores: total y categorías en una sola pasada.
        if let average = averageMonthlySpendingByCategory(in: state, before: currentStart, months: 3, calendar: calendar,
                                                          notSpending: notSpending, subscriptionKeys: keys) {
            if average.total > 0 { out.suggestions["month"] = average.total }
            for (category, cents) in average.byCategory where cents > 0 && category != .sinCategoria {
                out.suggestions["cat-\(category.rawValue)"] = cents
            }
        }

        // Pagos por categoría y mes, en una pasada.
        let monthSet = Set(months)
        var grouped: [String: [Movement]] = [:]
        for m in spendingMovements(in: state.movements, notSpending: notSpending) {
            guard let start = calendar.dateInterval(of: .month, for: m.date)?.start, monthSet.contains(start) else { continue }
            if start == currentStart && m.date > now { continue }
            let category = categoryOf(m, in: state, subscriptionKeys: keys) ?? .sinCategoria
            grouped[categoryKey(month: start, category: category, calendar: calendar), default: []].append(m)
        }
        let monthName = { (date: Date) in date.formatted(Date.FormatStyle(locale: spanish).month(.wide)) }
        for start in months {
            guard let page = pages[start] else { continue }
            // Mes en curso: se compara con el mismo punto del mes anterior, y la frase lo dice («… a estas alturas»).
            let previousName = (calendar.date(byAdding: .month, value: -1, to: start).map(monthName) ?? "")
                + (start == currentStart ? " a estas alturas" : "")
            for row in page.rows {
                let key = categoryKey(month: start, category: row.category, calendar: calendar)
                let sorted = (grouped[key] ?? []).sorted {
                    $0.date != $1.date ? $0.date > $1.date : $0.id.uuidString > $1.id.uuidString
                }
                out.categoryEntries[key] = ListEntry.flatten(
                    sections(for: sorted.map { LedgerItem.movement($0) }, showsBank: true, now: now, calendar: calendar,
                             ownTransfers: transfers),
                    prefix: "cat-\(key)")
                out.categoryHeaders[key] = CategoryHeader(
                    cents: row.cents, comparison: row.change.map { "\($0) frente a \(previousName)" })
            }
        }

        // Traspasos entre tus cuentas: los más recientes primero.
        let moved = state.movements.filter { transfers.contains($0.id) }.sorted { $0.date > $1.date }
        out.transferEntries = ListEntry.flatten(
            sections(for: moved.prefix(maxTransferRows).map { LedgerItem.movement($0) }, showsBank: true, now: now, calendar: calendar,
                     ownTransfers: transfers),
            prefix: "tr")

        out.links.budgets = budgetsSummary(state.budgets)
        if !moved.isEmpty { out.links.transfers = "\(moved.count) · no cuentan" }
        return out
    }

    private static func budgetsSummary(_ budgets: Budgets) -> String {
        let month = (budgets.monthlyCents ?? 0) > 0
        let count = budgets.byCategory.values.filter { $0 > 0 }.count
        let categories = count == 1 ? "1 categoría" : "\(count) categorías"
        switch (month, count) {
        case (false, 0): return "Sin presupuestos"
        case (true, 0): return "Del mes"
        case (false, _): return categories
        case (true, _): return "Del mes y \(categories)"
        }
    }
}
