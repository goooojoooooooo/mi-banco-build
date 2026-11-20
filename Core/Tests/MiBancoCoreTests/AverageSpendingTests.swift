import Foundation
import Testing
@testable import MiBancoCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Madrid")!
    return c
}()

private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    cal.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}

private func pay(_ cents: Int, _ merchant: String, _ when: Date) -> Movement {
    Movement(bank: .rev, amountCents: -cents, merchant: merchant, kind: .payment, source: .notification, date: when, isShop: true)
}

@Suite struct AverageSpendingTests {
    private func book() -> LedgerState {
        LedgerState(movements: [
            pay(3000, "Mercadona", date(2026, 8, 5)),
            pay(6000, "Restaurante Lateral", date(2026, 9, 10)),
            pay(9000, "Mercadona", date(2026, 9, 12)),
            pay(1500, "Bar Pepe", date(2026, 10, 3)),
            pay(4500, "Mercadona", date(2026, 10, 20)),
            pay(7000, "Mercadona", date(2026, 11, 8)),
        ])
    }

    @Test func coincideConLaMediaPorCategoria() {
        let state = book()
        let nov = date(2026, 11, 1)
        let keys = Set<String>()
        let all = averageMonthlySpendingByCategory(in: state, before: nov, months: 3, calendar: cal, subscriptionKeys: keys)
        #expect(all?.total == averageMonthlySpending(in: state, category: nil, before: nov, months: 3, calendar: cal))
        for category in SpendingCategory.allCases {
            let single = averageMonthlySpending(in: state, category: category, before: nov, months: 3, calendar: cal,
                                                subscriptionKeys: keys)
            #expect((all?.byCategory[category] ?? 0) == (single ?? 0))
        }
        #expect(all?.byCategory[.supermercado] == 5500)
        #expect(all?.byCategory[.comerFuera] == 2500)
    }

    @Test func sinMesesCompletosEsNil() {
        let state = LedgerState(movements: [pay(1000, "Mercadona", date(2026, 11, 3))])
        #expect(averageMonthlySpendingByCategory(in: state, before: date(2026, 11, 20), months: 3, calendar: cal) == nil)
    }

    @Test func noCuentaLosMesesPreviosAlPrimerMovimiento() {
        // Primer movimiento en septiembre: noviembre promedia septiembre y octubre (2 meses), no 3.
        let state = LedgerState(movements: [pay(6000, "Mercadona", date(2026, 9, 10)), pay(2000, "Mercadona", date(2026, 10, 2))])
        let result = averageMonthlySpendingByCategory(in: state, before: date(2026, 11, 1), months: 3, calendar: cal)
        #expect(result?.total == 4000)
    }
}
