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

private func nov(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date { date(11, day, hour, minute) }

private func pay(_ cents: Int, _ merchant: String?, _ when: Date, bank: BankID = .rev,
                 source: Movement.Source = .notification) -> Movement {
    Movement(bank: bank, amountCents: -cents, merchant: merchant, kind: .payment, source: source, date: when)
}

private func ledger(_ movements: [Movement], balances: [BankID: ManualBalance] = [:],
                    settings: AlertSettings = AlertSettings(), muted: Set<String> = [],
                    budgets: Budgets = Budgets(), links: [BankID: BankLinkInfo] = [:],
                    overrides: [String: SpendingCategory] = [:]) -> LedgerState {
    LedgerState(balances: balances, movements: movements, unread: [], alertSettings: settings,
                mutedMerchants: muted, categoryOverrides: overrides, budgets: budgets, links: links)
}

@Suite struct NyxMoneyWatchTests {
    @Test func pagoPocoHabitualEsEspejoEnElMomentoAviso() throws {
        let prior = [pay(2000, "Mercadona", nov(2)), pay(2100, "Mercadona", nov(9)), pay(1900, "Mercadona", nov(16))]
        let new = pay(7000, "Mercadona", nov(26, 10))
        let obs = nyxMoneyObservations(state: ledger(prior + [new]), book: AccountBook(), newMovementIDs: [new.id],
                                       moment: .notice, now: nov(26, 10, 1), calendar: cal)
        let o = try #require(obs.first { $0.situation == .unusualPayment })
        #expect(o.id == "unusualPayment|\(new.id.uuidString)" && o.priority == .normal && o.viaInstantAlert)
        #expect(o.facts.cents == 7000 && o.facts.usualCents == 2000 && o.facts.merchant == "Mercadona" && o.facts.bank == .rev)
        let bg = nyxMoneyObservations(state: ledger(prior + [new]), book: AccountBook(), newMovementIDs: [new.id],
                                      moment: .background, now: nov(26, 10, 1), calendar: cal)
        #expect(bg.first { $0.situation == .unusualPayment }?.viaInstantAlert == false)
    }

    @Test func duplicadoEsUrgente() {
        let a = pay(1299, "Cabify", nov(26, 10))
        let b = pay(1299, "Cabify", nov(26, 10, 5))
        let obs = nyxMoneyObservations(state: ledger([a, b]), book: AccountBook(), newMovementIDs: [b.id], moment: .notice,
                                       now: nov(26, 10, 6), calendar: cal)
        #expect(obs.contains { $0.situation == .duplicateCharge && $0.priority == .urgent && $0.facts.movementID == b.id })
    }

    @Test func cobroQueNoCabeConDeDondeTraspasar() throws {
        let s = ledger([pay(1099, "Spotify", date(9, 27)), pay(1099, "Spotify", date(10, 27))],
                       balances: [.rev: ManualBalance(cents: 3000, setAt: nov(26, 9), fromBank: true),
                                  .ima: ManualBalance(cents: 100_000, setAt: nov(26, 9), fromBank: true)])
        var book = AccountBook()
        book.floors[.rev] = 2500
        let o = try #require(nyxMoneyObservations(state: s, book: book, newMovementIDs: [], moment: .open,
                                                  now: nov(26, 12), calendar: cal).first { $0.situation == .shortfall })
        #expect(o.id == "shortfall|rev|spotify|2026-11-27" && o.priority == .urgent)
        #expect(o.facts.cents == 1099 && o.facts.balanceCents == 3000 && o.facts.suggestedCents == 1000 && o.facts.otherBank == .ima)
        #expect(o.facts.day == cal.startOfDay(for: nov(27)) && o.facts.merchant == "Spotify")
    }

    @Test func presupuestoQueSeVaDeRitmo() {
        func run(_ spent: Int, day: Int) -> Bool {
            let s = ledger([pay(spent, "Tienda", nov(day, 9))], budgets: Budgets(monthlyCents: 60_000))
            return nyxMoneyObservations(state: s, book: AccountBook(), newMovementIDs: [], moment: .open,
                                        now: nov(day, 12), calendar: cal).contains { $0.id == "budgetOffPace|month|2026-11" }
        }
        #expect(run(25_000, day: 10))
        #expect(!run(15_000, day: 10))
        #expect(!run(25_000, day: 7))
        #expect(!run(50_000, day: 10))
        #expect(run(45_000, day: 20))
        #expect(run(47_000, day: 21))
        #expect(!run(47_900, day: 22))
        #expect(!run(47_000, day: 28))
        #expect(!run(47_000, day: 29))
        // Ventana de días del diseño §6.3: del día 8 al antepenúltimo (`daysInMonth - 2`).
        #expect(!nyxIsBudgetOffPaceDay(7, daysInMonth: 30))
        #expect(nyxIsBudgetOffPaceDay(8, daysInMonth: 30))
        #expect(nyxIsBudgetOffPaceDay(28, daysInMonth: 30))
        #expect(!nyxIsBudgetOffPaceDay(29, daysInMonth: 30))
        #expect(nyxIsBudgetOffPaceDay(29, daysInMonth: 31))
        #expect(!nyxIsBudgetOffPaceDay(30, daysInMonth: 31))
    }

    @Test func masDeLoHabitualSinPresupuesto() {
        let history = [8, 9, 10].flatMap { m in [pay(5000, "La Tasca", date(m, 5)), pay(5000, "La Tasca", date(m, 20))] }
        let overrides: [String: SpendingCategory] = ["la tasca": .comerFuera]
        func run(_ cents: Int, budget: Bool = false) -> Bool {
            let s = ledger(history + [pay(cents, "La Tasca", nov(20, 9))],
                           budgets: budget ? Budgets(byCategory: [.comerFuera: 20_000]) : Budgets(),
                           overrides: overrides)
            return nyxMoneyObservations(state: s, book: AccountBook(), newMovementIDs: [], moment: .open,
                                        now: nov(20, 12), calendar: cal).contains { $0.id == "categoryAboveNormal|comerFuera|2026-11" }
        }
        #expect(run(13_500))
        #expect(!run(12_900))
        #expect(!run(13_500, budget: true))
        let baselines = nyxBaselines(in: ledger(history, overrides: overrides), now: nov(20), calendar: cal)
        #expect(baselines.categoryAverageCents[.comerFuera] == 10_000)
        #expect(baselines.fullMonths == 2)
        #expect(baselines.merchantUsualCents["la tasca"] == 5000)
    }

    @Test func fullMonthsSoloCuentaMesInicialSiEmpiezaElDiaUno() {
        let overrides: [String: SpendingCategory] = ["la tasca": .comerFuera]
        let lateStart = [pay(6000, "La Tasca", date(9, 28)), pay(10_000, "La Tasca", date(10, 15))]
        let lateBaselines = nyxBaselines(in: ledger(lateStart, overrides: overrides), now: nov(20), calendar: cal)
        #expect(lateBaselines.fullMonths == 1)
        #expect(!nyxMoneyObservations(
            state: ledger(lateStart + [pay(15_000, "La Tasca", nov(20, 9))], overrides: overrides),
            book: AccountBook(), newMovementIDs: [], moment: .open, now: nov(20, 12), calendar: cal
        ).contains { $0.situation == .categoryAboveNormal })

        let firstDayStart = [pay(10_000, "La Tasca", date(9, 1)), pay(10_000, "La Tasca", date(10, 15))]
        let firstDayBaselines = nyxBaselines(in: ledger(firstDayStart, overrides: overrides), now: nov(20), calendar: cal)
        #expect(firstDayBaselines.fullMonths == 2)
        #expect(nyxMoneyObservations(
            state: ledger(firstDayStart + [pay(13_500, "La Tasca", nov(20, 9))], overrides: overrides),
            book: AccountBook(), newMovementIDs: [], moment: .open, now: nov(20, 12), calendar: cal
        ).contains { $0.id == "categoryAboveNormal|comerFuera|2026-11" })
    }

    @Test func laMediaSoloUsaMesesCompletosSiElPrimerMesEstaAMedias() {
        // Primer pago el 28 ago (mes a medias, 60 €), sep y oct con 100 €: la media real de meses completos es 100 €.
        let overrides: [String: SpendingCategory] = ["la tasca": .comerFuera]
        let history = [pay(6000, "La Tasca", date(8, 28)), pay(10_000, "La Tasca", date(9, 15)),
                       pay(10_000, "La Tasca", date(10, 15))]
        let baselines = nyxBaselines(in: ledger(history, overrides: overrides), now: nov(20), calendar: cal)
        #expect(baselines.fullMonths == 2)
        #expect(baselines.categoryAverageCents[.comerFuera] == 10_000)
        // 115 € no supera 100 € x 1,3: no sale «Más de lo habitual» (con la media diluida de 86,67 € sí saldría).
        #expect(!nyxMoneyObservations(
            state: ledger(history + [pay(11_500, "La Tasca", nov(20, 9))], overrides: overrides),
            book: AccountBook(), newMovementIDs: [], moment: .open, now: nov(20, 12), calendar: cal
        ).contains { $0.situation == .categoryAboveNormal })
        // 135 € sí la supera.
        #expect(nyxMoneyObservations(
            state: ledger(history + [pay(13_500, "La Tasca", nov(20, 9))], overrides: overrides),
            book: AccountBook(), newMovementIDs: [], moment: .open, now: nov(20, 12), calendar: cal
        ).contains { $0.id == "categoryAboveNormal|comerFuera|2026-11" })
    }

    @Test func comercioSilenciadoYNoEsMioNoObservan() {
        let prior = [pay(2000, "Mercadona", nov(2)), pay(2000, "Mercadona", nov(9)), pay(2000, "Mercadona", nov(16))]
        let new = pay(7000, "Mercadona", nov(26, 10))
        let muted = ledger(prior + [new], muted: ["mercadona"])
        #expect(nyxMoneyObservations(state: muted, book: AccountBook(), newMovementIDs: [new.id], moment: .notice,
                                     now: nov(26, 10, 1), calendar: cal).allSatisfy { $0.situation != .unusualPayment })
        var notMine = new
        notMine.flaggedNotMine = true
        let flagged = ledger(prior + [notMine])
        #expect(nyxMoneyObservations(state: flagged, book: AccountBook(), newMovementIDs: [notMine.id], moment: .notice,
                                     now: nov(26, 10, 1), calendar: cal).allSatisfy { $0.situation != .unusualPayment })
    }
}
