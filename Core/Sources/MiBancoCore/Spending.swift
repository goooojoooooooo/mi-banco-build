import Foundation

public struct SpendingPace: Equatable, Sendable {
    public let thisMonthCents: Int
    public let lastMonthSamePointCents: Int
    public var differenceCents: Int { thisMonthCents - lastMonthSamePointCents }

    public init(thisMonthCents: Int, lastMonthSamePointCents: Int) {
        self.thisMonthCents = thisMonthCents
        self.lastMonthSamePointCents = lastMonthSamePointCents
    }
}

public struct WeekSummary: Equatable, Sendable {
    public let spentCents: Int
    public let previousWeekSpentCents: Int
    public let movementCount: Int
    public let topMerchant: String?

    public init(spentCents: Int, previousWeekSpentCents: Int, movementCount: Int, topMerchant: String?) {
        self.spentCents = spentCents
        self.previousWeekSpentCents = previousWeekSpentCents
        self.movementCount = movementCount
        self.topMerchant = topMerchant
    }
}

public struct MerchantHistory: Equatable, Sendable {
    public let countThisMonth: Int
    public let totalThisMonthCents: Int
    public let countAllTime: Int
    public let firstDate: Date?

    public init(countThisMonth: Int, totalThisMonthCents: Int, countAllTime: Int, firstDate: Date?) {
        self.countThisMonth = countThisMonth
        self.totalThisMonthCents = totalThisMonthCents
        self.countAllTime = countAllTime
        self.firstDate = firstDate
    }
}

private func spent(_ movements: [Movement], where include: (Date) -> Bool) -> Int {
    movements.reduce(0) { include($1.date) ? $0 + abs($1.amountCents) : $0 }
}

/// Fin (exclusivo) del tramo comparable del mes anterior cuando se mira el mes en curso: el FINAL del mismo día del mes
/// (R19, granularidad de día: la cifra no cambia con la hora). El día se ajusta a la longitud de ese mes
/// (el 31 de diciembre compara con todo el 30 de noviembre). nil si el calendario no puede construir la fecha.
func sameDayCutoff(now: Date, previousMonthStart prevStart: Date, calendar: Calendar) -> Date? {
    guard let prevDays = calendar.range(of: .day, in: .month, for: prevStart) else { return nil }
    var parts = calendar.dateComponents([.year, .month], from: prevStart)
    parts.day = min(calendar.component(.day, from: now), prevDays.count)
    guard let day = calendar.date(from: parts) else { return nil }
    return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day))
}

/// Gasto de este mes hasta `now` frente al del mes anterior hasta el final del mismo día (el día se ajusta a la
/// longitud de ese mes; ver `sameDayCutoff`). nil si el mes anterior no tiene ningún pago.
public func spendingPace(movements: [Movement], now: Date, calendar: Calendar, notSpending: Set<UUID>? = nil) -> SpendingPace? {
    guard let monthStart = calendar.dateInterval(of: .month, for: now)?.start,
          let prevStart = calendar.date(byAdding: .month, value: -1, to: monthStart) else { return nil }
    let payments = spendingMovements(in: movements, notSpending: notSpending)
    guard payments.contains(where: { $0.date >= prevStart && $0.date < monthStart }) else { return nil }
    guard let cutoff = sameDayCutoff(now: now, previousMonthStart: prevStart, calendar: calendar) else { return nil }
    let thisMonth = spent(payments) { $0 >= monthStart && $0 <= now }
    let lastMonth = spent(payments) { $0 >= prevStart && $0 < cutoff }
    return SpendingPace(thisMonthCents: thisMonth, lastMonthSamePointCents: lastMonth)
}

