import Foundation

/// Lo mismo que `averageMonthlySpending` (mismos meses, mismas reglas), pero el total y todas las categorías de una sola
/// pasada por los movimientos: la pantalla de presupuestos pide las medias de todas las categorías al reconstruir el
/// snapshot y no debe recorrer el libro una vez por categoría. nil si no hay ningún mes completo que promediar.
public func averageMonthlySpendingByCategory(in state: LedgerState, before month: Date, months: Int, calendar: Calendar,
                                             ownTransferIDs ownTransfers: Set<UUID>? = nil,
                                             subscriptionKeys keys: Set<String>? = nil)
    -> (total: Int, byCategory: [SpendingCategory: Int])? {
    guard months > 0, let first = state.movements.map(\.date).min(),
          let firstMonth = calendar.dateInterval(of: .month, for: first)?.start,
          let monthStart = calendar.dateInterval(of: .month, for: month)?.start,
          let earliest = calendar.date(byAdding: .month, value: -months, to: monthStart) else { return nil }
    let from = max(earliest, firstMonth)
    guard from < monthStart,
          let count = calendar.dateComponents([.month], from: from, to: monthStart).month, count > 0 else { return nil }
    let transfers = ownTransfers ?? ownTransferIDs(in: state.movements)
    let subKeys = keys ?? subscriptionKeys(in: state, now: monthStart, calendar: calendar, ownTransferIDs: transfers)
    var total = 0
    var sums: [SpendingCategory: Int] = [:]
    for m in spendingMovements(in: state.movements, excluding: transfers) where m.date >= from && m.date < monthStart {
        let amount = abs(m.amountCents)
        total += amount
        sums[categoryOf(m, in: state, subscriptionKeys: subKeys) ?? .sinCategoria, default: 0] += amount
    }
    return (total / count, sums.mapValues { $0 / count })
}
