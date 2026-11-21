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

private func pay(_ cents: Int, _ merchant: String?, _ when: Date, bank: BankID = .rev, isShop: Bool = true,
                 ownTransfer: Bool? = nil) -> Movement {
    Movement(bank: bank, amountCents: -cents, merchant: merchant, kind: .payment, source: .notification, date: when,
             isShop: isShop, ownTransfer: ownTransfer)
}

private let defaultBudgets = Budgets(monthlyCents: 70000, byCategory: [.comerFuera: 12000])

private func state(_ movements: [Movement], budgets: Budgets = defaultBudgets) -> LedgerState {
    LedgerState(movements: movements, budgets: budgets)
}

private func budgetAlerts(_ alerts: [Insight]) -> [Insight] {
    alerts.filter { $0.kind == .budgetWarning || $0.kind == .budgetExceeded }
}

@Suite struct BudgetTests {
    @Test func estados() {
        let s = state([pay(9620, "Glovo", nov(10)), pay(30000, "Mercadona", nov(12))])
        let out = budgetStatuses(in: s, month: nov(19), now: nov(19, 13), calendar: cal)
        #expect(out.map(\.id) == ["month", "cat-comerFuera"])
        #expect(out[0].spentCents == 39620 && out[0].percent == 56 && out[0].level == .ok)
        #expect(out[1].spentCents == 9620 && out[1].percent == 80 && out[1].level == .warning && out[1].remainingCents == 2380)
        #expect(BudgetStatus(scope: .month, limitCents: 1000, spentCents: 1000).level == .exceeded)
        #expect(BudgetStatus(scope: .month, limitCents: 1000, spentCents: 1500).remainingCents == 0)
    }

    @Test func sinPresupuestosNoHayEstados() {
        let s = state([pay(9620, "Glovo", nov(10))], budgets: Budgets())
        #expect(budgetStatuses(in: s, month: nov(19), now: nov(19, 13), calendar: cal).isEmpty)
    }

    @Test func avisoAl80() {
        let before = pay(9000, "Glovo", nov(10))
        let stored = pay(1000, "Glovo", nov(19, 12, 30))
        let alerts = budgetAlerts(immediateAlerts(afterStoring: stored, in: state([before, stored]), now: nov(19, 13), calendar: cal))
        #expect(alerts.count == 1)
        #expect(alerts[0].kind == .budgetWarning)
        #expect(alerts[0].title == "Llevas el 83\u{00A0}% de tu presupuesto de Comer fuera")
        #expect(alerts[0].detail == "Te quedan 20,00\u{00A0}€ para lo que queda de mes")
    }

    @Test func avisoAl100() {
        let a = pay(9000, "Glovo", nov(10))
        let b = pay(1000, "Glovo", nov(19, 12, 30))
        let stored = pay(2540, "Glovo", nov(19, 12, 45))
        let alerts = budgetAlerts(immediateAlerts(afterStoring: stored, in: state([a, b, stored]), now: nov(19, 13), calendar: cal))
        #expect(alerts.count == 1)
        #expect(alerts[0].kind == .budgetExceeded)
        #expect(alerts[0].title == "Te has pasado del presupuesto de Comer fuera")
        #expect(alerts[0].detail == "Llevas 125,40\u{00A0}€ de 120,00\u{00A0}€")
    }

    @Test func saltoDirectoAlCientoSoloAvisaUnaVez() {
        let a = pay(9000, "Glovo", nov(10))
        let stored = pay(4200, "Glovo", nov(19, 12, 30))
        let alerts = budgetAlerts(immediateAlerts(afterStoring: stored, in: state([a, stored]), now: nov(19, 13), calendar: cal))
        #expect(alerts.count == 1)
        #expect(alerts[0].kind == .budgetExceeded)
    }

    @Test func sinAvisoSiYaEstabaPorEncima() {
        let a = pay(9000, "Glovo", nov(10))
        let b = pay(4200, "Glovo", nov(11))
        let stored = pay(500, "Glovo", nov(19, 12, 30))
        #expect(budgetAlerts(immediateAlerts(afterStoring: stored, in: state([a, b, stored]), now: nov(19, 13), calendar: cal)).isEmpty)
    }

