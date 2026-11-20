import Foundation
import Testing
@testable import MiBancoCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Madrid")!
    c.locale = Locale(identifier: "es_ES")
    return c
}()

private func date(_ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, year: Int = 2026) -> Date {
    cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private func mv(_ bank: BankID, _ cents: Int, _ merchant: String, at when: Date, shop: Bool = true) -> Movement {
    Movement(bank: bank, amountCents: cents, merchant: merchant, kind: cents < 0 ? .payment : .income, source: .notification,
             date: when, isShop: shop)
}

private func subscription(_ bank: BankID, _ name: String, _ cents: Int, _ first: Date, _ second: Date) -> [Movement] {
    [mv(bank, -cents, name, at: first), mv(bank, -cents, name, at: second)]
}

private func calendarOf(_ state: LedgerState, book: AccountBook = AccountBook(), now: Date = date(11, 20, 8, 30)) -> [UpcomingDay] {
    upcomingCalendar(state: state, book: book, now: now, calendar: cal)
}

@Suite struct UpcomingCalendarTests {
    private func twoSubscriptions() -> LedgerState {
        var state = LedgerState()
        state.movements = subscription(.rev, "Spotify", 1099, date(9, 22), date(10, 22))
            + subscription(.rev, "Netflix", 1399, date(9, 25), date(10, 25))
        state.balances[.rev] = ManualBalance(cents: 10_000, setAt: date(11, 20, 8), origin: .bank)
        return state
    }

    @Test func catorceDiasDeMadrid() {
        let days = calendarOf(twoSubscriptions())
        #expect(days.count == 14)
        #expect(days.first?.day == date(11, 20, 0))
        #expect(days.last?.day == date(12, 3, 0))
        for (i, d) in days.enumerated() { #expect(cal.dateComponents([.day], from: days[0].day, to: d.day).day == i) }
    }

    @Test func cadaCobroEnSuDiaYElSaldoAcumula() {
        let days = calendarOf(twoSubscriptions())
        #expect(days[1].charges.isEmpty)
        #expect(days[2].charges.map(\.name) == ["Spotify"])
        #expect(days[5].charges.map(\.name) == ["Netflix"])
        #expect(days[1].balanceAfter[.rev] == 10_000)
        #expect(days[2].balanceAfter[.rev] == 10_000 - 1099)
        #expect(days[4].balanceAfter[.rev] == 10_000 - 1099)
        #expect(days[5].balanceAfter[.rev] == 10_000 - 1099 - 1399)
        #expect(days[13].balanceAfter[.rev] == 10_000 - 1099 - 1399)
        #expect(days.flatMap(\.charges).count == 2)
        #expect(days.map(\.isEmpty) == (0..<14).map { $0 != 2 && $0 != 5 })
    }

    @Test func unCobroYaHechoHoyNoSeCuentaDosVeces() {
        var state = LedgerState()
        state.movements = subscription(.rev, "Spotify", 1099, date(10, 20, 8), date(11, 20, 8))
        state.balances[.rev] = ManualBalance(cents: 10_000, setAt: date(11, 20, 7), origin: .manual)
        let days = calendarOf(state, now: date(11, 20, 9))
        #expect(days.flatMap(\.charges).isEmpty)
        // El saldo ya incluye el pago de hoy (movimiento posterior a la lectura): no se resta otra vez.
        #expect(days[0].balanceAfter[.rev] == 10_000 - 1099)
        #expect(days[13].balanceAfter[.rev] == 10_000 - 1099)
    }

    @Test func elSaldoEstimadoSeMarca() {
        var state = twoSubscriptions()
        #expect(calendarOf(state)[0].estimatedBanks.isEmpty)
        state.balances[.rev] = ManualBalance(cents: 10_000, setAt: date(11, 20, 8), origin: .manual)
        #expect(calendarOf(state).allSatisfy { $0.estimatedBanks == [.rev] })
    }

    @Test func sinSaldoSeListanLosCobros() {
        var state = twoSubscriptions()
        state.balances = [:]
        let days = calendarOf(state)
        #expect(days[2].charges.map(\.name) == ["Spotify"])
        #expect(days.allSatisfy { $0.balanceAfter.isEmpty })
    }

    @Test func laNominaEsperadaSuma() {
        var state = LedgerState()
        state.movements = [mv(.ima, 185_000, "Nómina ACME", at: date(9, 27), shop: false),
                           mv(.ima, 185_000, "Nómina ACME", at: date(10, 28), shop: false)]
        state.balances[.ima] = ManualBalance(cents: 50_000, setAt: date(11, 20, 8), origin: .bank)
        let days = calendarOf(state)
        #expect(days[8].expectedIncome == [ExpectedIncome(name: "Nómina ACME", bank: .ima, cents: 185_000, date: date(11, 28, 12))])
        #expect(days[7].balanceAfter[.ima] == 50_000)
        #expect(days[8].balanceAfter[.ima] == 235_000)
        #expect(days[13].balanceAfter[.ima] == 235_000)
        // Fuera de los 14 días no sale.
        #expect(calendarOf(state, now: date(11, 10, 8, 30)).allSatisfy { $0.expectedIncome.isEmpty })
    }

    @Test func porDebajoDelMinimo() {
        var state = twoSubscriptions()
        state.balances[.rev] = ManualBalance(cents: 5_500, setAt: date(11, 20, 8), origin: .bank)
        var book = AccountBook()
        book.floors[.rev] = 5_000
        let days = calendarOf(state, book: book)
        #expect(days[1].belowFloor.isEmpty)
        #expect(days[2].belowFloor == [.rev])
        #expect(days[13].belowFloor == [.rev])
        // Sin mínimo, solo un saldo negativo cuenta.
        #expect(calendarOf(state).allSatisfy { $0.belowFloor.isEmpty })
        state.balances[.rev] = ManualBalance(cents: 1_000, setAt: date(11, 20, 8), origin: .bank)
        #expect(calendarOf(state)[2].belowFloor == [.rev])
    }

    @Test func cambioDeHoraDeOtono() {
        // El domingo 25 de octubre de 2026 la hora de las 02:00 se repite: sigue habiendo un día por fecha.
        var state = LedgerState()
        state.movements = subscription(.ima, "Gimnasio", 3000, date(8, 26), date(9, 26))
        state.balances[.ima] = ManualBalance(cents: 20_000, setAt: date(10, 20, 8), origin: .bank)
        let days = calendarOf(state, now: date(10, 20, 8, 30))
        #expect(days.count == 14)
        #expect(days.map { cal.component(.day, from: $0.day) } == [20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 1, 2])
        #expect(days.allSatisfy { cal.component(.hour, from: $0.day) == 0 })
        #expect(days[6].charges.map(\.name) == ["Gimnasio"])
        #expect(days[5].balanceAfter[.ima] == 20_000)
        #expect(days[6].balanceAfter[.ima] == 17_000)
    }

    @Test func sinNadaSigueHabiendoCatorceDias() {
        let days = calendarOf(LedgerState())
        #expect(days.count == 14)
        #expect(days.allSatisfy { $0.isEmpty && $0.balanceAfter.isEmpty })
    }
}
