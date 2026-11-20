import Foundation

/// Un día del calendario de próximos cobros (día de Madrid, a las 00:00 del calendario que se pase).
public struct UpcomingDay: Equatable, Sendable {
    public let day: Date
    /// Cobros de suscripciones que caen ese día, por hora y nombre. Cada cobro sale en un solo día.
    public let charges: [UpcomingCharge]
    /// Ingresos que se esperan ese día (la nómina según el historial: una previsión, no una promesa).
    public let expectedIncome: [ExpectedIncome]
    /// Saldo previsto de cada banco con saldo conocido al terminar ese día: saldo de hoy más lo esperado menos los cobros
    /// hasta ese día incluido. Es una previsión: no cuenta nada que no sea un cobro o un ingreso de esta lista.
    public let balanceAfter: [BankID: Int]
    /// Bancos cuyo saldo de partida es una estimación (no lo dijo el banco): sus cifras son aproximadas.
    public let estimatedBanks: Set<BankID>
    /// Bancos cuyo saldo previsto al terminar el día queda por debajo de su mínimo (0 si no tiene mínimo).
    public let belowFloor: Set<BankID>

    public var isEmpty: Bool { charges.isEmpty && expectedIncome.isEmpty }

    public init(day: Date, charges: [UpcomingCharge], expectedIncome: [ExpectedIncome], balanceAfter: [BankID: Int],
                estimatedBanks: Set<BankID>, belowFloor: Set<BankID>) {
        self.day = day
        self.charges = charges
        self.expectedIncome = expectedIncome
        self.balanceAfter = balanceAfter
        self.estimatedBanks = estimatedBanks
        self.belowFloor = belowFloor
    }
}

/// El primer día (de los que dan `days`) en que el saldo previsto de cada banco queda por debajo de su mínimo. Un banco que no
/// baja en esos días no sale.
public func firstBelowFloorDays(_ days: [UpcomingDay]) -> [BankID: Date] {
    var first: [BankID: Date] = [:]
    for day in days {
        for bank in day.belowFloor where first[bank] == nil { first[bank] = day.day }
    }
    return first
}

/// Cuántos días mira el calendario, hoy incluido.
public let upcomingCalendarDays = 14

/// Los próximos 14 días (hoy incluido), uno por día de Madrid, con los cobros de las suscripciones activas, la nómina
/// esperada y el saldo previsto de cada banco al terminar cada día. Se devuelven los 14 días aunque no pase nada.
///
/// - Un cobro que ya está en el libro hoy no se cuenta otra vez (ni en el día ni en el saldo, que ya lo incluye).
/// - Un cobro cuya fecha cayó en los 14 días anteriores a hoy y no está en el libro se coloca HOY con `overdue` (y su fecha
///   debida en `dueDate`) y se resta del saldo previsto; uno más antiguo no se coloca: no se sabe si sigue vivo.
/// - Un banco sin saldo conocido no tiene saldo previsto, pero sus cobros se listan.
/// - Los gastos corrientes (comida, ocio) no se estiman: solo cobros fijos e ingreso esperado.
public func upcomingCalendar(state: LedgerState, book: AccountBook, now: Date, calendar: Calendar) -> [UpcomingDay] {
    let today = calendar.startOfDay(for: now)
    let exclusions = spendingExclusions(in: state, now: now)

    var running: [BankID: Int] = [:]
    var estimated = Set<BankID>()
    let ledger = Ledger(state: state)
    for bank in BankID.allCases {
        guard let balance = ledger.balance(bank) else { continue }
        running[bank] = balance.cents
        if balance.estimated { estimated.insert(bank) }
    }

    func index(of date: Date) -> Int? {
        guard let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day,
              (0..<upcomingCalendarDays).contains(days) else { return nil }
        return days
    }

    var chargesByDay = [[UpcomingCharge]](repeating: [], count: upcomingCalendarDays)
    var seen = Set<String>()
    for charge in subscriptionCharges(in: state, now: now, calendar: calendar, notSpending: exclusions) {
        guard let i = index(of: charge.date) else { continue }
        // La misma suscripción no se cuenta dos veces el mismo día.
        guard seen.insert("\(charge.bank.rawValue)|\(normalizeMerchant(charge.name))|\(i)").inserted else { continue }
        chargesByDay[i].append(charge)
    }
    var incomeByDay = [[ExpectedIncome]](repeating: [], count: upcomingCalendarDays)
    if let expected = expectedIncome(in: state, now: now, calendar: calendar), let i = index(of: expected.date) {
        incomeByDay[i].append(expected)
    }

    var days: [UpcomingDay] = []
    for i in 0..<upcomingCalendarDays {
        guard let day = calendar.date(byAdding: .day, value: i, to: today) else { break }
        let charges = chargesByDay[i].sorted { $0.date != $1.date ? $0.date < $1.date : $0.name < $1.name }
        for charge in charges where running[charge.bank] != nil { running[charge.bank]! -= charge.cents }
        for income in incomeByDay[i] where running[income.bank] != nil { running[income.bank]! += income.cents }
        let below = Set(running.filter { $0.value < (book.floors[$0.key] ?? 0) }.keys)
        days.append(UpcomingDay(day: day, charges: charges, expectedIncome: incomeByDay[i], balanceAfter: running,
                                estimatedBanks: estimated, belowFloor: below))
    }
    return days
}