    @Test func presupuestoDelMes() {
        let monthOnly = Budgets(monthlyCents: 70000)
        let base = pay(55000, "Mercadona", nov(5))
        let first = pay(1700, "Mercadona", nov(19, 12, 30))
        let warn = budgetAlerts(immediateAlerts(afterStoring: first, in: state([base, first], budgets: monthOnly),
                                                now: nov(19, 13), calendar: cal))
        #expect(warn.count == 1)
        #expect(warn[0].kind == .budgetWarning)
        #expect(warn[0].title == "Llevas el 81\u{00A0}% de tu presupuesto del mes")
        #expect(warn[0].detail == "Te quedan 133,00\u{00A0}€ para lo que queda de mes")

        let second = pay(14000, "Mercadona", nov(19, 12, 45))
        let over = budgetAlerts(immediateAlerts(afterStoring: second, in: state([base, first, second], budgets: monthOnly),
                                                now: nov(19, 13), calendar: cal))
        #expect(over.count == 1)
        #expect(over[0].kind == .budgetExceeded)
        #expect(over[0].title == "Te has pasado del presupuesto del mes")
        #expect(over[0].detail == "Llevas 707,00\u{00A0}€ de 700,00\u{00A0}€")
    }

    @Test func sinAvisoSiApagado() {
        let a = pay(9000, "Glovo", nov(10))
        let stored = pay(4200, "Glovo", nov(19, 12, 30))
        var s = state([a, stored])
        s.alertSettings.budgets = false
        #expect(budgetAlerts(immediateAlerts(afterStoring: stored, in: s, now: nov(19, 13), calendar: cal)).isEmpty)
        #expect(budgetAlerts(insights(for: s, now: nov(19, 13), calendar: cal)).isEmpty)
    }

    @Test func sinAvisoParaTraspasos() {
        let a = pay(9000, "Glovo", nov(10))
        let stored = pay(4200, "Glovo", nov(19, 12, 30), ownTransfer: true)
        #expect(budgetAlerts(immediateAlerts(afterStoring: stored, in: state([a, stored]), now: nov(19, 13), calendar: cal)).isEmpty)
    }

    @Test func feed() {
        let near = state([pay(9620, "Glovo", nov(10))])
        let warnings = budgetAlerts(insights(for: near, now: nov(19, 13), calendar: cal))
        #expect(warnings.count == 1)
        #expect(warnings[0].kind == .budgetWarning)
        let calm = state([pay(1000, "Glovo", nov(10)), pay(3000, "Mercadona", nov(11))])
        #expect(budgetAlerts(insights(for: calm, now: nov(19, 13), calendar: cal)).isEmpty)
        let over = state([pay(13000, "Glovo", nov(10))])
        #expect(budgetAlerts(insights(for: over, now: nov(19, 13), calendar: cal)).map(\.kind) == [.budgetExceeded])
    }

    private func subscriptionBook() -> LedgerState {
        LedgerState(movements: [
            pay(1399, "Netflix", date(10, 5)), pay(1399, "Netflix", nov(5)),
            pay(1099, "Spotify", date(10, 20)), pay(1099, "Spotify", date(9, 20)),
        ])
    }

