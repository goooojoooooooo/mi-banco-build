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

    // MARK: J12 — cobros retrasados y mínimos

    private func overdueState(first: Date = date(9, 18), second: Date = date(10, 18)) -> LedgerState {
        var state = LedgerState()
        state.movements = subscription(.rev, "Spotify", 1099, first, second)
        state.balances[.rev] = ManualBalance(cents: 10_000, setAt: date(11, 20, 8), origin: .bank)
        return state
    }

    @Test func unCobroRetrasadoSeColocaHoyYSeResta() throws {
        // Su fecha era el 18 y no llegó: hoy (20) cuenta con su fecha debida.
        let days = calendarOf(overdueState())
        let charge = try #require(days[0].charges.first)
        #expect(days[0].charges.count == 1)
        #expect(charge.name == "Spotify")
        #expect(charge.overdue)
        #expect(charge.dueDate == date(11, 18, 12))
        #expect(charge.date == date(11, 20, 0))
        #expect(overdueNote(charge, calendar: cal) == "con retraso, debía cobrarse el 18")
        #expect(days[0].balanceAfter[.rev] == 10_000 - 1099)
        #expect(days[13].balanceAfter[.rev] == 10_000 - 1099)
        #expect(days.flatMap(\.charges).count == 1)
        // Un cobro normal no lleva nota.
        let normal = UpcomingCharge(name: "Netflix", bank: .rev, cents: 1399, date: date(11, 25))
        #expect(!normal.overdue && overdueNote(normal, calendar: cal) == nil)
    }

    @Test func elLimiteDeCatorceDiasDeRetraso() {
        // Debía cobrarse el 6 (14 días antes de hoy): todavía se coloca.
        let edge = calendarOf(overdueState(first: date(9, 6), second: date(10, 6)))
        #expect(edge[0].charges.first?.overdue == true)
        #expect(edge[0].charges.first?.dueDate == date(11, 6, 12))
        // Ya cobrado hoy: no se cuenta ni como retrasado.
        var booked = overdueState()
        booked.movements.append(mv(.rev, -1099, "Spotify", at: date(11, 20, 8)))
        #expect(calendarOf(booked, now: date(11, 20, 9)).flatMap(\.charges).filter(\.overdue).isEmpty)
    }

    @Test func elPrimerDiaPorDebajoDelMinimo() {
        var state = twoSubscriptions()
        state.balances[.rev] = ManualBalance(cents: 5_500, setAt: date(11, 20, 8), origin: .bank)
        var book = AccountBook()
        book.floors[.rev] = 5_000
        let days = calendarOf(state, book: book)
        #expect(firstBelowFloorDays(days) == [.rev: date(11, 22, 0)])
        #expect(firstBelowFloorDays(calendarOf(state)).isEmpty)
        // Un banco que ya está por debajo hoy: el día de hoy.
        state.balances[.rev] = ManualBalance(cents: 4_000, setAt: date(11, 20, 8), origin: .bank)
        #expect(firstBelowFloorDays(calendarOf(state, book: book)) == [.rev: date(11, 20, 0)])
    }

    @Test func sinNadaSigueHabiendoCatorceDias() {
        let days = calendarOf(LedgerState())
        #expect(days.count == 14)
        #expect(days.allSatisfy { $0.isEmpty && $0.balanceAfter.isEmpty })
    }

    // MARK: Ronda U0–U68 (U21, U22)

    @Test func unSoloPasarPorBanco() throws {
        var state = LedgerState()
        state.movements = subscription(.rev, "Spotify", 1099, date(9, 21), date(10, 21))
            + subscription(.rev, "Netflix", 1399, date(9, 22), date(10, 22))
        state.balances[.rev] = ManualBalance(cents: 6_000, setAt: date(11, 20, 8), origin: .bank)
        var book = AccountBook()
        book.floors[.rev] = 5_000

        let now = date(11, 20, 8, 30)
        let days = upcomingCalendar(state: state, book: book, now: now, calendar: cal)
        let topUps = calendarTopUps(days: days, floors: book.floors)
        #expect(topUps.count == 1)
        let rev = try #require(topUps.first)
        #expect(rev.bank == .rev)
        #expect(rev.firstDay == date(11, 21, 0))
        #expect(rev.suggestedCents == 2_000)

        // Cuadra con `shortfalls` del resumen.
        let upcoming = subscriptionCharges(in: state, now: now, calendar: cal)
        let sf = shortfalls(balances: [.rev: 6_000], floors: book.floors, upcoming: upcoming, now: now, calendar: cal)
        #expect(sf.first?.suggestedCents == 2_000)
    }

    @Test func finDeMesSuscripcion() throws {
        // 31 ene + 28 feb 2026 -> 31 mar 2026.
        let s31 = detectSubscriptions(in: subscription(.rev, "Alquiler", 50_000, date(1, 31), date(2, 28)),
                                      now: date(3, 10), calendar: cal)
        #expect(try #require(s31.first).nextDate == date(3, 31))

        // 30 ene + 28 feb 2026 -> 30 mar 2026.
        let s30 = detectSubscriptions(in: subscription(.rev, "Gym", 3_000, date(1, 30), date(2, 28)),
                                      now: date(3, 10), calendar: cal)
        #expect(try #require(s30.first).nextDate == date(3, 30))

        // Control: 15 ene + 15 feb -> 15 mar; 28 ene + 28 feb -> 28 mar.
        let s15 = detectSubscriptions(in: subscription(.rev, "Spotify", 1_099, date(1, 15), date(2, 15)),
                                      now: date(3, 10), calendar: cal)
        #expect(try #require(s15.first).nextDate == date(3, 15))
        let s28 = detectSubscriptions(in: subscription(.rev, "Netflix", 1_399, date(1, 28), date(2, 28)),
                                      now: date(3, 10), calendar: cal)
        #expect(try #require(s28.first).nextDate == date(3, 28))
    }

    @Test func finDeMesNoEsRetraso() {
        var state = LedgerState()
        state.movements = subscription(.rev, "Alquiler", 50_000, date(1, 31), date(2, 28))
        let days = upcomingCalendar(state: state, book: AccountBook(), now: date(3, 29, 9), calendar: cal)
        #expect(days.flatMap(\.charges).allSatisfy { !$0.overdue })
        #expect(days[2].charges.map(\.name) == ["Alquiler"])
    }

    @Test func finDeMesNomina() throws {
        var state = LedgerState()
        state.movements = [
            mv(.ima, 185_000, "Nómina ACME", at: date(1, 31, 9), shop: false),
            mv(.ima, 185_000, "Nómina ACME", at: date(2, 28, 9), shop: false),
        ]
        let inc = try #require(expectedIncome(in: state, now: date(3, 20, 9), calendar: cal))
        #expect(inc.date == date(3, 31, 12))
    }
}
