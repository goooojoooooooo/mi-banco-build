import Foundation

/// Un ingreso que se espera (la nómina): lo que dice el historial, no una promesa.
public struct ExpectedIncome: Equatable, Sendable {
    public let name: String
    public let bank: BankID
    public let cents: Int
    public let date: Date

    public init(name: String, bank: BankID, cents: Int, date: Date) {
        self.name = name
        self.bank = bank
        self.cents = cents
        self.date = date
    }
}

/// Ingresos de al menos esto cuentan como posible nómina.
private let minimumExpectedIncomeCents = 30_000

private func monthIndex(_ date: Date, calendar: Calendar) -> Int {
    let c = calendar.dateComponents([.year, .month], from: date)
    return (c.year ?? 0) * 12 + (c.month ?? 1) - 1
}

/// El próximo ingreso recurrente: mismo comercio (clave de `normalizeMerchant`), de 300 € o más, con un ingreso en cada uno
/// de dos meses seguidos cuyo último caiga en el mes en curso o en el anterior y con el día del mes a 3 días o menos entre
/// ambos. La fecha esperada es el día del último ingreso en el mes siguiente, a las 12:00 (el día se ajusta a la longitud
/// del mes). Se descarta si esa fecha ya pasó. No mira el horizonte: quien lo muestra decide (el resumen, 7 días; el
/// calendario, 14). Traspasos propios, "no es mío" y operaciones de valores no cuentan.
public func expectedIncome(in state: LedgerState, now: Date, calendar: Calendar) -> ExpectedIncome? {
    let transfers = ownTransferIDs(in: state.movements)
    var groups: [String: [Movement]] = [:]
    for m in state.movements where m.kind == .income && m.amountCents >= minimumExpectedIncomeCents && !m.flaggedNotMine
        && !m.excludedFromSpending && !transfers.contains(m.id) {
        let key = normalizeMerchant(m.merchant ?? "")
        if key.isEmpty { continue }
        groups[m.bank.rawValue + "|" + key, default: []].append(m)
    }
    let current = monthIndex(now, calendar: calendar)
    var best: ExpectedIncome?
    for (_, group) in groups {
        guard let last = group.max(by: { $0.date < $1.date }) else { continue }
        let lastMonth = monthIndex(last.date, calendar: calendar)
        guard lastMonth == current || lastMonth == current - 1 else { continue }
        let day = calendar.component(.day, from: last.date)
        let regular = group.contains {
            monthIndex($0.date, calendar: calendar) == lastMonth - 1
                && abs(calendar.component(.day, from: $0.date) - day) <= 3
        }
        guard regular else { continue }
        let nextMonth = lastMonth + 1
        var parts = DateComponents(year: nextMonth / 12, month: nextMonth % 12 + 1, day: 1, hour: 12)
        guard let first = calendar.date(from: parts), let length = calendar.range(of: .day, in: .month, for: first)?.count else { continue }
        parts.day = min(day, length)
        guard let next = calendar.date(from: parts), next > now else { continue }
        let candidate = ExpectedIncome(name: last.merchant ?? last.bank.displayName, bank: last.bank,
                                       cents: last.amountCents, date: next)
        if let incumbent = best {
            if candidate.date < incumbent.date || (candidate.date == incumbent.date && candidate.cents > incumbent.cents) { best = candidate }
        } else {
            best = candidate
        }
    }
    return best
}
