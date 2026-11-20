import Foundation

public struct UpcomingCharge: Equatable, Sendable {
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

public struct PayOption: Equatable, Sendable {
    public let bank: BankID
    public let leftAfterCents: Int
    public let fits: Bool
    /// true = el saldo de ese banco es una estimación (no lo dijo el banco).
    public let isEstimated: Bool

    public init(bank: BankID, leftAfterCents: Int, fits: Bool, isEstimated: Bool = false) {
        self.bank = bank
        self.leftAfterCents = leftAfterCents
        self.fits = fits
        self.isEstimated = isEstimated
    }
}

private func order(_ bank: BankID) -> Int { BankID.allCases.firstIndex(of: bank) ?? 0 }

/// De dónde pagar: lo que queda tras el pago, el mínimo y los cobros próximos de ese banco.
/// Primero los que alcanzan; dentro de cada grupo, de más a menos sobrante y Trade Republic al final.
/// Solo cuentan los bancos que el dueño ha incluido (`included`); `estimated` marca los de saldo estimado.
public func whereToPay(amountCents: Int, balances: [BankID: Int], floors: [BankID: Int],
                       upcoming: [UpcomingCharge], included: Set<BankID> = Set(BankID.allCases),
                       estimated: Set<BankID> = []) -> [PayOption] {
    let options = balances.filter { included.contains($0.key) }.map { bank, balance -> PayOption in
        let charges = upcoming.filter { $0.bank == bank }.reduce(0) { $0 + $1.cents }
        let left = balance - amountCents - (floors[bank] ?? 0) - charges
        return PayOption(bank: bank, leftAfterCents: left, fits: left >= 0, isEstimated: estimated.contains(bank))
    }
    func sorted(_ list: [PayOption]) -> [PayOption] {
        let normal = list.filter { $0.bank != .tr }.sorted {
            $0.leftAfterCents != $1.leftAfterCents ? $0.leftAfterCents > $1.leftAfterCents : order($0.bank) < order($1.bank)
        }
        return normal + list.filter { $0.bank == .tr }
    }
    return sorted(options.filter(\.fits)) + sorted(options.filter { !$0.fits })
}

public struct Shortfall: Equatable, Sendable {
    public let bank: BankID
    public let charge: UpcomingCharge
    public let balanceCents: Int
    public let missingCents: Int
    public let suggestedFrom: BankID?
    public let suggestedCents: Int
    /// true = el saldo del banco que se queda corto es una estimación.
    public let isEstimated: Bool
    /// true = el saldo del banco sugerido como origen es una estimación.
    public let suggestedIsEstimated: Bool

    public init(bank: BankID, charge: UpcomingCharge, balanceCents: Int, missingCents: Int, suggestedFrom: BankID?,
                suggestedCents: Int, isEstimated: Bool = false, suggestedIsEstimated: Bool = false) {
        self.isEstimated = isEstimated
        self.suggestedIsEstimated = suggestedIsEstimated
        self.bank = bank
        self.charge = charge
        self.balanceCents = balanceCents
        self.missingCents = missingCents
        self.suggestedFrom = suggestedFrom
        self.suggestedCents = suggestedCents
    }
}

/// Bancos incluidos a los que les falta saldo para un cobro de los próximos 3 días, con de dónde traspasar.
/// Los cobros anteriores a `now` no cuentan (ya están en el saldo).
public func shortfalls(balances: [BankID: Int], floors: [BankID: Int], upcoming: [UpcomingCharge], now: Date,
                       calendar: Calendar, included: Set<BankID> = Set(BankID.allCases),
                       estimated: Set<BankID> = []) -> [Shortfall] {
    let start = calendar.startOfDay(for: now)
    guard let horizon = calendar.date(byAdding: .day, value: 3, to: start) else { return [] }
    var result: [Shortfall] = []
    for bank in BankID.allCases {
        guard included.contains(bank), let balance = balances[bank] else { continue }
        let soon = upcoming.filter { $0.bank == bank && $0.date >= now && $0.date < horizon }.sorted { $0.date < $1.date }
        guard let first = soon.first else { continue }
        let missing = soon.reduce(0) { $0 + $1.cents } + (floors[bank] ?? 0) - balance
        guard missing > 0 else { continue }
        let suggested = (missing + 999) / 1000 * 1000
        var others = balances
        others[bank] = nil
        let source = whereToPay(amountCents: suggested, balances: others, floors: floors, upcoming: upcoming,
                                included: included, estimated: estimated).first(where: \.fits)
        result.append(Shortfall(bank: bank, charge: first, balanceCents: balance, missingCents: missing,
                                suggestedFrom: source?.bank, suggestedCents: suggested,
                                isEstimated: estimated.contains(bank), suggestedIsEstimated: source?.isEstimated ?? false))
    }
    return result.sorted { $0.charge.date != $1.charge.date ? $0.charge.date < $1.charge.date : order($0.bank) < order($1.bank) }
}

public struct FreeMoney: Equatable, Sendable {
    public let cents: Int
    public let daysLeft: Int
    /// Bancos incluidos de los que no se conoce el saldo (no suman): quien lo muestra puede avisarlo.
    public let missingBanks: [BankID]
    public var perDayCents: Int { cents / daysLeft }

    public init(cents: Int, daysLeft: Int, missingBanks: [BankID] = []) {
        self.cents = cents
        self.daysLeft = max(1, daysLeft)
        self.missingBanks = missingBanks
    }
}

/// Lo que se puede gastar hasta fin de mes: saldos menos mínimos menos los cobros que faltan este mes.
/// nil sin saldos conocidos o si no sobra nada.
public func freeMoney(balances: [BankID: Int], floors: [BankID: Int], banks: Set<BankID>, pending: [UpcomingCharge],
                      now: Date, calendar: Calendar) -> FreeMoney? {
    let known = banks.filter { balances[$0] != nil }
    guard !known.isEmpty else { return nil }
    let total = known.reduce(0) { $0 + (balances[$1] ?? 0) - (floors[$1] ?? 0) }
    let charges = pending.filter {
        banks.contains($0.bank) && $0.date >= now && calendar.isDate($0.date, equalTo: now, toGranularity: .month)
    }.reduce(0) { $0 + $1.cents }
    let free = total - charges
    guard free > 0,
          let days = calendar.range(of: .day, in: .month, for: now)?.count else { return nil }
    let today = calendar.component(.day, from: now)
    let missing = BankID.allCases.filter { banks.contains($0) && balances[$0] == nil }
    return FreeMoney(cents: free, daysLeft: days - today + 1, missingBanks: missing)
}
