import Foundation

public struct CategorySpend: Equatable, Sendable, Identifiable {
    public let category: SpendingCategory
    public let cents: Int
    /// Lo gastado en la misma categoría el mes anterior (hasta el mismo punto del mes si se mira el mes en curso).
    public let previousCents: Int
    public let count: Int
    public var id: SpendingCategory { category }

    public init(category: SpendingCategory, cents: Int, previousCents: Int, count: Int) {
        self.category = category
        self.cents = cents
        self.previousCents = previousCents
        self.count = count
    }
}

public struct MonthSpending: Equatable, Sendable {
    public let monthStart: Date
    public let totalCents: Int
    public let previousTotalCents: Int
    public let byCategory: [CategorySpend]

    public init(monthStart: Date, totalCents: Int, previousTotalCents: Int, byCategory: [CategorySpend]) {
        self.monthStart = monthStart
        self.totalCents = totalCents
        self.previousTotalCents = previousTotalCents
        self.byCategory = byCategory
    }
}

public struct MonthForecast: Equatable, Sendable {
    public let spentCents: Int
    public let projectedCents: Int
    public let pendingSubscriptionsCents: Int

    public init(spentCents: Int, projectedCents: Int, pendingSubscriptionsCents: Int) {
        self.spentCents = spentCents
        self.projectedCents = projectedCents
        self.pendingSubscriptionsCents = pendingSubscriptionsCents
    }
}

/// Claves (comercio normalizado) de las suscripciones detectadas. Quien suma varios meses la calcula una vez y la pasa.
public func subscriptionKeys(in state: LedgerState, now: Date, calendar: Calendar,
                             ownTransferIDs: Set<UUID>? = nil) -> Set<String> {
    Set(detectSubscriptions(in: state.movements, now: now, calendar: calendar, ownTransferIDs: ownTransferIDs).map(\.id))
}

/// Categoría de un pago con las categorías recordadas del libro; nil para ingresos.
public func categoryOf(_ movement: Movement, in state: LedgerState, subscriptionKeys: Set<String>) -> SpendingCategory? {
    spendingCategory(of: movement, overrides: state.categoryOverrides, subscriptionKeys: subscriptionKeys)
}

/// Tramo de tiempo de un mes: el mes en curso llega hasta `now` (incluido); un mes pasado, entero.
private struct MonthWindow {
    let start: Date
    let upper: Date
    let upperInclusive: Bool

    func contains(_ date: Date) -> Bool {
        date >= start && (upperInclusive ? date <= upper : date < upper)
    }
}

/// El mes pedido y el anterior. Si el mes pedido es el actual, el anterior llega solo hasta el mismo día y hora
/// (el día se ajusta a la longitud de ese mes, como `spendingPace`); si no, se comparan meses enteros.
private func monthWindows(month: Date, now: Date, calendar: Calendar) -> (current: MonthWindow, previous: MonthWindow)? {
    guard let interval = calendar.dateInterval(of: .month, for: month),
          let prevStart = calendar.date(byAdding: .month, value: -1, to: interval.start),
          let prevDays = calendar.range(of: .day, in: .month, for: prevStart) else { return nil }
    let current = now < interval.end
        ? MonthWindow(start: interval.start, upper: now, upperInclusive: true)
        : MonthWindow(start: interval.start, upper: interval.end, upperInclusive: false)
    var previous = MonthWindow(start: prevStart, upper: interval.start, upperInclusive: false)
    if now >= interval.start && now < interval.end {
        let clock = calendar.dateComponents([.day, .hour, .minute, .second], from: now)
        var parts = calendar.dateComponents([.year, .month], from: prevStart)
        parts.day = min(clock.day ?? 1, prevDays.count)
        parts.hour = clock.hour
        parts.minute = clock.minute
        parts.second = clock.second
        if let cutoff = calendar.date(from: parts) {
            previous = MonthWindow(start: prevStart, upper: cutoff, upperInclusive: true)
        }
    }
    return (current, previous)
}

/// Gasto de un mes por categoría frente al mes anterior. Para el mes en curso, la comparación llega al mismo punto del mes.
/// Quien lo llama para varios meses calcula `ownTransferIDs(in:)` y `subscriptionKeys(...)` una vez y los pasa.
public func monthSpending(in state: LedgerState, month: Date, now: Date, calendar: Calendar,
                          ownTransferIDs ownTransfers: Set<UUID>? = nil,
                          subscriptionKeys keys: Set<String>? = nil) -> MonthSpending {
    guard let windows = monthWindows(month: month, now: now, calendar: calendar) else {
        return MonthSpending(monthStart: month, totalCents: 0, previousTotalCents: 0, byCategory: [])
    }
    let transfers = ownTransfers ?? ownTransferIDs(in: state.movements)
    let subKeys = keys ?? subscriptionKeys(in: state, now: now, calendar: calendar, ownTransferIDs: transfers)
    var cents: [SpendingCategory: Int] = [:]
    var counts: [SpendingCategory: Int] = [:]
    var previous: [SpendingCategory: Int] = [:]
    var total = 0
    var previousTotal = 0
    for m in spendingMovements(in: state.movements, excluding: transfers) {
        let inCurrent = windows.current.contains(m.date)
        guard inCurrent || windows.previous.contains(m.date) else { continue }
        let category = categoryOf(m, in: state, subscriptionKeys: subKeys) ?? .sinCategoria
        let amount = abs(m.amountCents)
        if inCurrent {
            cents[category, default: 0] += amount
            counts[category, default: 0] += 1
            total += amount
        } else {
            previous[category, default: 0] += amount
            previousTotal += amount
        }
    }
    let order = Dictionary(uniqueKeysWithValues: SpendingCategory.allCases.enumerated().map { ($1, $0) })
    let rows = counts.keys.sorted { a, b in
        let ca = cents[a] ?? 0, cb = cents[b] ?? 0
        return ca != cb ? ca > cb : (order[a] ?? 0) < (order[b] ?? 0)
    }.map { CategorySpend(category: $0, cents: cents[$0] ?? 0, previousCents: previous[$0] ?? 0, count: counts[$0] ?? 0) }
    return MonthSpending(monthStart: windows.current.start, totalCents: total, previousTotalCents: previousTotal, byCategory: rows)
}

