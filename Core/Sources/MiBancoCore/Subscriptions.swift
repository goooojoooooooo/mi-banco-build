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
                                ownTransferIDs: Set<UUID>? = nil) -> [Subscription] {
    var groups: [String: [Movement]] = [:]
    for m in spendingMovements(in: movements, excluding: ownTransferIDs) {
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
        let previous = abs(sorted[sorted.count - 2].amountCents)
        let latest = abs(last.amountCents)
        let key = normalizeMerchant(last.merchant ?? "")
        result.append(Subscription(
            id: key, merchant: last.merchant ?? key, bank: last.bank, amountCents: latest,
            previousAmountCents: previous == latest ? nil : previous, lastDate: last.date,
            nextDate: calendar.date(byAdding: .month, value: 1, to: last.date) ?? last.date))
    }
    return result.sorted { a, b in
        if a.nextDate != b.nextDate { return a.nextDate < b.nextDate }
        if a.id != b.id { return a.id < b.id }
        return a.bank.rawValue < b.bank.rawValue
    }
}

/// Las suscripciones detectadas sin las que el dueño ocultó (id `"<banco>|<clave>"` en `dismissedSubscriptions`).
public func activeSubscriptions(in state: LedgerState, now: Date, calendar: Calendar,
                                ownTransferIDs: Set<UUID>? = nil) -> [Subscription] {
    detectSubscriptions(in: state.movements, now: now, calendar: calendar,
                        ownTransferIDs: ownTransferIDs ?? spendingExclusions(in: state, now: now))
        .filter { !state.dismissedSubscriptions.contains("\($0.bank.rawValue)|\($0.id)") }
}

/// Lo que cuestan al mes y al año (12 cuotas) las suscripciones dadas.
public func subscriptionTotals(_ subscriptions: [Subscription]) -> (monthlyCents: Int, yearlyCents: Int) {
    let monthly = subscriptions.reduce(0) { $0 + $1.amountCents }
    return (monthly, monthly * 12)
}
