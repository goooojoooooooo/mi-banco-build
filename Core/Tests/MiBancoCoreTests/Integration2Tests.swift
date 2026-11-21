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

    /// R22: volver a lo automático en un pago con elección propia quita solo esa; la del comercio no se toca.
    @Test func volverALaCategoriaAutomaticaQuitaSoloLaDelPago() {
        let a = pay(1_250, "Mercadona", at(11, 10))
        let b = pay(900, "Mercadona", at(11, 12))
        var ledger = Ledger(state: LedgerState(movements: [a, b]))
        ledger.setCategory(.casa, for: a.id, applyToMerchant: true)
        ledger.setCategory(.ocio, for: b.id, applyToMerchant: false)
        let keys = Set<String>()
        #expect(categoryOf(ledger.state.movements[1], in: ledger.state, subscriptionKeys: keys) == .ocio)
        #expect(ledger.hasOwnCategory(b.id))
        ledger.resetCategoryToAutomatic(for: b.id)
        #expect(categoryOf(ledger.state.movements[0], in: ledger.state, subscriptionKeys: keys) == .casa)
        #expect(categoryOf(ledger.state.movements[1], in: ledger.state, subscriptionKeys: keys) == .casa)
        #expect(!ledger.hasOwnCategory(b.id))
        #expect(ledger.hasChosenCategory(b.id))
    }

    /// R22: sin elección propia, el botón quita la del comercio y todos vuelven a lo automático.
    @Test func volverALaCategoriaAutomaticaSinEleccionPropiaQuitaLaDelComercio() {
        let a = pay(1_250, "Mercadona", at(11, 10))
        let b = pay(900, "Mercadona", at(11, 12))
        var ledger = Ledger(state: LedgerState(movements: [a, b]))
        ledger.setCategory(.casa, for: a.id, applyToMerchant: true)
        #expect(!ledger.hasOwnCategory(a.id))
        #expect(ledger.hasChosenCategory(a.id))
        ledger.resetCategoryToAutomatic(for: a.id)
        let keys = Set<String>()
        #expect(categoryOf(ledger.state.movements[0], in: ledger.state, subscriptionKeys: keys) == .supermercado)
        #expect(categoryOf(ledger.state.movements[1], in: ledger.state, subscriptionKeys: keys) == .supermercado)
        #expect(!ledger.hasChosenCategory(a.id) && !ledger.hasChosenCategory(b.id))
    }

    // MARK: R23 — las filas de solo día cuentan desde el inicio de su día

    private func bankDay(_ cents: Int, _ merchant: String, _ month: Int, _ day: Int) -> Movement {
        Movement(bank: .rev, amountCents: -cents, merchant: merchant, kind: .payment, source: .bank, date: at(month, day, 12),
                 importedAt: at(month, day, 6), dayOnly: true)
    }

    @Test func r23FilaDeSoloDiaDeHoyCuentaAntesDeLasDoce() {
        let state = LedgerState(movements: [
            pay(1_000, "Mercadona", at(11, 8)),
            pay(2_000, "Mercadona", at(10, 8)),
            bankDay(6_000, "Endesa", 11, 19),
        ])
        for hour in [9, 13] {
            let now = at(11, 19, hour)
            let month = monthSpending(in: state, month: now, now: now, calendar: cal)
            #expect(month.totalCents == 7_000)
            #expect(month.byCategory.reduce(0) { $0 + $1.count } == 2)
            var budgeted = state
            budgeted.budgets = Budgets(monthlyCents: 50_000)
            #expect(budgetStatuses(in: budgeted, month: now, now: now, calendar: cal).first?.spentCents == 7_000)
            let listed = month.byCategory.reduce(0) {
                $0 + spendingMovements(in: state, category: $1.category, month: now, now: now, calendar: cal).count
            }
            #expect(listed == 2)
            #expect(spendingPace(movements: state.movements, now: now, calendar: cal)?.thisMonthCents == 7_000)
            #expect(merchantHistory(for: "Endesa", in: state.movements, now: now, calendar: cal).totalThisMonthCents == 6_000)
            #expect(merchantHistories(in: state.movements, now: now, calendar: cal)["endesa"]?.totalThisMonthCents == 6_000)
        }
    }

    @Test func r23SoloUnaFilaDeHoyEs6000EnElMes() {
        let state = LedgerState(movements: [bankDay(6_000, "Endesa", 11, 19)])
        let now = at(11, 19, 9)
        #expect(monthSpending(in: state, month: now, now: now, calendar: cal).totalCents == 6_000)
        #expect(monthSpending(in: state, month: now, now: now, calendar: cal).byCategory.count == 1)
    }

    @Test func r23LaPrevisionUsaLaFilaDeHoy() {
        let state = LedgerState(movements: [bankDay(6_000, "Endesa", 11, 19)])
        let now = at(11, 19, 9)
        let forecast = monthForecast(in: state, now: now, calendar: cal)
        #expect(forecast?.spentCents == 6_000)
        // 6 000 en 19 días, 11 por delante (30 días en noviembre): 6 000 + 6 000 * 11 / 19.
        #expect(forecast?.projectedCents == 6_000 + 6_000 * 11 / 19)
    }

    @Test func r23FilaDeMananaSigueFueraALasVeintitresCincuentaYNueve() {
        let state = LedgerState(movements: [bankDay(6_000, "Endesa", 11, 20)])
        let now = at(11, 19, 23, 59)
        #expect(monthSpending(in: state, month: now, now: now, calendar: cal).totalCents == 0)
        #expect(spendingPace(movements: state.movements, now: now, calendar: cal) == nil
                || spendingPace(movements: state.movements, now: now, calendar: cal)?.thisMonthCents == 0)
        #expect(monthForecast(in: state, now: now, calendar: cal)?.spentCents == 0)
        // Y entra al empezar su día.
        let next = at(11, 20, 0, 5)
        #expect(monthSpending(in: state, month: next, now: next, calendar: cal).totalCents == 6_000)
    }

    @Test func r23DiaUnoDelMesAMedianoche() {
        let state = LedgerState(movements: [bankDay(6_000, "Endesa", 11, 1), bankDay(900, "Bar", 10, 1)])
        let now = at(11, 1, 0, 30)
        let month = monthSpending(in: state, month: now, now: now, calendar: cal)
        #expect(month.totalCents == 6_000)
        // Frente al día 1 entero del mes anterior (R19).
        #expect(month.previousTotalCents == 900)
        #expect(spendingPace(movements: state.movements, now: now, calendar: cal)?.thisMonthCents == 6_000)
    }

    // MARK: R27 (20) — R19 en el día 1, al final de marzo frente a febrero y en el cambio de hora

    @Test func r19DiaUnoCompruebaElDiaUnoEnteroDelMesAnterior() {
        let state = LedgerState(movements: [
            pay(1_000, "Mercadona", at(10, 1, 8)),
            pay(2_000, "Mercadona", at(10, 1, 23, 50)),
            pay(4_000, "Mercadona", at(10, 2, 0, 10)),
        ])
        let now = at(11, 1, 0, 5)
        #expect(monthSpending(in: state, month: now, now: now, calendar: cal).previousTotalCents == 3_000)
        #expect(spendingPace(movements: state.movements, now: now, calendar: cal)?.lastMonthSamePointCents == 3_000)
    }

    @Test func r19FinalDeMarzoComparaConFebreroEntero() {
        func march(_ day: Int, _ hour: Int = 12) -> Date {
            cal.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))!
        }
        func feb(_ day: Int, _ hour: Int = 12) -> Date {
            cal.date(from: DateComponents(year: 2026, month: 2, day: day, hour: hour))!
        }
        let state = LedgerState(movements: [
            pay(1_000, "Mercadona", feb(10)),
            pay(2_000, "Mercadona", feb(28, 23)),
            pay(500, "Mercadona", march(1)),
        ])
        for day in [29, 30, 31] {
            let now = march(day, 9)
            #expect(monthSpending(in: state, month: now, now: now, calendar: cal).previousTotalCents == 3_000)
            #expect(spendingPace(movements: state.movements, now: now, calendar: cal)?.lastMonthSamePointCents == 3_000)
        }
    }

    @Test func r19DiaDelCambioDeHoraCuentaEntero() {
        // 25 de octubre de 2026: el día de 25 horas (acaba el horario de verano). Sus pagos cuentan enteros.
        func oct(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
        }
        let state = LedgerState(movements: [
            pay(1_000, "Mercadona", oct(25, 0, 30)),
            pay(2_000, "Mercadona", oct(25, 23, 45)),
            pay(4_000, "Mercadona", oct(26, 0, 10)),
        ])
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 8))!
        #expect(monthSpending(in: state, month: now, now: now, calendar: cal).previousTotalCents == 3_000)
        #expect(spendingPace(movements: state.movements, now: now, calendar: cal)?.lastMonthSamePointCents == 3_000)
    }
}
