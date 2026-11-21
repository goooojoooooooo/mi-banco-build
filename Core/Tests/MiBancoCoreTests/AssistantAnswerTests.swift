import Foundation
import Testing
@testable import MiBancoCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Madrid")!
    c.locale = Locale(identifier: "es_ES")
    return c
}()

private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 10, _ minute: Int = 0) -> Date {
    cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private func nov(_ day: Int, _ hour: Int = 10, _ minute: Int = 0) -> Date {
    at(2026, 11, day, hour, minute)
}

private func nb(_ s: String) -> String {
    s.replacingOccurrences(of: " €", with: "\u{00A0}€").replacingOccurrences(of: " %", with: "\u{00A0}%")
}

private func richFixture() -> (state: LedgerState, portfolio: Portfolio, book: AccountBook, now: Date) {
    let now = nov(20, 10, 0)
    var state = LedgerState()
    state.balances[.rev] = ManualBalance(cents: 34_020, setAt: nov(20, 8), origin: .bank)
    state.balances[.ima] = ManualBalance(cents: 128_455, setAt: nov(20, 8), origin: .manual)
    state.balances[.tr] = ManualBalance(cents: 215_000, setAt: nov(20, 8), origin: .manual)
    state.budgets = Budgets(monthlyCents: 30_000, byCategory: [.comerFuera: 4_000, .supermercado: 20_000])

    state.movements = [
        // Octubre (mes anterior)
        Movement(bank: .rev, amountCents: -1_099, merchant: "Spotify", kind: .payment, source: .bank,
                 date: at(2026, 9, 22, 12), isShop: true, bankRef: "s1", bankStatus: .booked),
        Movement(bank: .rev, amountCents: -1_099, merchant: "Spotify", kind: .payment, source: .bank,
                 date: at(2026, 10, 22, 12), isShop: true, bankRef: "s2", bankStatus: .booked),
        Movement(bank: .rev, amountCents: -5_000, merchant: "Mercadona", kind: .payment, source: .bank,
                 date: at(2026, 10, 10, 12), isShop: true, bankRef: "o1", bankStatus: .booked),
        Movement(bank: .ima, amountCents: 180_000, merchant: "Nómina ACME", kind: .income, source: .bank,
                 date: at(2026, 9, 28, 9), bankRef: "n1", bankStatus: .booked),
        Movement(bank: .ima, amountCents: 180_000, merchant: "Nómina ACME", kind: .income, source: .bank,
                 date: at(2026, 10, 28, 9), bankRef: "n2", bankStatus: .booked),
        // Noviembre (mes en curso)
        Movement(bank: .rev, amountCents: -4_250, merchant: "Mercadona Torrejón", kind: .payment, source: .bank,
                 date: nov(5, 18), isShop: true, bankRef: "m1", bankStatus: .booked),
        Movement(bank: .rev, amountCents: -3_100, merchant: "Mercadona Alcalá", kind: .payment, source: .bank,
                 date: nov(15, 19), isShop: true, bankRef: "m2", bankStatus: .booked),
        Movement(bank: .rev, amountCents: -4_995, merchant: "Zara", kind: .payment, source: .bank,
                 date: nov(19, 23, 5), isShop: true, bankRef: "m3", bankStatus: .booked),
        Movement(bank: .rev, amountCents: -4_500, merchant: "Restaurante Sol", kind: .payment, source: .bank,
                 date: nov(12, 21), isShop: true, bankRef: "m4", bankStatus: .booked),
        Movement(bank: .ima, amountCents: 185_000, merchant: "Nómina ACME", kind: .income, source: .bank,
                 date: nov(20, 6, 5), bankRef: "n3", bankStatus: .booked),
        // Traspaso propio (no debe contar ni como gasto ni como ingreso)
        Movement(bank: .ima, amountCents: -20_000, merchant: "Transferencia a Revolut", kind: .payment, source: .bank,
                 date: nov(20, 7, 49), isShop: false, bankRef: "t1", bankStatus: .booked),
        Movement(bank: .rev, amountCents: 20_000, merchant: "Transferencia de imagin", kind: .income, source: .bank,
                 date: nov(20, 7, 50), bankRef: "t2", bankStatus: .booked),
        // Excluidos (no es mío + compra de valores + 0 €)
        Movement(bank: .rev, amountCents: -9_999, merchant: "Mercadona", kind: .payment, source: .notification,
                 date: nov(16, 12), isShop: true, flaggedNotMine: true),
        Movement(bank: .tr, amountCents: -50_000, merchant: "Compra Apple", kind: .payment, source: .statement,
                 date: nov(14, 10), excludedFromSpending: true),
        Movement(bank: .rev, amountCents: 0, merchant: "Mercadona", kind: .payment, source: .notification,
                 date: nov(17, 10), isShop: true),
    ]

    var portfolio = Portfolio()
    portfolio.transactions = [
        InvestmentTransaction(id: "tx-1", date: at(2026, 3, 2, 9), instrument: "IE00B4L5Y983",
                              name: "iShares Core MSCI World (Acc)", assetClass: "FUND",
                              shares: 8, cashCents: -77_067, priceEUR: 96),
        InvestmentTransaction(id: "tx-2", date: at(2026, 6, 15, 13), instrument: "US0378331005",
                              name: "Apple", assetClass: "STOCK",
                              shares: 3, cashCents: -54_100, priceEUR: 180),
        InvestmentTransaction(id: "tx-3", date: at(2026, 7, 1, 10), instrument: "ETH",
                              name: "Ethereum", assetClass: "CRYPTO",
                              shares: Decimal(string: "0.01")!, cashCents: 0, priceEUR: nil, acquired: true),
    ]
    portfolio.quotes["IE00B4L5Y983"] = Quote(priceEUR: 110, previousCloseEUR: Decimal(string: "108.5")!,
                                             fetchedAt: nov(20, 9, 30), marketTime: nov(20, 9, 25))
    portfolio.quotes["US0378331005"] = Quote(priceEUR: 200, previousCloseEUR: 202,
                                             fetchedAt: nov(20, 9, 30), marketTime: nov(20, 9, 25))
    portfolio.manualPrices["ETH"] = ManualPrice(priceEUR: 3_000, setAt: nov(19, 9))

    var book = AccountBook()
    book.floors[.rev] = 5_000

    return (state, portfolio, book, now)
}

private func plainLines(_ answer: AssistantAnswer) -> [String] {
    answer.lines.map { render($0.parts, .plain) }
}

@Suite struct AssistantAnswerTests {
    @Test func saldosTotalesYPorBanco() {
        let fx = richFixture()
        let all = answerQuestion("¿Cuánto tengo?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(all) == [
            nb("En total tienes unos 3.774,75 €."),
            nb("Revolut: 340,20 €"),
            nb("imagin: unos 1.284,55 €"),
            nb("Trade Republic: unos 2.150,00 €"),
        ])

        let one = answerQuestion("¿Cuánto tengo en Revolut?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(one) == [nb("En Revolut tienes 340,20 €.")])

        // Si falta un banco conectado, el total lo dice honestamente.
        var partial = fx.state
        partial.balances[.ima] = nil
        partial.links[.ima] = BankLinkInfo(connectedAt: at(2026, 10, 1), consentValidUntil: at(2026, 12, 31))
        let partialAns = answerQuestion("¿Cuánto tengo?", state: partial, portfolio: nil, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(partialAns)[0] == nb("En total tienes unos 2.490,20 €, sin contar imagin."))
        #expect(plainLines(partialAns).contains("imagin: aún sin saldo"))

        let missingOne = answerQuestion("¿Cuánto tengo en imagin?", state: partial, portfolio: nil, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(missingOne) == ["Aún no tengo el saldo de imagin."])
    }

    @Test func gastosMesCategoriaComercioYBancoRespetanExclusiones() {
        let fx = richFixture()
        // I3 #7: Mercadona Torrejón + Mercadona Alcalá -> usa «Mercadona» (no la última tienda concreta).
        let mercadona = answerQuestion("¿Cuánto llevo en Mercadona?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(mercadona)[0] == nb("Este mes llevas 73,50 € en Mercadona (2 pagos)."))
        #expect(mercadona.lines[1].action != nil)

        // I7 #3: Categoría Supermercado tampoco cuenta el pago de 0 € (2 pagos, igual que Mercadona).
        let superCat = answerQuestion("¿Cuánto llevo en Supermercado?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(superCat)[0] == nb("Este mes llevas 73,50 € en Supermercado (2 pagos)."))

        // I3 #5: Gasto filtrado por banco (en imagin solo hubo traspaso de 200 €, que NO es gasto -> 0 gastos).
        let spendIma = answerQuestion("¿Cuánto gasté en imagin este mes?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(spendIma) == ["Este mes aún no tienes gastos registrados en imagin."])
        let spendRev = answerQuestion("¿Cuánto gasté en Revolut este mes?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(spendRev)[0] == nb("Este mes llevas 168,45 € gastados en Revolut."))

        // Comercio sin pagos -> respuesta honesta.
        let emptyMerchant = answerQuestion("¿Cuánto llevo en Lidl?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(emptyMerchant) == ["Este mes no tienes pagos en Lidl."])

        // Categoría Comer fuera: 45,00 €
        let cat = answerQuestion("¿Cuánto llevo en Comer fuera?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(cat)[0] == nb("Este mes llevas 45,00 € en Comer fuera (1 pago)."))

        // Total del mes: 42,50 + 31,00 + 49,95 + 45,00 = 168,45 €
        let total = answerQuestion("¿Cuánto llevo gastado este mes?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(total)[0].hasPrefix(nb("Este mes llevas 168,45 € gastados")))
        #expect(plainLines(total).contains(nb("Donde más: Supermercado (73,50 €).")))

        // Mes pasado (octubre): 50,00 Mercadona + 10,99 Spotify = 60,99 €
        let last = answerQuestion("¿Cuánto gasté el mes pasado?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(last)[0] == nb("El mes pasado gastaste 60,99 €."))

        // Mes futuro: honesto.
        let future = answerIntent(.spending(month: .specific(year: 2027, month: 1), category: nil, merchant: nil),
                                  state: fx.state, portfolio: nil, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(future) == ["Aún no ha llegado enero de 2027."])
    }

    @Test func mayoresPagosOrdenadosYConAccion() {
        let fx = richFixture()
        let ans = answerQuestion("¿Cuáles son mis mayores pagos este mes?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        let lines = plainLines(ans)
        #expect(lines[0] == "Tus mayores pagos este mes:")
        #expect(lines[1].hasPrefix(nb("Zara: 49,95 €")))
        #expect(lines[2].hasPrefix(nb("Restaurante Sol: 45,00 €")))
        #expect(lines[3].hasPrefix(nb("Mercadona Torrejón: 42,50 €")))
        #expect(ans.lines[1].action != nil)
    }

    @Test func suscripcionesYTotalesIncluyenLasCobradasHoy() {
        let fx = richFixture()
        let ans = answerQuestion("¿Qué suscripciones tengo?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        let lines = plainLines(ans)
        #expect(lines[0] == nb("Tienes 1 suscripción activa: 10,99 € al mes (131,88 € al año)."))
        #expect(lines[1].contains(nb("Spotify: 10,99 € en Revolut")))

        // I6 + M2: si una suscripción vence hoy y ya hubo cobro hoy (p. ej. un pago de otro importe que no avanza la cadena),
        // NO desaparece de la lista y aparece marcada como «cobrado hoy».
        var withChargedToday = LedgerState()
        withChargedToday.movements = [
            Movement(bank: .rev, amountCents: -1_399, merchant: "Netflix", kind: .payment, source: .bank,
                     date: at(2026, 9, 20, 8), isShop: true, bankRef: "nf1", bankStatus: .booked),
            Movement(bank: .rev, amountCents: -1_399, merchant: "Netflix", kind: .payment, source: .bank,
                     date: at(2026, 10, 20, 8), isShop: true, bankRef: "nf2", bankStatus: .booked),
            Movement(bank: .rev, amountCents: -1_099, merchant: "Spotify", kind: .payment, source: .bank,
                     date: at(2026, 9, 22, 12), isShop: true, bankRef: "sp1", bankStatus: .booked),
            Movement(bank: .rev, amountCents: -1_099, merchant: "Spotify", kind: .payment, source: .bank,
                     date: at(2026, 10, 22, 12), isShop: true, bankRef: "sp2", bankStatus: .booked),
            // Un cobro hoy en Netflix que deja `sub.nextDate == nov(20)` (p. ej. importe distinto de la cuota anterior)
            // hace que `subscriptionCharges` la quite de pendientes y `subscriptionsAnswer` la enseñe como «cobrado hoy».
            Movement(bank: .rev, amountCents: -1_999, merchant: "Netflix", kind: .payment, source: .notification,
                     date: nov(20, 9, 0), isShop: true),
        ]
        // Caso 1: con un cobro que SÍ avanzó la cadena, ambas suscripciones siguen listadas.
        var advancedToday = withChargedToday
        advancedToday.movements[4] = Movement(bank: .rev, amountCents: -1_399, merchant: "Netflix", kind: .payment, source: .bank,
                                              date: nov(20, 9, 0), isShop: true, bankRef: "nf3", bankStatus: .booked)
        let twoSubs = answerQuestion("¿Qué suscripciones tengo?", state: advancedToday, portfolio: nil, book: AccountBook(), now: nov(20, 10), calendar: cal)
        #expect(plainLines(twoSubs)[0].hasPrefix("Tienes 2 suscripciones activas:"))
        #expect(plainLines(twoSubs).count == 3)
        #expect(plainLines(twoSubs).contains { $0.contains("Netflix") })
        #expect(plainLines(twoSubs).contains { $0.contains("Spotify") })

        // Caso 2: suscripción con `nextDate` hoy y cobro hoy capturado como gemelo probable de una fila del banco -> dice «cobrado hoy».
        var sameDayUnlinked = LedgerState()
        sameDayUnlinked.movements = [
            Movement(bank: .rev, amountCents: -1_399, merchant: "Netflix", kind: .payment, source: .bank,
                     date: at(2026, 9, 20, 8), isShop: true, bankRef: "nf1", bankStatus: .booked),
            Movement(bank: .rev, amountCents: -1_399, merchant: "Netflix", kind: .payment, source: .bank,
                     date: at(2026, 10, 20, 8), isShop: true, bankRef: "nf2", bankStatus: .booked),
            // Aviso capturado hoy con pareja probable en el banco (nombre distinto): queda en `spendingExclusions` para
            // `detectSubscriptions`, pero `chargedToday` lo detecta como cobrado hoy.
            Movement(bank: .rev, amountCents: -1_399, merchant: "Netflix", kind: .payment, source: .notification,
                     date: nov(20, 9, 0), isShop: true),
            Movement(bank: .rev, amountCents: -1_399, merchant: "NETFLIX COM EU", kind: .payment, source: .bank,
                     date: nov(20, 9, 5), isShop: true, bankRef: "nf3", bankStatus: .booked),
        ]
        let chargedTodayAns = answerQuestion("¿Qué suscripciones tengo?", state: sameDayUnlinked, portfolio: nil, book: AccountBook(), now: nov(20, 10), calendar: cal)
        #expect(plainLines(chargedTodayAns).contains { $0.contains("Netflix") && $0.contains("cobrado hoy") })
    }

    @Test func proximosCobrosNoDescuadranOtroBancoYRespetanHonestidad() {
        let fx = richFixture()
        // Con 340,20 € (exacto) y mínimo 50 € llega para Spotify (10,99 € el día 22).
        let ok = answerQuestion("¿Qué cobros vienen?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(ok).contains { $0.contains("Spotify") && $0.contains(nb("10,99 €")) })
        #expect(plainLines(ok).contains("Con el saldo actual, llega para estos cobros (sin contar otros gastos)."))

        // C3 REGRESIÓN: preguntar solo por Revolut NO debe ignorar un cobro próximo en imagin ni recomendar dejar a imagin bajo mínimo!
        var tightBoth = LedgerState()
        tightBoth.balances[.rev] = ManualBalance(cents: 5_500, setAt: nov(20, 8), origin: .bank)
        tightBoth.balances[.ima] = ManualBalance(cents: 10_000, setAt: nov(20, 8), origin: .bank)
        tightBoth.movements = [
            // Spotify en Revolut el 22 nov (10,99 € -> faltan 5,99 €, sugiere 10 €)
            Movement(bank: .rev, amountCents: -1_099, merchant: "Spotify", kind: .payment, source: .bank,
                     date: at(2026, 9, 22, 12), isShop: true, bankRef: "s1", bankStatus: .booked),
            Movement(bank: .rev, amountCents: -1_099, merchant: "Spotify", kind: .payment, source: .bank,
                     date: at(2026, 10, 22, 12), isShop: true, bankRef: "s2", bankStatus: .booked),
            // Seguro en imagin el 21 nov (45,00 € -> con colchón 50 € solo le sobran 5 € en imagin: NO puede enviar 10 €!)
            Movement(bank: .ima, amountCents: -4_500, merchant: "Seguro", kind: .payment, source: .bank,
                     date: at(2026, 9, 21, 12), isShop: true, bankRef: "i1", bankStatus: .booked),
            Movement(bank: .ima, amountCents: -4_500, merchant: "Seguro", kind: .payment, source: .bank,
                     date: at(2026, 10, 21, 12), isShop: true, bankRef: "i2", bankStatus: .booked),
        ]
        var bookBoth = AccountBook()
        bookBoth.floors[.rev] = 5_000
        bookBoth.floors[.ima] = 5_000
        let revOnly = answerQuestion("¿Me va a faltar saldo en Revolut?", state: tightBoth, portfolio: nil, book: bookBoth, now: fx.now, calendar: cal)
        #expect(!plainLines(revOnly).joined().contains("desde imagin"))
        #expect(plainLines(revOnly).contains { $0.contains("Pásale") })

        // I5: si el banco que tiene cobros llega solo gracias a una nómina prevista, no dice «Con el saldo actual, llega».
        var needsIncome = LedgerState()
        needsIncome.balances[.ima] = ManualBalance(cents: 2_000, setAt: nov(20, 8), origin: .bank)
        needsIncome.movements = [
            // Nómina prevista el 25 nov (+1.800 €)
            Movement(bank: .ima, amountCents: 180_000, merchant: "Nómina ACME", kind: .income, source: .bank,
                     date: at(2026, 9, 25, 9), bankRef: "n1", bankStatus: .booked),
            Movement(bank: .ima, amountCents: 180_000, merchant: "Nómina ACME", kind: .income, source: .bank,
                     date: at(2026, 10, 25, 9), bankRef: "n2", bankStatus: .booked),
            // Recibo el 28 nov (50 € > saldo actual 20 €, pero cubierto por nómina del 25)
            Movement(bank: .ima, amountCents: -5_000, merchant: "Gimnasio", kind: .payment, source: .bank,
                     date: at(2026, 9, 28, 12), isShop: true, bankRef: "g1", bankStatus: .booked),
            Movement(bank: .ima, amountCents: -5_000, merchant: "Gimnasio", kind: .payment, source: .bank,
                     date: at(2026, 10, 28, 12), isShop: true, bankRef: "g2", bankStatus: .booked),
        ]
        let incomeSaved = answerQuestion("¿Qué cobros vienen?", state: needsIncome, portfolio: nil, book: AccountBook(), now: fx.now, calendar: cal)
        #expect(!plainLines(incomeSaved).contains("Con el saldo actual, llega para estos cobros (sin contar otros gastos)."))
        #expect(plainLines(incomeSaved).contains { $0.contains("sin el ingreso previsto") })

        // Sin cobros próximos: no repite «próximos» dos veces (Minor 2).
        let emptyUp = answerQuestion("¿Qué cobros vienen?", state: LedgerState(), portfolio: nil, book: AccountBook(), now: fx.now, calendar: cal)
        #expect(plainLines(emptyUp) == ["No veo cobros para los próximos 14 días."])

        // Si el banco del cobro no tiene saldo, lo avisa honestamente.
        var noBal = fx.state
        noBal.balances[.rev] = nil
        let unknown = answerQuestion("¿Qué cobros vienen?", state: noBal, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(unknown).contains("No tengo el saldo de Revolut, así que no puedo comprobar si llega."))
    }

    @Test func presupuestosConAccionYSinCifrasSueltas() {
        let fx = richFixture()
        let all = answerQuestion("¿Cómo van mis presupuestos?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        let lines = plainLines(all)
        #expect(lines[0] == nb("Presupuesto del mes: llevas 168,45 € de 300,00 € (te quedan 131,55 €)."))
        #expect(lines.contains(nb("Comer fuera: te has pasado, llevas 45,00 € de 40,00 €.")))
        #expect(all.lines.allSatisfy { $0.action == .openBudgets })

        let one = answerQuestion("¿Cómo va mi presupuesto de Comer fuera?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(one) == [nb("Comer fuera: te has pasado, llevas 45,00 € de 40,00 €.")])
    }

    @Test func ingresosYTraspasosPropiosNoSeMezclanNiSeDuplican() {
        let fx = richFixture()
        let inc = answerQuestion("¿Qué ingresos han entrado este mes?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(inc)[0] == nb("Este mes han entrado 1.850,00 € en 1 ingreso."))
        #expect(plainLines(inc)[1].hasPrefix(nb("Nómina ACME: 1.850,00 € en imagin")))

        let tr = answerQuestion("¿Qué traspasos hice entre mis cuentas este mes?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(tr)[0] == nb("Este mes has movido 200,00 € entre tus cuentas (1 traspaso)."))
        #expect(plainLines(tr)[1].hasPrefix(nb("200,00 € de imagin a Revolut")))

        // I7 #1: dos patas de una recarga con tarjeta (`isShop == true`) marcadas manualmente `ownTransfer = true` cuentan como 1 traspaso, no 2.
        var manualState = LedgerState()
        manualState.movements = [
            Movement(bank: .ima, amountCents: -10_000, merchant: "Recarga Revolut", kind: .payment, source: .bank,
                     date: nov(15, 10), isShop: true, ownTransfer: true, bankRef: "p1", bankStatus: .booked),
            Movement(bank: .rev, amountCents: 10_000, merchant: "Recarga con tarjeta", kind: .income, source: .bank,
                     date: nov(15, 10, 5), ownTransfer: true, bankRef: "i1", bankStatus: .booked),
        ]
        let manualAns = answerQuestion("¿Qué traspasos hice entre mis cuentas este mes?", state: manualState,
                                       portfolio: nil, book: AccountBook(), now: fx.now, calendar: cal)
        #expect(plainLines(manualAns)[0] == nb("Este mes has movido 100,00 € entre tus cuentas (1 traspaso)."))
        #expect(plainLines(manualAns)[1].hasPrefix(nb("100,00 € de imagin a Revolut")))
    }

    @Test func dineroLibreHonestoYNuncaCero() {
        let fx = richFixture()
        let ans = answerQuestion("¿Cuánto dinero libre tengo?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        let lines = plainLines(ans)
        #expect(lines[0].hasPrefix(nb("Hasta fin de mes te quedan unos 1.564 € libres: unos 142 € al día, sin contar el gasto del día a día.")))
        #expect(lines.contains("No incluye Trade Republic."))

        // Si el margen diario no llega a 0,50 €, nunca escribe «unos 0 € al día».
        var tiny = LedgerState()
        tiny.balances[.rev] = ManualBalance(cents: 5_200, setAt: nov(20, 8), origin: .bank)
        let tinyAns = answerQuestion("¿Cuánto dinero libre tengo?", state: tiny, portfolio: nil, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(tinyAns)[0] == nb("Hasta fin de mes te quedan unos 2 € libres, sin contar el gasto del día a día."))
        #expect(!plainLines(tinyAns).joined().contains("unos 0"))
        #expect(plainLines(tinyAns).contains("Sin contar imagin: no tengo su saldo."))

        // I7 #2: con 30 céntimos libres (< 50), nunca escribe «unos 0 € libres» y avisa qué banco falta sin nombrar TR si no hay saldo en TR.
        var pennies = LedgerState()
        pennies.balances[.rev] = ManualBalance(cents: 5_030, setAt: nov(20, 8), origin: .bank)
        let penniesAns = answerQuestion("¿Cuánto dinero libre tengo?", state: pennies, portfolio: nil, book: fx.book, now: fx.now, calendar: cal)
        #expect(!plainLines(penniesAns).joined().contains("unos 0"))
        #expect(!plainLines(penniesAns).joined().contains("Trade Republic"))
        #expect(plainLines(penniesAns).contains("Sin contar imagin: no tengo su saldo."))
    }

    @Test func inversionesResumenMoversYPosicionConcreta() {
        let fx = richFixture()
        let overview = answerQuestion("¿Cómo van mis inversiones?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        let lines = plainLines(overview)
        #expect(lines[0] == nb("Valen 1.510,00 €: +6,00 € hoy (+0,4 %)"))
        #expect(lines[1] == nb("Lo que más subió: iShares Core MSCI World (Acc) (+1,4 %). Lo que más bajó: Apple (\u{2212}1,0 %)."))
        #expect(overview.lines.allSatisfy { $0.action == .openInvestments })

        // Posición concreta: Apple (con cambio negativo usando U+2212).
        let apple = answerQuestion("¿Cómo va Apple?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(apple)[0] == nb("Apple: 600,00 € (\u{2212}6,00 € hoy, \u{2212}1,0 %)."))
        #expect(plainLines(apple)[1].hasPrefix(nb("Desde la compra: +59,00 € (+10,9 %)")))

        // Posición con coste incompleto (ETH adquirido a coste 0): NO inventa ganancia (J1).
        let eth = answerQuestion("¿Cómo va Ethereum?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(eth)[0] == nb("Ethereum: 30,00 €."))
        #expect(!plainLines(eth).joined().contains("Desde la compra"))

        // Solo movers.
        let movers = answerQuestion("¿Qué es lo que más ha subido hoy?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(movers) == [nb("Lo que más subió: iShares Core MSCI World (Acc) (+1,4 %). Lo que más bajó: Apple (\u{2212}1,0 %).")])

        // Minor 4: cartera con operaciones pero todas vendidas -> «No tienes posiciones abiertas en tu cartera.»
        var closed = Portfolio()
        closed.transactions = [
            InvestmentTransaction(id: "b", date: at(2026, 3, 2, 9), instrument: "US0378331005", name: "Apple",
                                  assetClass: "STOCK", shares: 2, cashCents: -30_000, priceEUR: 150),
            InvestmentTransaction(id: "s", date: at(2026, 4, 2, 9), instrument: "US0378331005", name: "Apple",
                                  assetClass: "STOCK", shares: -2, cashCents: 34_000, priceEUR: 170),
        ]
        let closedAns = answerQuestion("¿Cómo van mis inversiones?", state: fx.state, portfolio: closed, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(closedAns) == ["No tienes posiciones abiertas en tu cartera."])

        // Minor 3: fallback de posición desconocida con precios faltantes dice «de las que tienen precio».
        var partialPortfolio = fx.portfolio
        partialPortfolio.manualPrices.removeAll()
        let notFound = answerIntent(.investments(positionQuery: "Nvidia", moversOnly: false),
                                    state: fx.state, portfolio: partialPortfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(notFound)[1].contains("de las que tienen precio."))

        // Sin cartera.
        let empty = answerQuestion("¿Cómo van mis inversiones?", state: fx.state, portfolio: nil, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(empty) == ["Aún no tienes inversiones importadas."])
    }

    @Test func queHaPasadoDesdeAyerReutilizaElResumenYAvisaSiHayMasAvisos() {
        let fx = richFixture()
        let recap = answerQuestion("¿Qué ha pasado desde ayer?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(recap)[0].contains(nb("1.850,00 €")))
        #expect(plainLines(recap)[0].contains(nb("49,95 €")))

        // Minor 6: con 3 avisos en atención no trunca en silencio.
        let manyAlerts = BriefingInput(
            now: fx.now, since: nov(19, 10), isFirst: false,
            attention: [.bankProblem(.rev, .offline), .bankProblem(.ima, .bankUnavailable),
                        .warning(title: "Saldo bajo en Revolut", detail: "Te quedan 35,00\u{00A0}€")]
        )
        let recapAlerts = answerIntent(.briefingRecap, state: fx.state, portfolio: nil, book: fx.book,
                                       briefingInput: manyAlerts, now: fx.now, calendar: cal)
        #expect(plainLines(recapAlerts).contains("Y 1 aviso más."))
    }

    @Test func consejoDeInversionDevuelveNegativaLiteralYDatosNeutros() {
        let fx = richFixture()
        let ans = answerQuestion("¿Debería vender Apple?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(ans.isAdviceRefusal)
        #expect(plainLines(ans)[0] == investmentAdviceRefusal)
        #expect(plainLines(ans).count >= 2)
        #expect(plainLines(ans)[1].hasPrefix("Apple: "))
        for extra in plainLines(ans).dropFirst() {
            #expect(!hasAdviceMarker(extra), "\(extra)")
            #expect(!hasTradeVerb(extra), "\(extra)")
        }

        // Sin cartera: solo la negativa literal y sin chip de inversiones (Minor 5).
        let noPortfolio = answerQuestion("¿Qué acciones compro?", state: fx.state, portfolio: nil, book: fx.book, now: fx.now, calendar: cal)
        #expect(noPortfolio.isAdviceRefusal)
        #expect(plainLines(noPortfolio) == [investmentAdviceRefusal])
        #expect(!noPortfolio.chips.contains { $0.id == "investments" })
    }

    @Test func preguntaDesconocidaDevuelveTextoFijoYFichas() {
        let fx = richFixture()
        let ans = answerQuestion("¿Quién ganó ayer el partido?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(ans.intent == .unknown)
        #expect(plainLines(ans) == [assistantUnknownMessage])
        #expect(ans.chips.count >= 4)
    }

    @Test func modoPrivadoTapaCadaCifraEnTodasLasIntenciones() {
        let fx = richFixture()
        let questions = [
            "¿Cuánto tengo?",
            "¿Cuánto tengo en Revolut?",
            "¿Cuánto llevo gastado este mes?",
            "¿Cuánto llevo en Mercadona?",
            "¿Cuánto llevo en Comer fuera?",
            "¿Cuáles son mis mayores pagos este mes?",
            "¿Qué suscripciones tengo?",
            "¿Qué cobros vienen?",
            "¿Cómo van mis presupuestos?",
            "¿Qué ingresos han entrado este mes?",
            "¿Qué traspasos hice entre mis cuentas?",
            "¿Cuánto dinero libre tengo?",
            "¿Cómo van mis inversiones?",
            "¿Cómo va Apple?",
            "¿Qué es lo que más ha subido hoy?",
            "¿Qué ha pasado desde ayer?",
            "¿Vendo Apple?",
        ]
        for q in questions {
            let ans = answerQuestion(q, state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
            for line in ans.lines {
                let masked = render(line.parts, .masked)
                #expect(!masked.contains("€"), "\(q) -> \(masked)")
                #expect(!masked.contains("%"), "\(q) -> \(masked)")
                #expect(masked.range(of: "[0-9],[0-9]{2}", options: .regularExpression) == nil, "\(q) -> \(masked)")
                #expect(masked.range(of: "[0-9]\\.[0-9]{3}", options: .regularExpression) == nil, "\(q) -> \(masked)")
            }
            let privateSpoken = spokenAssistantAnswer(ans, privateMode: true)
            #expect(!privateSpoken.contains("€") && !privateSpoken.contains("euros"), "\(q) -> \(privateSpoken)")
            #expect(!privateSpoken.contains("%") && !privateSpoken.contains("por ciento"), "\(q) -> \(privateSpoken)")
            #expect(privateSpoken.range(of: "[0-9],[0-9]{2}", options: .regularExpression) == nil, "\(q) -> \(privateSpoken)")
        }
    }

    @Test func laVozNormalProtegeNombresYConvierteAvisosDelResumen() {
        var state = LedgerState()
        state.movements = [
            Movement(bank: .rev, amountCents: -3_000, merchant: "Gym +24 % -5€", kind: .payment, source: .bank,
                     date: nov(18, 10), isShop: true, bankRef: "g1", bankStatus: .booked),
        ]
        let ans = answerQuestion("¿Cuáles son mis mayores pagos este mes?", state: state, portfolio: nil, book: AccountBook(),
                                 now: nov(20, 10), calendar: cal)
        let spoken = spokenAssistantAnswer(ans, privateMode: false)
        #expect(spoken.contains("Gym +24 % -5€: 30,00 euros"))
        #expect(!spoken.contains("más 24"))

        // I8 #2: conserva «(Acc)» intacto en el nombre de una posición mientras lee los importes con palabras.
        let fx = richFixture()
        let msci = answerQuestion("¿Cómo va MSCI World?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        let msciSpoken = spokenAssistantAnswer(msci, privateMode: false)
        #expect(msciSpoken.contains("iShares Core MSCI World (Acc)"))
        #expect(msciSpoken.contains("880,00 euros"))

        // I8 #1: un aviso del resumen con «35,00 €» dentro de `.text` se lee como «35,00 euros».
        let warningInput = BriefingInput(
            now: fx.now, since: nov(19, 10), isFirst: false,
            attention: [.warning(title: "Saldo bajo en Revolut", detail: "Te quedan 35,00\u{00A0}€")]
        )
        let recapWarn = answerIntent(.briefingRecap, state: fx.state, portfolio: nil, book: fx.book,
                                     briefingInput: warningInput, now: fx.now, calendar: cal)
        let warnSpoken = spokenAssistantAnswer(recapWarn, privateMode: false)
        #expect(warnSpoken.contains("35,00 euros"))
        #expect(!warnSpoken.contains("€"))

        // En modo privado, una negativa de consejo conserva el texto legal y oculta los números de la cartera.
        let refusal = answerQuestion("¿Vendo Apple?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        let refusalSpoken = spokenAssistantAnswer(refusal, privateMode: true)
        #expect(refusalSpoken.hasPrefix(investmentAdviceRefusal))
        #expect(refusalSpoken.contains("modo privado"))
        #expect(!refusalSpoken.contains("600"))
    }

    @Test func auditoriaC3I1I3PrivacidadDayOnlyYTraspasos() {
        // C3: render(.masked) y spokenAssistantAnswer tapan %, €, U+2212, U+202F y decimales con punto.
        for raw in ["Dia %", "Gym +24 %", "€\u{2212}13,99", "20\u{202F}€", "Tienda 12.50", "Tienda €"] {
            let masked = render([.text("Este mes en \(raw)")], .masked)
            #expect(!masked.contains("€") && !masked.contains("%") && !masked.contains("12.50"), "\(raw) -> \(masked)")
            let ans = AssistantAnswer(intent: .unknown, lines: [BriefingLine(id: "t", parts: [.text("En \(raw)")])])
            let spoken = spokenAssistantAnswer(ans, privateMode: true)
            #expect(!spoken.contains("€") && !spoken.contains("%") && !spoken.contains("12.50"), "\(raw) -> \(spoken)")
        }

        // I1: filas `dayOnly` del banco de hoy (guardadas a las 12:00) cuentan también a las 08:30 de la mañana.
        var morningState = LedgerState()
        morningState.movements = [
            Movement(bank: .rev, amountCents: -8_000, merchant: "Mercadona", kind: .payment, source: .bank,
                     date: nov(20, 12, 0), isShop: true, bankRef: "m-dayonly", bankStatus: .booked, dayOnly: true),
            Movement(bank: .ima, amountCents: 185_000, merchant: "Nómina", kind: .income, source: .bank,
                     date: nov(20, 12, 0), isShop: false, bankRef: "n-dayonly", bankStatus: .booked, dayOnly: true),
        ]
        let morningNow = nov(20, 8, 30)
        let merchAns = answerQuestion("¿Cuánto llevo en Mercadona?", state: morningState, portfolio: nil,
                                      book: AccountBook(), now: morningNow, calendar: cal)
        #expect(render(merchAns.lines[0].parts, .plain).contains("80,00"))
        let bigAns = answerQuestion("¿Cuáles son mis mayores pagos este mes?", state: morningState, portfolio: nil,
                                    book: AccountBook(), now: morningNow, calendar: cal)
        #expect(render(bigAns.lines[1].parts, .plain).contains("80,00"))
        let incAns = answerQuestion("¿Qué ingresos han entrado este mes?", state: morningState, portfolio: nil,
                                    book: AccountBook(), now: morningNow, calendar: cal)
        #expect(render(incAns.lines[0].parts, .plain).contains("1.850,00"))

        // C2: `answerQuestion` rechaza un `modelIntent` con `merchant` no presente en la pregunta original.
        let injectedAns = answerQuestion(
            "¿Cuánto gasté en comida este mes?",
            state: morningState,
            portfolio: nil,
            book: AccountBook(),
            modelIntent: .spending(month: .current, category: nil, merchant: "Supermercado", bank: nil),
            now: morningNow,
            calendar: cal
        )
        #expect(injectedAns.intent != .spending(month: .current, category: nil, merchant: "Supermercado", bank: nil))
    }
}
