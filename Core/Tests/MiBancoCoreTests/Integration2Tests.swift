import Foundation
import Testing
@testable import MiBancoCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Madrid")!
    c.locale = Locale(identifier: "es_ES")
    return c
}()

private func at(_ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}

private func pay(_ cents: Int, _ merchant: String, _ when: Date, bank: BankID = .rev) -> Movement {
    Movement(bank: bank, amountCents: -cents, merchant: merchant, kind: .payment, source: .notification, date: when, isShop: true)
}

private func income(_ cents: Int, _ merchant: String, _ when: Date, bank: BankID = .ima) -> Movement {
    Movement(bank: bank, amountCents: cents, merchant: merchant, kind: .income, source: .notification, date: when)
}

/// Integración 2 (pantallas de Plan 3 sobre la línea principal): R19, R21 y las firmas `notSpending:`.
@Suite struct Integration2Tests {
    // MARK: R19 — el corte del mes anterior es el final del mismo día

    @Test func r19LaComparacionNoCambiaConLaHoraDelDia() {
        let state = LedgerState(movements: [
            pay(1_000, "Mercadona", at(10, 19, 8)),
            pay(2_000, "Mercadona", at(10, 19, 22)),
            pay(4_000, "Mercadona", at(10, 20, 0, 30)),
            pay(500, "Mercadona", at(11, 3)),
        ])
        for hour in [0, 9, 13, 23] {
            let now = at(11, 19, hour, 1)
            let month = monthSpending(in: state, month: now, now: now, calendar: cal)
            #expect(month.previousTotalCents == 3_000)
            #expect(month.byCategory.first?.previousCents == 3_000)
            #expect(spendingPace(movements: state.movements, now: now, calendar: cal)?.lastMonthSamePointCents == 3_000)
        }
    }

    @Test func r19DiaAjustadoAlMesMasCortoYMesesPasadosEnteros() {
        let state = LedgerState(movements: [
            pay(1_000, "Mercadona", at(11, 30, 23, 30)),
            pay(700, "Mercadona", at(12, 2)),
        ])
        // 31 de diciembre: noviembre entero (su día 30 completo).
        let now = at(12, 31, 9)
        #expect(monthSpending(in: state, month: now, now: now, calendar: cal).previousTotalCents == 1_000)
        // Un mes pasado se compara siempre entero, sea la hora que sea.
        let past = monthSpending(in: state, month: at(12, 15), now: cal.date(byAdding: .month, value: 1, to: now)!, calendar: cal)
        #expect(past.previousTotalCents == 1_000)
    }

    // MARK: R21 — importes escritos a mano

    @Test func r21LeeLosImportesEscritosAMano() {
        #expect(parseBalanceInput("1.234,5") == 123_450)
        #expect(parseBalanceInput("120.5") == 12_050)
        #expect(parseBalanceInput("") == nil)
        #expect(parseBalanceInput("0") == 0)
        #expect(parseBalanceInput("-5") == -500)
        #expect(parseBalanceInput("12345678901") == nil)
        #expect(parseBalanceInput("1.234.567.890") == nil)
        #expect(parseBalanceInput("abc") == nil)
    }

    // MARK: R21 — presupuesto justo en el límite

    @Test func r21PresupuestoJustoEnElLimiteEstaSuperado() {
        let state = LedgerState(movements: [pay(9_000, "Restaurante Lateral", at(11, 10))],
                                budgets: Budgets(monthlyCents: nil, byCategory: [.comerFuera: 9_000]))
        let now = at(11, 19)
        let status = budgetStatuses(in: state, month: now, now: now, calendar: cal).first { $0.scope == .category(.comerFuera) }
        #expect(status?.spentCents == 9_000)
        #expect(status?.percent == 100)
        #expect(status?.level == .exceeded)
    }

    // MARK: R21 — la clave de una suscripción oculta es la que guarda la app

    @Test func r21LaClaveDeLaSuscripcionOcultaEsLaDeLaApp() throws {
        var ledger = Ledger(state: LedgerState(movements: [
            pay(1_399, "Netflix", at(9, 23)), pay(1_399, "Netflix", at(10, 23)),
            pay(1_099, "Spotify", at(9, 20), bank: .ima), pay(1_099, "Spotify", at(10, 20), bank: .ima),
        ]))
        let now = at(11, 19)
        let detected = detectSubscriptions(in: ledger.state.movements, now: now, calendar: cal)
        let spotify = try #require(detected.first { $0.merchant == "Spotify" })
        // La app guarda «<banco>|<clave>» (LedgerSnapshot.SubscriptionRow.id) al tocar «Esto no es una suscripción».
        ledger.setSubscriptionDismissed(true, id: "\(spotify.bank.rawValue)|\(spotify.id)")
        #expect(activeSubscriptions(in: ledger.state, now: now, calendar: cal).map(\.merchant) == ["Netflix"])
    }

    // MARK: Una sola pasada de emparejado

    @Test func exclusionesConLosTraspasosYaCalculados() {
        let state = LedgerState(movements: [
            // Un traspaso nunca es una compra en tienda (`isShop` falso).
            Movement(bank: .rev, amountCents: -20_000, merchant: "Transferencia a imagin", kind: .payment,
                     source: .notification, date: at(11, 15, 10)),
            income(20_000, "Transferencia de Revolut", at(11, 15, 10, 5)),
            pay(1_250, "Mercadona", at(11, 16)),
        ])
        let now = at(11, 19)
        let transfers = ownTransferIDs(in: state.movements)
        #expect(transfers.count == 2)
        #expect(spendingExclusions(in: state, now: now, ownTransfers: transfers) == spendingExclusions(in: state, now: now))
        let average = averageMonthlySpendingByCategory(in: state, before: at(12, 1), months: 1, calendar: cal,
                                                       notSpending: spendingExclusions(in: state, now: now))
        #expect(average?.total == 1_250)
    }

    // MARK: Tarea 8 — la categoría en la hoja del movimiento

    @Test func conceptosGenericosNoAplicanATodoPorDefecto() {
        #expect(isGenericPayee("Bizum a Ana"))
        #expect(isGenericPayee("TRANSFERENCIA ENVIADA"))
        #expect(isGenericPayee("Devolución"))
        #expect(isGenericPayee("Recibo luz"))
        #expect(!isGenericPayee("Mercadona"))
        #expect(!isGenericPayee("Pagoda Sushi"))
        #expect(!isGenericPayee(nil))
    }

    @Test func volverALaCategoriaAutomatica() {
        let a = pay(1_250, "Mercadona", at(11, 10))
        let b = pay(900, "Mercadona", at(11, 12))
        var ledger = Ledger(state: LedgerState(movements: [a, b]))
        #expect(!ledger.hasChosenCategory(a.id))
        // Para todo el comercio, y luego otra solo para b.
        ledger.setCategory(.ocio, for: a.id, applyToMerchant: true)
        ledger.setCategory(.casa, for: b.id, applyToMerchant: false)
        #expect(ledger.hasChosenCategory(a.id) && ledger.hasChosenCategory(b.id))
        ledger.resetCategoryToAutomatic(for: a.id)
        #expect(!ledger.hasChosenCategory(a.id))
        let keys = Set<String>()
        #expect(categoryOf(ledger.state.movements[0], in: ledger.state, subscriptionKeys: keys) == .supermercado)
        // Lo elegido a mano en b se queda.
        #expect(categoryOf(ledger.state.movements[1], in: ledger.state, subscriptionKeys: keys) == .casa)
    }
}