/// Semana de lunes a domingo que contiene `date`. `movementCount` cuenta los pagos de la semana.
public func weekSummary(movements: [Movement], weekContaining date: Date, calendar: Calendar,
                        notSpending: Set<UUID>? = nil) -> WeekSummary {
    var cal = calendar
    cal.firstWeekday = 2
    cal.minimumDaysInFirstWeek = 4
    guard let week = cal.dateInterval(of: .weekOfYear, for: date),
          let prevStart = cal.date(byAdding: .day, value: -7, to: week.start) else {
        return WeekSummary(spentCents: 0, previousWeekSpentCents: 0, movementCount: 0, topMerchant: nil)
    }
    let payments = spendingMovements(in: movements, notSpending: notSpending)
    let inWeek = payments.filter { $0.date >= week.start && $0.date < week.end }
    let previous = spent(payments) { $0 >= prevStart && $0 < week.start }

    var totals: [String: (cents: Int, name: String, latest: Date)] = [:]
    for m in inWeek {
        guard let name = m.merchant else { continue }
        let key = normalizeMerchant(name)
        if key.isEmpty { continue }
        var entry = totals[key] ?? (0, name, m.date)
        entry.cents += abs(m.amountCents)
        if m.date >= entry.latest { entry.latest = m.date; entry.name = name }
        totals[key] = entry
    }
    let top = totals.min { a, b in
        a.value.cents != b.value.cents ? a.value.cents > b.value.cents : a.key < b.key
    }?.value.name
    return WeekSummary(spentCents: spent(inWeek) { _ in true }, previousWeekSpentCents: previous,
                       movementCount: inWeek.count, topMerchant: top)
}

/// Pagos a un comercio (por clave normalizada): este mes, en total y el primero.
public func merchantHistory(for merchant: String, in movements: [Movement], now: Date, calendar: Calendar,
                            notSpending: Set<UUID>? = nil) -> MerchantHistory {
    let key = normalizeMerchant(merchant)
    let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
    let mine = key.isEmpty ? [] : spendingMovements(in: movements, notSpending: notSpending).filter { normalizeMerchant($0.merchant ?? "") == key }
    let month = mine.filter { $0.date >= monthStart && $0.date <= now }
    return MerchantHistory(countThisMonth: month.count, totalThisMonthCents: month.reduce(0) { $0 + abs($1.amountCents) },
                           countAllTime: mine.count, firstDate: mine.map(\.date).min())
}

/// El historial de todos los comercios con pagos, en una sola pasada (cada movimiento se normaliza una vez).
/// Para cada clave da exactamente lo mismo que `merchantHistory(for:in:now:calendar:)`.
public func merchantHistories(in movements: [Movement], now: Date, calendar: Calendar,
                              notSpending: Set<UUID>? = nil) -> [String: MerchantHistory] {
    let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
    var count: [String: Int] = [:]
    var monthCount: [String: Int] = [:]
    var monthTotal: [String: Int] = [:]
    var first: [String: Date] = [:]
    for m in spendingMovements(in: movements, notSpending: notSpending) {
        let key = normalizeMerchant(m.merchant ?? "")
        if key.isEmpty { continue }
        count[key, default: 0] += 1
        if let known = first[key] { first[key] = min(known, m.date) } else { first[key] = m.date }
        if m.date >= monthStart && m.date <= now {
            monthCount[key, default: 0] += 1
            monthTotal[key, default: 0] += abs(m.amountCents)
        }
    }
    var out: [String: MerchantHistory] = [:]
    for (key, all) in count {
        out[key] = MerchantHistory(countThisMonth: monthCount[key] ?? 0, totalThisMonthCents: monthTotal[key] ?? 0,
                                   countAllTime: all, firstDate: first[key])
    }
    return out
}

private func foldedForSearch(_ s: String) -> String {
    s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
}

/// Búsqueda sin mayúsculas ni tildes en comercio, nombre del banco y nota; y por importe tal como se escribe:
/// "12,50" o "12.50" = exactamente 12,50 €; "12" = cualquier importe de 12 euros. Vacío devuelve todo.
public func searchMovements(_ movements: [Movement], query: String) -> [Movement] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return movements }
    let needle = foldedForSearch(trimmed)
    let isAmount = trimmed.allSatisfy { $0.isASCII && ($0.isNumber || $0 == "," || $0 == ".") }
        && trimmed.contains(where: \.isNumber)
    let hasSeparator = trimmed.contains(",") || trimmed.contains(".")
    let amount = isAmount ? parseAmountToCents(Substring(trimmed)) : nil
    return movements.filter { m in
        if foldedForSearch(m.merchant ?? "").contains(needle) { return true }
        if foldedForSearch(m.bank.displayName).contains(needle) { return true }
        if let note = m.note, foldedForSearch(note).contains(needle) { return true }
        if let amount {
            let cents = abs(m.amountCents)
            return hasSeparator ? cents == amount : cents / 100 == amount / 100
        }
        return false
    }
}