    @Test func suscripcionOculta() {
        var ledger = Ledger(state: subscriptionBook())
        let now = nov(19, 13)
        let all = activeSubscriptions(in: ledger.state, now: now, calendar: cal)
        #expect(Set(all.map(\.id)) == [normalizeMerchant("Netflix"), normalizeMerchant("Spotify")])
        // Netflix se cobra en menos de una semana (5 dic); se prueba con una fecha cercana.
        let feedNow = date(12, 3, 12)
        #expect(insights(for: ledger.state, now: feedNow, calendar: cal).contains {
            $0.kind == .subscriptionUpcoming && $0.merchant == "Netflix"
        })
        ledger.setSubscriptionDismissed(true, id: "rev|netflix")
        #expect(activeSubscriptions(in: ledger.state, now: now, calendar: cal).map(\.id) == [normalizeMerchant("Spotify")])
        #expect(!insights(for: ledger.state, now: feedNow, calendar: cal).contains {
            $0.kind == .subscriptionUpcoming && $0.merchant == "Netflix"
        })
        ledger.setSubscriptionDismissed(false, id: "rev|netflix")
        #expect(activeSubscriptions(in: ledger.state, now: now, calendar: cal).count == 2)

        let spotify = Subscription(id: "spotify", merchant: "Spotify", bank: .rev, amountCents: 1099, previousAmountCents: nil,
                                   lastDate: nov(1), nextDate: date(12, 1))
        let netflix = Subscription(id: "netflix", merchant: "Netflix", bank: .rev, amountCents: 1399, previousAmountCents: nil,
                                   lastDate: nov(5), nextDate: date(12, 5))
        let totals = subscriptionTotals([spotify, netflix])
        #expect(totals.monthlyCents == 2498 && totals.yearlyCents == 29976)
    }

    @Test func ocultaCambiaCategoria() {
        var ledger = Ledger(state: LedgerState(movements: [
            pay(3000, "Gimnasio Fit", date(10, 3)), pay(3000, "Gimnasio Fit", nov(3)),
        ]))
        let now = nov(19, 13)
        let gym = ledger.state.movements[1]
        let keys = subscriptionKeys(in: ledger.state, now: now, calendar: cal)
        #expect(categoryOf(gym, in: ledger.state, subscriptionKeys: keys) == .suscripciones)
        ledger.setSubscriptionDismissed(true, id: "rev|" + normalizeMerchant("Gimnasio Fit"))
        let after = subscriptionKeys(in: ledger.state, now: now, calendar: cal)
        #expect(categoryOf(gym, in: ledger.state, subscriptionKeys: after) == .ocio)
    }

    @Test func mutaciones() {
        var ledger = Ledger(state: LedgerState())
        ledger.setMonthlyBudget(70000)
        ledger.setBudget(12000, for: .comerFuera)
        #expect(ledger.state.budgets == defaultBudgets)
        ledger.setMonthlyBudget(0)
        ledger.setBudget(-5, for: .comerFuera)
        #expect(ledger.state.budgets == Budgets())
        ledger.setMonthlyBudget(500)
        ledger.setMonthlyBudget(nil)
        #expect(ledger.state.budgets.monthlyCents == nil)
    }

    @Test func leeLibrosAntiguos() throws {
        let json = """
        {"balances":[],"movements":[],"unread":[],"alertSettings":{"everyMovement":true}}
        """
        let decoded = try JSONDecoder().decode(LedgerState.self, from: Data(json.utf8))
        #expect(decoded.budgets == Budgets())
        #expect(decoded.dismissedSubscriptions.isEmpty)
        #expect(decoded.alertSettings.budgets)
        let bare = try JSONDecoder().decode(LedgerState.self, from: Data(#"{"balances":[],"movements":[],"unread":[]}"#.utf8))
        #expect(bare.alertSettings.budgets)
    }

    @Test func viajaIdaYVuelta() throws {
        var s = state([])
        s.dismissedSubscriptions = ["rev|netflix"]
        let again = try JSONDecoder().decode(LedgerState.self, from: JSONEncoder().encode(s))
        #expect(again == s)
    }
}

/// R32: qué hace el texto de un campo de presupuesto.
@Suite struct BudgetInputTests {
    @Test(arguments: ["", " ", "€", " €", "\u{00A0}€", ","])
    func unTextoSinCifrasQuitaElLimite(_ text: String) {
        #expect(parseBudgetInput(text) == .remove)
    }

    @Test func cerosQuitanYImportesFijan() {
        #expect(parseBudgetInput("0") == .remove)
        #expect(parseBudgetInput("0,00 €") == .remove)
        #expect(parseBudgetInput("120") == .set(12_000))
        #expect(parseBudgetInput("120,00 €") == .set(12_000))
        #expect(parseBudgetInput("700,00\u{00A0}€") == .set(70_000))
    }

    @Test func loQueNoSeEntiendeSigueSiendoInvalido() {
        for text in ["abc", "-", "-5", "12,345", "1a"] {
            #expect(parseBudgetInput(text) == .invalid, "\(text)")
        }
    }
}
