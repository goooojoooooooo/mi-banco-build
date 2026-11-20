import Foundation
import MiBancoCore

/// Una fila de categoría de la pestaña Gasto.
struct CategoryRowModel: Equatable, Sendable, Identifiable {
    let category: SpendingCategory
    let cents: Int
    /// Frente a la categoría mayor del mes (la mayor llena la barra).
    let fraction: Double
    /// Dónde quedó el mes anterior (mismo punto del mes si se mira el actual), en la misma escala. nil sin gasto previo.
    let previousFraction: Double?
    /// "+12 %" / "-30 %"; nil si el mes anterior no tuvo gasto en la categoría.
    let change: String?
    /// "12 % más que el mes pasado": lo que lee VoiceOver; nil sin comparación.
    let spokenChange: String?
    var id: SpendingCategory { category }
}

/// Un mes de la pestaña Gasto con todos sus textos ya redactados.
struct SpendingPage: Equatable, Sendable {
    let month: MonthSpending
    /// "Noviembre"; "Octubre 2025" si no es este año.
    let title: String
    let comparison: String?
    let forecast: String?
    let rows: [CategoryRowModel]
}

extension LedgerSnapshot {
    /// Como mucho, los meses que enseña el selector (el actual y los 12 anteriores).
    static let maxSpendingMonths = 13

    /// Las páginas de Gasto, de una sola vez. El emparejado de traspasos y las claves de suscripción llegan ya
    /// calculados: ninguna suma de Core los recalcula por mes ni por categoría.
    static func spendingPages(state: LedgerState, now: Date, calendar: Calendar, transfers: Set<UUID>,
                              pace: SpendingPace?) -> (months: [Date], pages: [Date: SpendingPage]) {
        let currentStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
        var months = [currentStart]
        if let first = state.movements.map(\.date).min(),
           let firstStart = calendar.dateInterval(of: .month, for: first)?.start {
            var cursor = currentStart
            while months.count < maxSpendingMonths, cursor > firstStart,
                  let earlier = calendar.date(byAdding: .month, value: -1, to: cursor) {
                months.insert(earlier, at: 0)
                cursor = earlier
            }
        }

        let subscriptions = activeSubscriptions(in: state, now: now, calendar: calendar, ownTransferIDs: transfers)
        let keys = Set(subscriptions.map(\.id))
        let forecast = monthForecast(in: state, now: now, calendar: calendar, ownTransferIDs: transfers, subscriptions: subscriptions)
        let spanish = Locale(identifier: "es_ES")
        let monthName = { (date: Date) in date.formatted(Date.FormatStyle(locale: spanish).month(.wide)) }
        let year = calendar.component(.year, from: now)

        var pages: [Date: SpendingPage] = [:]
        for start in months {
            let month = monthSpending(in: state, month: start, now: now, calendar: calendar,
                                      ownTransferIDs: transfers, subscriptionKeys: keys)
            let isCurrent = start == currentStart
            let previousName = calendar.date(byAdding: .month, value: -1, to: start).map(monthName) ?? ""

            var title = monthName(start)
            title = title.prefix(1).uppercased() + title.dropFirst()
            if calendar.component(.year, from: start) != year { title += " \(calendar.component(.year, from: start))" }

            var comparison: String?
            var forecastText: String?
            if isCurrent {
                if let pace {
                    comparison = phrase(difference: pace.differenceCents, previous: "\(previousName) a estas alturas")
                }
                if let forecast {
                    forecastText = "A este ritmo terminarás el mes en unos \(formatEURWhole(forecast.projectedCents))"
                } else {
                    forecastText = "Aún es pronto para saber cómo acabarás el mes"
                }
            } else if month.previousTotalCents > 0 {
                comparison = phrase(difference: month.totalCents - month.previousTotalCents, previous: previousName)
            }

            let biggest = Double(month.byCategory.map(\.cents).max() ?? 1)
            let rows = month.byCategory.map { spend -> CategoryRowModel in
                let percent = changePercent(from: spend.previousCents, to: spend.cents)
                return CategoryRowModel(
                    category: spend.category, cents: spend.cents,
                    fraction: min(1, Double(spend.cents) / max(biggest, 1)),
                    previousFraction: spend.previousCents > 0 ? min(1, Double(spend.previousCents) / max(biggest, 1)) : nil,
                    change: percent.map(formatSignedPercent),
                    spokenChange: percent.map { spoken(percent: $0, current: isCurrent) })
            }
            pages[start] = SpendingPage(month: month, title: title, comparison: comparison, forecast: forecastText, rows: rows)
        }
        return (months, pages)
    }

    /// "78,40 € menos que en octubre", "Igual que en octubre".
    private static func phrase(difference: Int, previous: String) -> String {
        if difference == 0 { return "Igual que en \(previous)" }
        return "\(formatEUR(abs(difference))) \(difference < 0 ? "menos" : "más") que en \(previous)"
    }

    /// "12 % más que el mes pasado".
    private static func spoken(percent: Int, current: Bool) -> String {
        let reference = current ? "el mes pasado" : "el mes anterior"
        if percent == 0 { return "igual que \(reference)" }
        return "\(abs(percent)) % \(percent > 0 ? "más" : "menos") que \(reference)"
    }
}