/// Los pagos de una categoría en el mes (el mes en curso, hasta `now`), el más reciente primero.
public func spendingMovements(in state: LedgerState, category: SpendingCategory, month: Date, now: Date, calendar: Calendar,
                              ownTransferIDs ownTransfers: Set<UUID>? = nil,
                              subscriptionKeys keys: Set<String>? = nil) -> [Movement] {
    guard let windows = monthWindows(month: month, now: now, calendar: calendar) else { return [] }
    let transfers = ownTransfers ?? ownTransferIDs(in: state.movements)
    let subKeys = keys ?? subscriptionKeys(in: state, now: now, calendar: calendar, ownTransferIDs: transfers)
    return spendingMovements(in: state.movements, excluding: transfers)
        .filter { windows.current.contains($0.date) && categoryOf($0, in: state, subscriptionKeys: subKeys) == category }
        .sorted { $0.date != $1.date ? $0.date > $1.date : $0.id.uuidString > $1.id.uuidString }
}

/// Previsión del mes: lo gastado, más el ritmo de lo que no son suscripciones por los días que faltan, más las
/// suscripciones que aún se cobrarán este mes. nil antes del día 5 (muy pocos datos).
public func monthForecast(in state: LedgerState, now: Date, calendar: Calendar,
                          ownTransferIDs ownTransfers: Set<UUID>? = nil,
                          subscriptions subs: [Subscription]? = nil) -> MonthForecast? {
    let day = calendar.component(.day, from: now)
    guard day >= 5, let interval = calendar.dateInterval(of: .month, for: now),
          let days = calendar.range(of: .day, in: .month, for: now)?.count else { return nil }
    let transfers = ownTransfers ?? ownTransferIDs(in: state.movements)
    let subscriptions = subs ?? detectSubscriptions(in: state.movements, now: now, calendar: calendar, ownTransferIDs: transfers)
    let keys = Set(subscriptions.map(\.id))
    var spent = 0
    var fromSubscriptions = 0
    for m in spendingMovements(in: state.movements, excluding: transfers) where m.date >= interval.start && m.date <= now {
        let amount = abs(m.amountCents)
        spent += amount
        if keys.contains(normalizeMerchant(m.merchant ?? "")) { fromSubscriptions += amount }
    }
    let remaining = days - day
    let pending = subscriptions.filter { $0.nextDate > now && $0.nextDate < interval.end }.reduce(0) { $0 + $1.amountCents }
    let projected = spent + (spent - fromSubscriptions) * remaining / day + pending
    return MonthForecast(spentCents: spent, projectedCents: projected, pendingSubscriptionsCents: pending)
}

/// Media mensual de gasto de los `months` meses completos anteriores a `month`, sin contar los meses previos al primer
/// movimiento del libro (un mes sin gasto cuenta como cero). nil si no hay ningún mes completo que promediar.
/// Con `category` solo suma esa categoría; las suscripciones se reconocen con `subscriptionKeys` o, si falta, con las
/// detectadas al empezar `month`.
public func averageMonthlySpending(in state: LedgerState, category: SpendingCategory?, before month: Date, months: Int,
                                   calendar: Calendar, ownTransferIDs ownTransfers: Set<UUID>? = nil,
                                   subscriptionKeys keys: Set<String>? = nil) -> Int? {
    guard months > 0, let first = state.movements.map(\.date).min(),
          let firstMonth = calendar.dateInterval(of: .month, for: first)?.start,
          let monthStart = calendar.dateInterval(of: .month, for: month)?.start,
          let earliest = calendar.date(byAdding: .month, value: -months, to: monthStart) else { return nil }
    let from = max(earliest, firstMonth)
    guard from < monthStart,
          let count = calendar.dateComponents([.month], from: from, to: monthStart).month, count > 0 else { return nil }
    let transfers = ownTransfers ?? ownTransferIDs(in: state.movements)
    var subKeys = keys ?? []
    if category != nil, keys == nil {
        subKeys = subscriptionKeys(in: state, now: monthStart, calendar: calendar, ownTransferIDs: transfers)
    }
    var sum = 0
    for m in spendingMovements(in: state.movements, excluding: transfers) where m.date >= from && m.date < monthStart {
        if let category, categoryOf(m, in: state, subscriptionKeys: subKeys) != category { continue }
        sum += abs(m.amountCents)
    }
    return sum / count
}
