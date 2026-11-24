import Foundation

public struct Subscription: Equatable, Sendable, Identifiable {
    /// Clave normalizada del comercio.
    public var id: String
    public let merchant: String
    public let bank: BankID
    public let amountCents: Int
    public let previousAmountCents: Int?
    public let lastDate: Date
    public let nextDate: Date

    public init(id: String, merchant: String, bank: BankID, amountCents: Int, previousAmountCents: Int?,
                lastDate: Date, nextDate: Date) {
        self.id = id
        self.merchant = merchant
        self.bank = bank
        self.amountCents = amountCents
        self.previousAmountCents = previousAmountCents
        self.lastDate = lastDate
        self.nextDate = nextDate
    }
}

/// Pagos (no ingresos, no marcados como "no es mío") al mismo comercio normalizado y banco: al menos 2 cargos seguidos
/// con 26–35 días entre sí e importes dentro de ±25 %. Si el último cargo tiene 45 días o más, se da por cancelada.
public func detectSubscriptions(in movements: [Movement], now: Date, calendar: Calendar,
                                notSpending: Set<UUID>? = nil) -> [Subscription] {
    var groups: [String: [Movement]] = [:]
    for m in spendingMovements(in: movements, notSpending: notSpending) {
        guard let merchant = m.merchant else { continue }
        let key = normalizeMerchant(merchant)
        if key.isEmpty { continue }
        groups[m.bank.rawValue + "|" + key, default: []].append(m)
    }
    var result: [Subscription] = []
    for (_, group) in groups {
        let sorted = group.sorted { $0.date < $1.date }
        guard let last = sorted.last, now.timeIntervalSince(last.date) < 45 * 86_400 else { continue }
        var chainLength = 1
        var newer = last
        var i = sorted.count - 2
        while i >= 0 {
            let older = sorted[i]
            let from = calendar.startOfDay(for: older.date)
            let to = calendar.startOfDay(for: newer.date)
            let gap = calendar.dateComponents([.day], from: from, to: to).day ?? 0
            let olderCents = abs(older.amountCents)
            guard (26...35).contains(gap), abs(abs(newer.amountCents) - olderCents) * 4 <= olderCents else { break }
            chainLength += 1
            newer = older
            i -= 1
        }
        guard chainLength >= 2 else { continue }
        let chainStart = sorted.count - chainLength
        let chainDates = sorted[chainStart...].map(\.date)
        let previous = abs(sorted[sorted.count - 2].amountCents)
        let latest = abs(last.amountCents)
        let key = normalizeMerchant(last.merchant ?? "")
        let nextDate = nextAnchoredMonthlyDate(last: last.date, priorDates: chainDates, calendar: calendar)
        result.append(Subscription(
            id: key, merchant: last.merchant ?? key, bank: last.bank, amountCents: latest,
            previousAmountCents: previous == latest ? nil : previous, lastDate: last.date,
            nextDate: nextDate))
    }
    return result.sorted { a, b in
        if a.nextDate != b.nextDate { return a.nextDate < b.nextDate }
        if a.id != b.id { return a.id < b.id }
        return a.bank.rawValue < b.bank.rawValue
    }
}

/// Fecha del mes siguiente respetando el día ancla de fin de mes (U22): si `last` cayó el último día de su mes
/// y alguna fecha previa de la cadena tiene un día mayor (p. ej. 31 ene + 28 feb), el ancla es ese día mayor
/// recortado a la longitud del mes siguiente (31 mar).
func nextAnchoredMonthlyDate(last: Date, priorDates: [Date], calendar: Calendar, fixedHour: Int? = nil) -> Date {
    let lastDay = calendar.component(.day, from: last)
    let lastMonthLength = calendar.range(of: .day, in: .month, for: last)?.count ?? lastDay
    var anchorDay = lastDay
    if lastDay == lastMonthLength {
        let maxPrior = priorDates.map { calendar.component(.day, from: $0) }.max() ?? lastDay
        if maxPrior > lastDay { anchorDay = maxPrior }
    }
    guard let lastMonthStart = calendar.dateInterval(of: .month, for: last)?.start,
          let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: lastMonthStart),
          let nextMonthLength = calendar.range(of: .day, in: .month, for: nextMonthStart)?.count else {
        return calendar.date(byAdding: .month, value: 1, to: last) ?? last
    }
    var parts = calendar.dateComponents([.year, .month], from: nextMonthStart)
    parts.day = min(anchorDay, nextMonthLength)
    if let fixedHour {
        parts.hour = fixedHour
        parts.minute = 0
        parts.second = 0
    } else {
        let time = calendar.dateComponents([.hour, .minute, .second], from: last)
        parts.hour = time.hour
        parts.minute = time.minute
        parts.second = time.second
    }
    return calendar.date(from: parts) ?? (calendar.date(byAdding: .month, value: 1, to: last) ?? last)
}

/// Las suscripciones detectadas sin las que el dueño ocultó (id `"<banco>|<clave>"` en `dismissedSubscriptions`).
public func activeSubscriptions(in state: LedgerState, now: Date, calendar: Calendar,
                                notSpending: Set<UUID>? = nil) -> [Subscription] {
    detectSubscriptions(in: state.movements, now: now, calendar: calendar,
                        notSpending: notSpending ?? spendingExclusions(in: state, now: now))
        .filter { !state.dismissedSubscriptions.contains("\($0.bank.rawValue)|\($0.id)") }
}

/// Lo que cuestan al mes y al año (12 cuotas) las suscripciones dadas.
public func subscriptionTotals(_ subscriptions: [Subscription]) -> (monthlyCents: Int, yearlyCents: Int) {
    let monthly = subscriptions.reduce(0) { $0 + $1.amountCents }
    return (monthly, monthly * 12)
}
