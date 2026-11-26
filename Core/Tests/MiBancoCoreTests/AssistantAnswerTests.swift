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
    @Test func saldosTotalesYPorBanco() throws {
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
        let partialLines = plainLines(partialAns)
        #expect(try #require(partialLines.first) == nb("En total tienes unos 2.490,20 €, sin contar imagin."))
        #expect(partialLines.contains("imagin: aún sin saldo"))

        let missingOne = answerQuestion("¿Cuánto tengo en imagin?", state: partial, portfolio: nil, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(missingOne) == ["Aún no tengo el saldo de imagin."])
    }

    @Test func gastosMesCategoriaComercioYBancoRespetanExclusiones() throws {
        let fx = richFixture()
        // I3 #7: Mercadona Torrejón + Mercadona Alcalá -> usa «Mercadona» (no la última tienda concreta).
        let mercadona = answerQuestion("¿Cuánto llevo en Mercadona?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(try #require(plainLines(mercadona).first) == nb("Este mes llevas 73,50 € en Mercadona (2 pagos)."))
        #expect(try #require(mercadona.lines.dropFirst().first).action != nil)

        // I7 #3: Categoría Supermercado tampoco cuenta el pago de 0 € (2 pagos, igual que Mercadona).
        let superCat = answerQuestion("¿Cuánto llevo en Supermercado?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(try #require(plainLines(superCat).first) == nb("Este mes llevas 73,50 € en Supermercado (2 pagos)."))

        // I3 #5: Gasto filtrado por banco (en imagin solo hubo traspaso de 200 €, que NO es gasto -> 0 gastos).
        let spendIma = answerQuestion("¿Cuánto gasté en imagin este mes?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(spendIma) == ["Este mes aún no tienes gastos registrados en imagin."])
        let spendRev = answerQuestion("¿Cuánto gasté en Revolut este mes?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(try #require(plainLines(spendRev).first) == nb("Este mes llevas 168,45 € gastados en Revolut."))

        // Comercio inexistente en el libro -> U2: no afirma «no tienes pagos».
        let emptyMerchant = answerQuestion("¿Cuánto llevo en Lidl?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(emptyMerchant) == ["No encuentro pagos a nombre de «Lidl»."])
        #expect(emptyMerchant.chips.map(\.label) == ["¿Cuánto llevo en Supermercado?", "¿Cuánto llevo en Comer fuera?"])

        // Comercio que SÍ existe en el libro (en otro mes) pero sin pagos este mes -> sí dice «Este mes no tienes pagos…».
        var withOldLidl = fx.state
        withOldLidl.movements.append(Movement(bank: .rev, amountCents: -2_000, merchant: "Lidl", kind: .payment, source: .bank,
                                              date: at(2026, 9, 10, 12), isShop: true, bankRef: "lidl-sep", bankStatus: .booked))
        let oldLidlAns = answerQuestion("¿Cuánto llevo en Lidl?", state: withOldLidl, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(oldLidlAns) == ["Este mes no tienes pagos en Lidl."])

        // Categoría Comer fuera: 45,00 €
        let cat = answerQuestion("¿Cuánto llevo en Comer fuera?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(try #require(plainLines(cat).first) == nb("Este mes llevas 45,00 € en Comer fuera (1 pago)."))

        // Total del mes: 42,50 + 31,00 + 49,95 + 45,00 = 168,45 €
        let total = answerQuestion("¿Cuánto llevo gastado este mes?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        let totalLines = plainLines(total)
        #expect(try #require(totalLines.first).hasPrefix(nb("Este mes llevas 168,45 € gastados")))
        #expect(totalLines.contains(nb("Donde más: Supermercado (73,50 €).")))

        // Mes pasado (octubre): 50,00 Mercadona + 10,99 Spotify = 60,99 €
        let last = answerQuestion("¿Cuánto gasté el mes pasado?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(try #require(plainLines(last).first) == nb("El mes pasado gastaste 60,99 €."))

        // Mes futuro: honesto.
        let future = answerIntent(.spending(month: .specific(year: 2027, month: 1), category: nil, merchant: nil),
                                  state: fx.state, portfolio: nil, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(future) == ["Aún no ha llegado enero de 2027."])
    }

    @Test func mayoresPagosOrdenadosYConAccion() throws {
        let fx = richFixture()
        let ans = answerQuestion("¿Cuáles son mis mayores pagos este mes?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        let lines = plainLines(ans)
        try #require(lines.count >= 4)
        #expect(lines[0] == "Tus mayores pagos este mes:")
        #expect(lines[1].hasPrefix(nb("Zara: 49,95 €")))
        #expect(lines[2].hasPrefix(nb("Restaurante Sol: 45,00 €")))
        #expect(lines[3].hasPrefix(nb("Mercadona Torrejón: 42,50 €")))
        #expect(try #require(ans.lines.dropFirst().first).action != nil)
    }

    @Test func suscripcionesYTotalesIncluyenLasCobradasHoy() throws {
        let fx = richFixture()
        let ans = answerQuestion("¿Qué suscripciones tengo?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        let lines = plainLines(ans)
        try #require(lines.count >= 2)
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
        let twoSubsLines = plainLines(twoSubs)
        #expect(try #require(twoSubsLines.first).hasPrefix("Tienes 2 suscripciones activas:"))
        #expect(twoSubsLines.count == 3)
        #expect(twoSubsLines.contains { $0.contains("Netflix") })
        #expect(twoSubsLines.contains { $0.contains("Spotify") })

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

    @Test func presupuestosConAccionYSinCifrasSueltas() throws {
        let fx = richFixture()
        let all = answerQuestion("¿Cómo van mis presupuestos?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        let lines = plainLines(all)
        #expect(try #require(lines.first) == nb("Presupuesto del mes: llevas 168,45 € de 300,00 € (te quedan 131,55 €)."))
        #expect(lines.contains(nb("Comer fuera: te has pasado, llevas 45,00 € de 40,00 €.")))
        #expect(all.lines.allSatisfy { $0.action == .openBudgets })

        let one = answerQuestion("¿Cómo va mi presupuesto de Comer fuera?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(one) == [nb("Comer fuera: te has pasado, llevas 45,00 € de 40,00 €.")])
    }

    @Test func ingresosYTraspasosPropiosNoSeMezclanNiSeDuplican() throws {
        let fx = richFixture()
        let inc = answerQuestion("¿Qué ingresos han entrado este mes?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        let incLines = plainLines(inc)
        try #require(incLines.count >= 2)
        #expect(incLines[0] == nb("Este mes han entrado 1.850,00 € en 1 ingreso."))
        #expect(incLines[1].hasPrefix(nb("Nómina ACME: 1.850,00 € en imagin")))

        let tr = answerQuestion("¿Qué traspasos hice entre mis cuentas este mes?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        let trLines = plainLines(tr)
        try #require(trLines.count >= 2)
        #expect(trLines[0] == nb("Este mes has movido 200,00 € entre tus cuentas (1 traspaso)."))
        #expect(trLines[1].hasPrefix(nb("200,00 € de imagin a Revolut")))

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
        let manualLines = plainLines(manualAns)
        try #require(manualLines.count >= 2)
        #expect(manualLines[0] == nb("Este mes has movido 100,00 € entre tus cuentas (1 traspaso)."))
        #expect(manualLines[1].hasPrefix(nb("100,00 € de imagin a Revolut")))
    }

    @Test func dineroLibreHonestoYNuncaCero() throws {
        let fx = richFixture()
        let ans = answerQuestion("¿Cuánto dinero libre tengo?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        let lines = plainLines(ans)
        #expect(try #require(lines.first).hasPrefix(nb("Hasta fin de mes te quedan unos 1.564 € libres: unos 142 € al día, sin contar el gasto del día a día.")))
        #expect(lines.contains("No incluye Trade Republic."))

        // Si el margen diario no llega a 0,50 €, nunca escribe «unos 0 € al día».
        var tiny = LedgerState()
        tiny.balances[.rev] = ManualBalance(cents: 5_200, setAt: nov(20, 8), origin: .bank)
        let tinyAns = answerQuestion("¿Cuánto dinero libre tengo?", state: tiny, portfolio: nil, book: fx.book, now: fx.now, calendar: cal)
        let tinyLines = plainLines(tinyAns)
        #expect(try #require(tinyLines.first) == nb("Hasta fin de mes te quedan unos 2 € libres, sin contar el gasto del día a día."))
        #expect(!tinyLines.joined().contains("unos 0"))
        #expect(tinyLines.contains("Sin contar imagin: no tengo su saldo."))

        // I7 #2: con 30 céntimos libres (< 50), nunca escribe «unos 0 € libres» y avisa qué banco falta sin nombrar TR si no hay saldo en TR.
        var pennies = LedgerState()
        pennies.balances[.rev] = ManualBalance(cents: 5_030, setAt: nov(20, 8), origin: .bank)
        let penniesAns = answerQuestion("¿Cuánto dinero libre tengo?", state: pennies, portfolio: nil, book: fx.book, now: fx.now, calendar: cal)
        #expect(!plainLines(penniesAns).joined().contains("unos 0"))
        #expect(!plainLines(penniesAns).joined().contains("Trade Republic"))
        #expect(plainLines(penniesAns).contains("Sin contar imagin: no tengo su saldo."))
    }

    @Test func inversionesResumenMoversYPosicionConcreta() throws {
        let fx = richFixture()
        // U89: la nota es la ÚLTIMA línea, con el texto corto; el dato va primero.
        let note = "Son datos, no una recomendación."
        let overview = answerQuestion("¿Cómo van mis inversiones?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        let lines = plainLines(overview)
        // U89 + U5: sujeto + punto final en el resumen de cartera del asistente y la nota al final.
        try #require(lines.count >= 3)
        #expect(lines[0] == nb("Tus inversiones valen 1.510,00 €: +6,00 € hoy (+0,4 %)."))
        #expect(lines[1] == nb("Lo que más subió: iShares Core MSCI World (Acc) (+1,4 %). Lo que más bajó: Apple (\u{2212}1,0 %)."))
        #expect(lines.last == note)
        #expect(overview.lines.allSatisfy { $0.action == .openInvestments })

        // Posición concreta: Apple (con cambio negativo usando U+2212).
        let apple = answerQuestion("¿Cómo va Apple?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        let appleLines = plainLines(apple)
        try #require(appleLines.count >= 3)
        #expect(appleLines[0] == nb("Apple: 600,00 € (\u{2212}6,00 € hoy, \u{2212}1,0 %)."))
        #expect(appleLines[1].hasPrefix(nb("Desde la compra: +59,00 € (+10,9 %)")))
        #expect(appleLines.last == note)

        // Posición con coste incompleto (ETH adquirido a coste 0): NO inventa ganancia (J1).
        let eth = answerQuestion("¿Cómo va Ethereum?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        let ethLines = plainLines(eth)
        try #require(ethLines.count >= 2)
        #expect(ethLines[0] == nb("Ethereum: 30,00 €."))
        #expect(ethLines.last == note)
        #expect(!ethLines.joined().contains("Desde la compra"))

        // Solo movers.
        let movers = answerQuestion("¿Qué es lo que más ha subido hoy?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(movers) == [nb("Lo que más subió: iShares Core MSCI World (Acc) (+1,4 %). Lo que más bajó: Apple (\u{2212}1,0 %)."), note])

        // Minor 4: cartera con operaciones pero todas vendidas -> nota fija + «No tienes posiciones abiertas en tu cartera.»
        var closed = Portfolio()
        closed.transactions = [
            InvestmentTransaction(id: "b", date: at(2026, 3, 2, 9), instrument: "US0378331005", name: "Apple",
                                  assetClass: "STOCK", shares: 2, cashCents: -30_000, priceEUR: 150),
            InvestmentTransaction(id: "s", date: at(2026, 4, 2, 9), instrument: "US0378331005", name: "Apple",
                                  assetClass: "STOCK", shares: -2, cashCents: 34_000, priceEUR: 170),
        ]
        let closedAns = answerQuestion("¿Cómo van mis inversiones?", state: fx.state, portfolio: closed, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(closedAns) == ["No tienes posiciones abiertas en tu cartera.", note])

        // Minor 3: fallback de posición desconocida con precios faltantes dice «de las que tienen precio».
        var partialPortfolio = fx.portfolio
        partialPortfolio.manualPrices.removeAll()
        let notFound = answerIntent(.investments(positionQuery: "Nvidia", moversOnly: false),
                                    state: fx.state, portfolio: partialPortfolio, book: fx.book, now: fx.now, calendar: cal)
        let notFoundLines = plainLines(notFound)
        try #require(notFoundLines.count >= 3)
        #expect(notFoundLines[0] == "No encuentro esa posición en tu cartera.")
        #expect(notFoundLines[1].contains("de las que tienen precio."))
        #expect(notFoundLines.last == note)

        // Sin cartera.
        let empty = answerQuestion("¿Cómo van mis inversiones?", state: fx.state, portfolio: nil, book: fx.book, now: fx.now, calendar: cal)
        #expect(plainLines(empty) == ["Aún no tienes inversiones importadas.", note])
    }

    @Test func queHaPasadoDesdeAyerReutilizaElResumenYAvisaSiHayMasAvisos() throws {
        let fx = richFixture()
        let recap = answerQuestion("¿Qué ha pasado desde ayer?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        let recapFirst = try #require(plainLines(recap).first)
        #expect(recapFirst.contains(nb("1.850,00 €")))
        #expect(recapFirst.contains(nb("49,95 €")))

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

    @Test func consejoDeInversionDevuelveNegativaLiteralYDatosNeutros() throws {
        let fx = richFixture()
        let ans = answerQuestion("¿Debería vender Apple?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(ans.isAdviceRefusal)
        let ansLines = plainLines(ans)
        try #require(ansLines.count >= 2)
        #expect(ansLines[0] == investmentAdviceRefusal)
        #expect(ansLines[1].hasPrefix("Apple: "))
        for extra in ansLines.dropFirst() {
            #expect(!hasAdviceMarker(extra), "\(extra)")
            #expect(!hasTradeVerb(extra), "\(extra)")
        }

        // U84 (cambia Minor 5 por U69(a)): sin cartera la negativa NO va sola; detrás va la respuesta de inversiones, y sin
        // chip de inversiones. Si la intención sin freno es desconocida, la negativa con las fichas sugeridas (U83).
        var routedToInvestments = 0
        for q in ["¿Qué acciones compro?", "¿Compro bitcoin?"] {
            let noPortfolio = answerQuestion(q, state: fx.state, portfolio: nil, book: fx.book, now: fx.now, calendar: cal)
            #expect(noPortfolio.isAdviceRefusal, "\(q)")
            #expect(!noPortfolio.chips.contains { $0.id == "investments" }, "\(q)")
            let underlying = routeAssistantQuestionWithoutAdviceGate(q, state: fx.state, portfolio: nil, now: fx.now, calendar: cal)
            if case .investments = underlying {
                routedToInvestments += 1
                #expect(plainLines(noPortfolio) == [investmentAdviceRefusal, "Aún no tienes inversiones importadas."], "\(q)")
            }
        }
        #expect(routedToInvestments >= 1, "U84: ninguna de las preguntas llega a inversiones")
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

    @Test func auditoriaC3I1I3PrivacidadDayOnlyYTraspasos() throws {
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
        try #require(merchAns.lines.count > 0)
        #expect(render(merchAns.lines[0].parts, .plain).contains("80,00"))
        let bigAns = answerQuestion("¿Cuáles son mis mayores pagos este mes?", state: morningState, portfolio: nil,
                                    book: AccountBook(), now: morningNow, calendar: cal)
        try #require(bigAns.lines.count > 1)
        #expect(render(bigAns.lines[1].parts, .plain).contains("80,00"))
        let incAns = answerQuestion("¿Qué ingresos han entrado este mes?", state: morningState, portfolio: nil,
                                    book: AccountBook(), now: morningNow, calendar: cal)
        try #require(incAns.lines.count > 0)
        #expect(render(incAns.lines[0].parts, .plain).contains("1.850,00"))

        // C2 + U2: `answerQuestion` rechaza un `modelIntent` con `merchant` no presente en la pregunta original,
        // y lo que enseña tampoco afirma «no tienes pagos».
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
        let injectedFirst = try #require(plainLines(injectedAns).first)
        #expect(!injectedFirst.lowercased().contains("no tienes pagos"), "No debe afirmar ausencia: \(injectedFirst)")
    }

    // MARK: U2 — Comercios inexistentes, artículos, dominio y tramo del modelo

    @Test func comidaNoAfirmaQueNoHayPagos() throws {
        let fx = richFixture()
        let ans = answerQuestion("¿Cuánto gasté en comida este mes?", state: fx.state, portfolio: fx.portfolio,
                                 book: fx.book, now: fx.now, calendar: cal)
        let first = try #require(plainLines(ans).first)
        #expect(first == "No encuentro pagos a nombre de «comida».")
        #expect(ans.chips.map(\.label) == ["¿Cuánto llevo en Supermercado?", "¿Cuánto llevo en Comer fuera?"])
    }

    @Test func elCocheSinArticulo() throws {
        let fx = richFixture()
        let ans = answerQuestion("¿Cuánto gasté en el coche?", state: fx.state, portfolio: fx.portfolio,
                                 book: fx.book, now: fx.now, calendar: cal)
        let first = try #require(plainLines(ans).first)
        #expect(first == "No encuentro pagos a nombre de «coche».")
    }

    @Test func amazonPorDominio() throws {
        var state = LedgerState()
        state.movements = [
            Movement(bank: .rev, amountCents: -2_599, merchant: "AMZN Mktp ES*2K4", kind: .payment, source: .bank,
                     date: nov(12, 14), isShop: true, bankRef: "amz1", bankStatus: .booked),
        ]
        let ans = answerQuestion("¿Cuánto llevo en Amazon?", state: state, portfolio: nil, book: AccountBook(),
                                 now: nov(20, 10), calendar: cal)
        let first = try #require(plainLines(ans).first)
        #expect(first.contains("25,99"), "Esperaba 25,99 en: \(first)")
    }

    @Test func diaEsUnComercio() throws {
        var state = LedgerState()
        state.movements = [
            Movement(bank: .rev, amountCents: -1_240, merchant: "DIA Alcalá", kind: .payment, source: .bank,
                     date: nov(12, 14), isShop: true, bankRef: "dia1", bankStatus: .booked),
            // Segundo pago para que la prueba no pueda pasar cayendo al total del mes.
            Movement(bank: .rev, amountCents: -5_000, merchant: "Mercadona", kind: .payment, source: .bank,
                     date: nov(14, 14), isShop: true, bankRef: "merc1", bankStatus: .booked),
        ]
        let ans = answerQuestion("¿Cuánto llevo en Dia?", state: state, portfolio: nil, book: AccountBook(),
                                 now: nov(20, 10), calendar: cal)
        let first = try #require(plainLines(ans).first)
        #expect(first.contains("12,40") && first.lowercased().contains("dia"), "Esperaba 12,40 en Dia: \(first)")
    }

    @Test func totalEnMercadonaDelModelo() throws {
        let fx = richFixture()
        let ans = answerQuestion(
            "¿Cuánto gasté en total en Mercadona?",
            state: fx.state,
            portfolio: fx.portfolio,
            book: fx.book,
            modelIntent: .spending(month: .current, category: nil, merchant: "total en Mercadona", bank: nil),
            now: fx.now,
            calendar: cal
        )
        let first = try #require(plainLines(ans).first)
        #expect(first.contains("en Mercadona") && first.contains("73,50"), "Cabecera inesperada: \(first)")
        #expect(!first.contains("en total en Mercadona"), "No debe arrastrar «total en»: \(first)")
    }

    // MARK: U5 — Textos honestos del Core del asistente

    @Test func sinColchonDiceEnNegativo() throws {
        var state = LedgerState()
        state.balances[.rev] = ManualBalance(cents: 2_000, setAt: nov(20, 8), origin: .bank)
        // Cobro dentro de 5 días (25 nov, 30 €): cae en el aviso de 14 días (no en urgente de 3 días).
        state.movements = [
            Movement(bank: .rev, amountCents: -3_000, merchant: "Gimnasio", kind: .payment, source: .bank,
                     date: at(2026, 9, 25, 12), isShop: true, bankRef: "g1", bankStatus: .booked),
            Movement(bank: .rev, amountCents: -3_000, merchant: "Gimnasio", kind: .payment, source: .bank,
                     date: at(2026, 10, 25, 12), isShop: true, bankRef: "g2", bankStatus: .booked),
        ]
        let ans = answerQuestion("¿Qué cobros vienen?", state: state, portfolio: nil, book: AccountBook(),
                                 now: nov(20, 10), calendar: cal)
        let lines = plainLines(ans)
        #expect(lines.contains { $0.contains("se quedaría en negativo") }, "Líneas: \(lines)")
        #expect(!lines.joined().contains("su mínimo"), "No debe decir «su mínimo» sin colchón: \(lines)")

        // También en tarjetas de «Te puede interesar» (InterestCards.swift:339).
        let cards = interestCards(state: state, portfolio: nil, book: AccountBook(), now: nov(20, 10), calendar: cal)
        let card = try #require(cards.first { $0.topic == .shortfall })
        let cardText = render(card.parts, .plain)
        #expect(cardText.contains("se quedaría en negativo"), "Tarjeta: \(cardText)")
        #expect(!cardText.contains("su mínimo"), "Tarjeta sin colchón: \(cardText)")
    }

    @Test func tradeRepublicEsEfectivo() throws {
        let fx = richFixture()
        let ans = answerQuestion("¿Cuánto tengo en Trade Republic?", state: fx.state, portfolio: fx.portfolio,
                                 book: fx.book, now: fx.now, calendar: cal)
        let first = try #require(plainLines(ans).first)
        #expect(first == nb("En Trade Republic tienes unos 2.150,00 € de efectivo, sin contar tus inversiones."))

        // Con saldo exacto del banco:
        var exact = fx.state
        exact.balances[.tr] = ManualBalance(cents: 215_000, setAt: nov(20, 8), origin: .bank)
        let exactAns = answerQuestion("¿Cuánto tengo en Trade Republic?", state: exact, portfolio: fx.portfolio,
                                      book: fx.book, now: fx.now, calendar: cal)
        #expect(try #require(plainLines(exactAns).first) == nb("En Trade Republic tienes 2.150,00 € de efectivo, sin contar tus inversiones."))

        // Sin cartera abierta: como hoy.
        let noPortfolio = answerQuestion("¿Cuánto tengo en Trade Republic?", state: exact, portfolio: nil,
                                         book: fx.book, now: fx.now, calendar: cal)
        #expect(try #require(plainLines(noPortfolio).first) == nb("En Trade Republic tienes 2.150,00 €."))
    }

    // MARK: U6 — Patas manuales sin pareja no se suman como dinero movido

    @Test func patasSinParejaNoDuplican() throws {
        var unpaired = LedgerState()
        unpaired.movements = [
            Movement(bank: .ima, amountCents: -20_000, merchant: "Envío Revolut", kind: .payment, source: .bank,
                     date: nov(15, 10), ownTransfer: true, bankRef: "u1", bankStatus: .booked),
            Movement(bank: .rev, amountCents: 15_000, merchant: "Recarga imagin", kind: .income, source: .bank,
                     date: nov(17, 10), ownTransfer: true, bankRef: "u2", bankStatus: .booked),
        ]
        let ans = answerQuestion("¿Qué traspasos hice entre mis cuentas este mes?", state: unpaired, portfolio: nil,
                                 book: AccountBook(), now: nov(20, 10), calendar: cal)
        let head = try #require(plainLines(ans).first)
        #expect(!head.contains("350,00"), "No debe sumar patas sin pareja: \(head)")
        #expect(head == "Este mes tienes 2 movimientos marcados como traspaso sin pareja:", "Cabecera: \(head)")

        // Control: emparejados (-200 / +200 en 2 días) siguen sumando 200,00 €.
        var paired = LedgerState()
        paired.movements = [
            Movement(bank: .ima, amountCents: -20_000, merchant: "Envío Revolut", kind: .payment, source: .bank,
                     date: nov(15, 10), ownTransfer: true, bankRef: "p1", bankStatus: .booked),
            Movement(bank: .rev, amountCents: 20_000, merchant: "Recarga imagin", kind: .income, source: .bank,
                     date: nov(17, 10), ownTransfer: true, bankRef: "p2", bankStatus: .booked),
        ]
        let pairedAns = answerQuestion("¿Qué traspasos hice entre mis cuentas este mes?", state: paired, portfolio: nil,
                                       book: AccountBook(), now: nov(20, 10), calendar: cal)
        #expect(try #require(plainLines(pairedAns).first) == nb("Este mes has movido 200,00 € entre tus cuentas (1 traspaso)."))

        // Emparejado + 1 pata sin pareja: la cabecera solo suma el emparejado y la pata va detrás de su línea propia.
        var mixed = paired
        mixed.movements.append(
            Movement(bank: .ima, amountCents: -5_000, merchant: "Recarga suelta", kind: .payment, source: .bank,
                     date: nov(18, 10), ownTransfer: true, bankRef: "p3", bankStatus: .booked)
        )
        let mixedAns = answerQuestion("¿Qué traspasos hice entre mis cuentas este mes?", state: mixed, portfolio: nil,
                                      book: AccountBook(), now: nov(20, 10), calendar: cal)
        let mixedLines = plainLines(mixedAns)
        #expect(try #require(mixedLines.first) == nb("Este mes has movido 200,00 € entre tus cuentas (1 traspaso)."))
        #expect(mixedLines.contains("Además, 1 movimiento marcado como traspaso no tiene pareja:"))

        // N7 (U6): mes concreto («en octubre») y mes pasado («el mes pasado») con patas sueltas.
        var octUnpaired = LedgerState()
        octUnpaired.movements = [
            Movement(bank: .ima, amountCents: -20_000, merchant: "Envío Revolut", kind: .payment, source: .bank,
                     date: at(2026, 10, 15, 10), ownTransfer: true, bankRef: "o1", bankStatus: .booked),
            Movement(bank: .rev, amountCents: 15_000, merchant: "Recarga imagin", kind: .income, source: .bank,
                     date: at(2026, 10, 17, 10), ownTransfer: true, bankRef: "o2", bankStatus: .booked),
        ]
        let octAns = answerQuestion("¿Qué traspasos hice entre mis cuentas en octubre?", state: octUnpaired, portfolio: nil,
                                    book: AccountBook(), now: nov(20, 10), calendar: cal)
        #expect(try #require(plainLines(octAns).first) == "En octubre tuviste 2 movimientos marcados como traspaso sin pareja:")
        let prevAns = answerQuestion("¿Qué traspasos hice entre mis cuentas el mes pasado?", state: octUnpaired, portfolio: nil,
                                     book: AccountBook(), now: nov(20, 10), calendar: cal)
        #expect(try #require(plainLines(prevAns).first) == "El mes pasado tuviste 2 movimientos marcados como traspaso sin pareja:")
    }

    // MARK: N2 (U3) — El modelo no puede saltarse `.unsupportedPeriod`

    @Test func modeloNoSeSaltaPeriodoNoSoportado() throws {
        let fx = richFixture()
        for (q, intent) in [
            ("¿Cuánto he gastado hoy?", AssistantIntent.spending(month: .current, category: nil, merchant: nil, bank: nil)),
            ("¿Cuál fue mi mayor pago ayer?", AssistantIntent.biggestPayments(month: .current)),
            ("¿Qué ingresos entraron esta semana?", AssistantIntent.income(month: .current)),
            ("¿Qué traspasos hice este año?", AssistantIntent.ownTransfers(month: .current)),
        ] {
            let ans = answerQuestion(q, state: fx.state, portfolio: fx.portfolio, book: fx.book,
                                     modelIntent: intent, now: fx.now, calendar: cal)
            #expect(ans.intent == .unsupportedPeriod, "\(q) -> \(ans.intent)")
            #expect(try #require(plainLines(ans).first) == "Aún no sé contarte el gasto por días, semanas o años; sí por meses.", "\(q)")
        }
    }

    // MARK: U69 — La negativa nunca quita los datos y toda respuesta de inversiones lleva la nota fija

    @Test func u69NegativaNuncaSustituyeDatosYNotaFijaEnInversiones() throws {
        let fx = richFixture()
        let note = "Son datos, no una recomendación."

        // (a) Una pregunta que dispara el filtro de consejo PERO también pide un dato concreto del libro (presupuesto, gasto, saldo…)
        // devuelve `investmentAdviceRefusal` como primera línea Y DESPUÉS los datos reales de esa intención (sin sustituirlos).
        let adviceWithBudget = answerQuestion("¿Debería comprar menos para mi presupuesto de Comer fuera?", state: fx.state,
                                              portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(adviceWithBudget.isAdviceRefusal)
        let budgetLines = plainLines(adviceWithBudget)
        try #require(budgetLines.count >= 2)
        #expect(budgetLines[0] == investmentAdviceRefusal)
        #expect(budgetLines.dropFirst().contains { $0.contains("Comer fuera") && $0.contains(nb("45,00 €")) })
        #expect(!budgetLines.contains(note), "No repetir la nota cuando ya va delante la negativa")

        let adviceWithBalance = answerQuestion("¿Me recomiendas mover mi saldo de Revolut?", state: fx.state,
                                               portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(adviceWithBalance.isAdviceRefusal)
        let balanceLines = plainLines(adviceWithBalance)
        try #require(balanceLines.count >= 2)
        #expect(balanceLines[0] == investmentAdviceRefusal)
        #expect(balanceLines.dropFirst().contains { $0.contains("Revolut") && $0.contains(nb("340,20 €")) })

        // (a) Cuando la pregunta pide consejo sobre inversiones con cartera, lleva `investmentAdviceRefusal` y NO repite `note`.
        let adviceInv = answerQuestion("¿Debería vender Apple?", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        let adviceInvLines = plainLines(adviceInv)
        try #require(adviceInvLines.count >= 2)
        #expect(adviceInvLines[0] == investmentAdviceRefusal)
        #expect(!adviceInvLines.contains(note))

        // (b) + U89: toda respuesta de inversiones (también en modo privado `.masked`) lleva la nota como ÚLTIMA línea (o la
        // negativa delante y entonces sin nota), nunca empieza por la nota y nunca filtra cifras.
        for q in ["Mis inversiones", "¿Qué acciones tengo?", "¿Cómo va Apple?", "¿Qué es lo que más ha subido hoy?"] {
            let ans = answerQuestion(q, state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
            let lines = plainLines(ans)
            try #require(lines.count >= 2, "Sin datos para \(q): \(lines)")
            #expect(lines[0] != note, "\(q): la nota no va delante")
            #expect(lines.last == note || lines[0] == investmentAdviceRefusal, "\(q): \(lines)")
            let maskedLast = render(try #require(ans.lines.last).parts, .masked)
            #expect(maskedLast == note || lines[0] == investmentAdviceRefusal)
            for line in ans.lines {
                let m = render(line.parts, .masked)
                #expect(!m.contains("€") && !m.contains("%"), "Fuga en privado: \(m)")
            }
        }
    }

    // MARK: U69 — listas de la re-revisión (`rerevision-u1-u7.md` §2a y §2b)

    /// §2b: preguntas de hechos que recibían la negativa. Reciban o no la negativa, DESPUÉS van siempre los datos de la
    /// intención que el enrutador elige sin el freno de consejos (la negativa nunca sustituye a la respuesta).
    private static let u69FactQuestions = [
        "¿Qué acciones tengo?", "¿Qué posiciones tengo?", "¿Cuántas posiciones tengo?", "¿Qué ETFs tengo?", "¿Qué fondos tengo?",
        "¿Cuántas acciones de Apple tengo?", "¿Tengo acciones de Apple?", "¿Cuál es mi cartera?", "Mi cartera", "Cartera",
        "Inversiones", "Mis inversiones", "Resumen de mi cartera", "Valor de mi cartera", "¿Qué tal van mis acciones?",
        "¿Cuál es mi posición en Apple?", "¿Cuál es la rentabilidad de mi cartera?", "Dividendos", "¿Qué dividendos me tocan?",
        "¿Cuándo cobro el dividendo de Apple?", "¿Cuántos dividendos he cobrado este año?", "¿Cuánto he cobrado en dividendos?",
        "¿Cuándo es la próxima aportación?", "¿A qué precio compré Apple?", "¿A cuánto cotiza Apple?",
        "¿Cuál es la cotización de Apple?", "¿Cuánto ha caído Apple?", "¿Qué tal va Apple?", "¿Cuánto me ha dado Apple?",
        "¿Cuánto me cobró el broker?", "¿Cuánto me cobró Trade Republic por el ETF?", "¿Cuánto me cuesta el ETF de comisión?",
        "¿Cuánto me pagó Apple de dividendo?", "¿Cuánto me cobró la academia Bitcoin Escuela?",
        "¿Cuánto pago de cuota en Fondo Social?", "¿Cuánto me entró de Wallapop?", "¿Cuánto me entró de Hacienda?",
        "¿Cuándo entró la nómina de Acme?", "¿Cuánto fue el aumento de la factura de Iberdrola?",
        "¿Cuánto dinero líquido tengo en ING?", "¿Cuánto compraba en Mercadona antes?", "¿Cuánto vendía en Wallapop?",
        "¿Cuánto he ganado vendiendo en Wallapop?", "¿Cuánto gasté en Vinted vendiendo ropa?",
        "¿Cuánto me pagaron por vender la bici?", "¿Cuánto me pagó el vendedor?", "¿Cuánto le pagué al vendedor del coche?",
        "¿Cuánto me costaron las vendas en la farmacia?", "¿Cuántas veces compro en Mercadona al mes?",
        "¿Cuánto gasto cuando compro en Mercadona?", "¿Cuánto me devolvieron al comprar en Amazon?",
        "¿Cuánto me ahorré comprando en Lidl?", "¿Qué compre el finde?", "¿Qué compre esta mañana?",
        "¿Dónde compre las zapatillas?", "Compras ayer", "Compras hoy", "Compras esta semana", "Compras Amazon",
        "Compras con tarjeta", "Ventas Wallapop", "¿Pongo 30 € en el bote de Navidad?", "¿Pongo 50 € para el regalo de Ana?",
        "¿Meto 50 € en la Tarjeta Regalo de Amazon?", "¿Va a subir el IBI en Madrid?", "¿Está caro Mercadona?",
        "¿Me compensa el Mercadona?", "¿Subirá Netflix?", "¿Cuánto gasté aprovechando las rebajas?", "¿Cuánto acumula la hucha?",
        "¿Hasta cuándo aguanta mi saldo?", "¿Cuántos días aguanto con lo que tengo?", "¿Cuánto me cuestan las clases de refuerzo?",
        "¿Cuánto pagué a la Consejería?", "¿Cuánto gasté en Sal de Ibiza?", "¿Es hora de pagar la luz?",
        "¿Qué pagos están en hold?", "What did I buy yesterday?", "My purchases this month",
        // Las dos del borrador de esta ronda: el filtro salta y, aun así, salen el presupuesto y el saldo.
        "¿Debería comprar menos para mi presupuesto de Comer fuera?", "¿Me recomiendas mover mi saldo de Revolut?",
    ]

    /// §2a: peticiones de consejo que pasaban sin la negativa.
    private static let u69AdviceQuestions = [
        "¿Nvidia está barata?", "¿Tesla es rentable?", "Nvidia worth it?", "¿Nvidia subirá?", "¿Tesla va a subir?",
        "¿Tesla o Nvidia?", "¿Apple o Microsoft?", "¿Merecería la pena Nvidia?", "¿Valdría la pena Tesla?",
        "¿En qué meto 1.000 €?", "¿Dónde pongo 1000 €?", "¿Qué hago con mil euros?", "¿Mantengo Nvidia?", "¿Promedio Nvidia?",
        "¿Hago bien en mantener Tesla?", "¿Me quedo con Tesla?", "¿Sigo en Tesla?", "¿Sigo con Nvidia?",
        "¿Meto mis ahorros en oro?", "¿Paso mis ahorros a oro?", "¿Me pongo en oro?", "¿Meto todo en oro?", "¿Cuánto meto en oro?",
        "¿Subirá el oro?", "¿Va a subir el oro?", "¿Qué opinas de Nvidia?", "¿Qué piensas de Tesla?", "¿Qué te parece Nvidia?",
        "¿Contrato un plan de pensiones?", "¿Abro un plan de pensiones?", "¿Cuánto debería meter en el plan de pensiones?",
        "¿Opero con Tesla?", "¿Shorteo Tesla?", "¿Hago trading con Tesla?", "¿Echo dinero a Nvidia?",
        "¿Doblo la apuesta en Nvidia?", "¿Qué hago con la herencia?", "¿Qué hago con la paga extra?", "¿Compensa el oro?",
        "¿Me interesa Nvidia?", "¿Tesla tiene futuro?", "¿Renuevo el depósito?", "¿Me suscribo a letras del Tesoro?",
    ]

    @Test func u69HechosSiempreConSusDatosDetrasDeLaNegativa() throws {
        let fx = richFixture()
        for portfolio in [fx.portfolio as Portfolio?, nil] {
            let tag = portfolio == nil ? "sin cartera" : "con cartera"
            for q in Self.u69FactQuestions {
                let ans = answerQuestion(q, state: fx.state, portfolio: portfolio, book: fx.book, now: fx.now, calendar: cal)
                let lines = plainLines(ans)
                try #require(!lines.isEmpty, "[\(tag)] \(q): sin líneas")
                if ans.isAdviceRefusal {
                    #expect(lines[0] == investmentAdviceRefusal, "[\(tag)] \(q): \(lines[0])")
                    #expect(!lines.contains(investmentDataOnlyNote), "[\(tag)] \(q): nota repetida tras la negativa")
                } else {
                    #expect(!lines.contains(investmentAdviceRefusal), "[\(tag)] \(q)")
                }
                #expect(lines.filter { $0 == investmentAdviceRefusal }.count <= 1, "[\(tag)] \(q)")

                let data = ans.lines.filter { $0.id != "advice-refusal" && $0.id != "inv-data-only" }
                let underlying = routeAssistantQuestionWithoutAdviceGate(q, state: fx.state, portfolio: portfolio,
                                                                         now: fx.now, calendar: cal)
                if underlying == .unknown {
                    // U83: sin intención, detrás de la negativa van las fichas de preguntas sugeridas, no la cartera.
                    if ans.isAdviceRefusal {
                        #expect(data.isEmpty, "[\(tag)] \(q): datos ajenos a la pregunta: \(plainLines(ans))")
                        let suggested = suggestedAssistantChips(state: fx.state, portfolio: portfolio, now: fx.now, calendar: cal)
                        #expect(ans.chips == suggested, "[\(tag)] \(q): fichas que no son las sugeridas")
                    }
                } else {
                    // U84: también inversiones sin cartera llevan su respuesta («Aún no tienes inversiones importadas.»).
                    let expected = answerIntent(underlying, state: fx.state, portfolio: portfolio, book: fx.book,
                                                now: fx.now, calendar: cal).lines.filter { $0.id != "inv-data-only" }
                    #expect(!data.isEmpty, "[\(tag)] \(q): sin datos de \(underlying)")
                    #expect(data == expected, "[\(tag)] \(q): los datos no son los de \(underlying)")
                }
            }
        }
    }

    @Test func u69TodaRespuestaDeInversionesEmpiezaPorLaNotaOLaNegativa() throws {
        let fx = richFixture()
        let investmentQuestions = Self.u69FactQuestions + Self.u69AdviceQuestions + [
            "¿Cómo van mis inversiones?", "¿Cómo va Apple?", "¿Cómo va Ethereum?", "¿Cómo va Nvidia?",
            "¿Qué es lo que más ha subido hoy?", "¿Cuánto vale mi cartera?", "¿Cuánto tengo en acciones?",
            "¿Cómo van mis acciones de Apple?", "¿Cuánto llevo invertido en Apple?",
        ]
        var routedToInvestments = 0
        for portfolio in [fx.portfolio as Portfolio?, nil] {
            let tag = portfolio == nil ? "sin cartera" : "con cartera"
            for q in investmentQuestions {
                let underlying = routeAssistantQuestionWithoutAdviceGate(q, state: fx.state, portfolio: portfolio,
                                                                         now: fx.now, calendar: cal)
                guard case .investments = underlying else { continue }
                routedToInvestments += 1
                let ans = answerQuestion(q, state: fx.state, portfolio: portfolio, book: fx.book, now: fx.now, calendar: cal)
                let first = try #require(ans.lines.first, "[\(tag)] \(q)")
                let last = try #require(ans.lines.last, "[\(tag)] \(q)")
                for style in [RenderStyle.plain, .masked] {
                    // U89: la negativa va delante (sin nota) o el dato va delante y la nota es la última línea.
                    if ans.isAdviceRefusal {
                        #expect(render(first.parts, style) == investmentAdviceRefusal, "[\(tag)] \(q)")
                        #expect(!ans.lines.contains { $0.id == investmentDataOnlyLineID }, "[\(tag)] \(q): nota tras la negativa")
                    } else {
                        #expect(render(first.parts, style) != investmentDataOnlyNote, "[\(tag)] \(q): la nota va delante")
                        #expect(render(last.parts, style) == investmentDataOnlyNote, "[\(tag)] \(q): falta la nota al final")
                    }
                }
                // U89: la voz no lee la nota; con el ojo cerrado no dice ninguna cifra.
                let spoken = spokenAssistantAnswer(ans, privateMode: true)
                #expect(!spoken.contains(investmentDataOnlyNote), "[\(tag)] \(q): \(spoken)")
                #expect(!spokenAssistantAnswer(ans, privateMode: false).contains(investmentDataOnlyNote), "[\(tag)] \(q)")
                #expect(!spoken.contains("€") && !spoken.contains("%"), "[\(tag)] \(q): \(spoken)")
            }
        }
        #expect(routedToInvestments >= 20, "Muy pocas preguntas llegan a inversiones: \(routedToInvestments)")

        // La intención directa (la que elige el modelo del dispositivo) también: datos delante y la nota al final (U89).
        let intents: [AssistantIntent] = [
            .investments(positionQuery: nil, moversOnly: false), .investments(positionQuery: nil, moversOnly: true),
            .investments(positionQuery: "Apple", moversOnly: false), .investments(positionQuery: "Nvidia", moversOnly: false),
        ]
        for intent in intents {
            for portfolio in [fx.portfolio as Portfolio?, nil] {
                let ans = answerIntent(intent, state: fx.state, portfolio: portfolio, book: fx.book, now: fx.now, calendar: cal)
                #expect(plainLines(ans).last == investmentDataOnlyNote, "\(intent)")
                #expect(plainLines(ans).first != investmentDataOnlyNote, "\(intent)")
                #expect(plainLines(ans).count >= 2, "\(intent): la nota sola, sin datos")
            }
        }
        #expect(investmentDataOnlyNote == "Son datos, no una recomendación.")
    }

    @Test func u69ConsejosQuePasabanEmpiezanPorLaNegativa() {
        let fx = richFixture()
        for portfolio in [fx.portfolio as Portfolio?, nil] {
            let tag = portfolio == nil ? "sin cartera" : "con cartera"
            for q in Self.u69AdviceQuestions {
                let ans = answerQuestion(q, state: fx.state, portfolio: portfolio, book: fx.book, now: fx.now, calendar: cal)
                #expect(ans.isAdviceRefusal, "[\(tag)] \(q)")
                #expect(plainLines(ans).first == investmentAdviceRefusal, "[\(tag)] \(q): \(plainLines(ans))")
                #expect(!plainLines(ans).contains(investmentDataOnlyNote), "[\(tag)] \(q)")
            }
        }
    }

    // MARK: Ronda 3 (U81–U89)

    /// U81: si el modelo del dispositivo dice «consejo», la negativa va delante y DETRÁS los datos de la intención por reglas.
    @Test func u81ConsejoDelModeloNoQuitaLosDatos() throws {
        let fx = richFixture()
        for q in ["¿Cuánto me cuesta mantener la cuenta de imagin?", "¿Cuánto llevo en Mercadona?"] {
            let ans = answerQuestion(q, state: fx.state, portfolio: fx.portfolio, book: fx.book,
                                     modelIntent: .adviceRequest(positionQuery: nil), now: fx.now, calendar: cal)
            #expect(ans.isAdviceRefusal, "\(q)")
            #expect(plainLines(ans).first == investmentAdviceRefusal, "\(q)")
            let underlying = routeAssistantQuestionWithoutAdviceGate(q, state: fx.state, portfolio: fx.portfolio,
                                                                     now: fx.now, calendar: cal)
            if underlying == .unknown {
                #expect(plainLines(ans) == [investmentAdviceRefusal], "\(q): datos ajenos tras la negativa")
            } else {
                let expected = answerIntent(underlying, state: fx.state, portfolio: fx.portfolio, book: fx.book,
                                            now: fx.now, calendar: cal).lines.filter { $0.id != investmentDataOnlyLineID }
                #expect(Array(ans.lines.dropFirst()) == expected, "\(q): \(plainLines(ans))")
            }
        }
        let merca = answerQuestion("¿Cuánto llevo en Mercadona?", state: fx.state, portfolio: fx.portfolio, book: fx.book,
                                   modelIntent: .adviceRequest(positionQuery: nil), now: fx.now, calendar: cal)
        #expect(plainLines(merca).dropFirst().contains { $0.contains("Mercadona") && $0.contains(nb("73,50 €")) },
                "\(plainLines(merca))")
        #expect(!plainLines(merca).contains { $0.hasPrefix("Tus inversiones valen") })
    }

    /// U83: con intención desconocida, tras la negativa van las fichas sugeridas, no la cartera ni las fichas fijas.
    @Test func u83NegativaSinIntencionLlevaLasFichasSugeridas() throws {
        let fx = richFixture()
        for portfolio in [fx.portfolio as Portfolio?, nil] {
            for q in ["¿me conviene meter más?", "¿Merece la pena el gimnasio?"] {
                let underlying = routeAssistantQuestionWithoutAdviceGate(q, state: fx.state, portfolio: portfolio,
                                                                         now: fx.now, calendar: cal)
                try #require(underlying == .unknown, "\(q): \(underlying)")
                let ans = answerQuestion(q, state: fx.state, portfolio: portfolio, book: fx.book, now: fx.now, calendar: cal)
                #expect(ans.isAdviceRefusal, "\(q)")
                #expect(plainLines(ans) == [investmentAdviceRefusal], "\(q): \(plainLines(ans))")
                #expect(ans.chips == suggestedAssistantChips(state: fx.state, portfolio: portfolio, now: fx.now, calendar: cal), "\(q)")
            }
        }
    }

    /// U85: VoiceOver anuncia la primera línea que no es la nota ni la negativa; si solo hay esas, la que haya.
    @Test func u85VoiceOverAnunciaElDato() throws {
        let fx = richFixture()
        let budget = answerQuestion("¿Debería comprar menos para mi presupuesto de Comer fuera?", state: fx.state,
                                    portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        try #require(budget.lines.count >= 2)
        #expect(assistantAnnouncedLine(budget) == budget.lines[1])
        let inv = answerQuestion("Mis inversiones", state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        let announced = try #require(assistantAnnouncedLine(inv))
        #expect(announced.id != investmentDataOnlyLineID && announced.id != "advice-refusal")
        #expect(render(announced.parts, .plain).hasPrefix("Tus inversiones valen"))

        let refusalLine = BriefingLine(id: "advice-refusal", parts: [.text(investmentAdviceRefusal)])
        let noteLine = BriefingLine(id: investmentDataOnlyLineID, parts: [.text(investmentDataOnlyNote)])
        let onlyRefusal = AssistantAnswer(intent: .adviceRequest(positionQuery: nil), lines: [refusalLine], isAdviceRefusal: true)
        #expect(assistantAnnouncedLine(onlyRefusal) == refusalLine)
        let onlyNote = AssistantAnswer(intent: .investments(positionQuery: nil, moversOnly: false), lines: [noteLine])
        #expect(assistantAnnouncedLine(onlyNote) == noteLine)
        let dataThenNote = AssistantAnswer(intent: .investments(positionQuery: nil, moversOnly: false),
                                           lines: [BriefingLine(id: "d", parts: [.text("Dato.")]), noteLine])
        #expect(assistantAnnouncedLine(dataThenNote)?.id == "d")
        #expect(assistantAnnouncedLine(AssistantAnswer(intent: .unknown, lines: [])) == nil)
    }

    /// U86: con el ojo cerrado, la voz lee detrás de la negativa las líneas sin cifras.
    @Test func u86VozPrivadaLeeLasLineasSinCifrasTrasLaNegativa() {
        let refusalLine = BriefingLine(id: "advice-refusal", parts: [.text(investmentAdviceRefusal)])
        let period = BriefingLine(id: "unsupported-period",
                                  parts: [.text("Aún no sé contarte el gasto por días, semanas o años; sí por meses.")])
        let figure = BriefingLine(id: "fig", parts: [.text("Llevas "), .amount(12_345), .text(".")])
        let privacy = "Tienes el modo privado activado, así que no leo importes."

        let withoutFigures = AssistantAnswer(intent: .adviceRequest(positionQuery: nil), lines: [refusalLine, period],
                                             isAdviceRefusal: true)
        #expect(spokenAssistantAnswer(withoutFigures, privateMode: true)
                == "\(investmentAdviceRefusal) Aún no sé contarte el gasto por días, semanas o años; sí por meses.")

        let mixed = AssistantAnswer(intent: .adviceRequest(positionQuery: nil), lines: [refusalLine, period, figure],
                                    isAdviceRefusal: true)
        let spoken = spokenAssistantAnswer(mixed, privateMode: true)
        #expect(spoken == "\(investmentAdviceRefusal) Aún no sé contarte el gasto por días, semanas o años; sí por meses. \(privacy)")
        #expect(!spoken.contains("123") && !spoken.contains("euros"))
    }

    /// U87: si la pregunta nombra algo de inversión y la intención no es la de inversiones, la negativa va delante y
    /// después los datos de esa intención; sin sujeto de inversión, sin negativa.
    @Test func u87SujetoDeInversionConOtraIntencionLlevaLaNegativa() throws {
        let fx = richFixture()
        for portfolio in [fx.portfolio as Portfolio?, nil] {
            let tag = portfolio == nil ? "sin cartera" : "con cartera"
            let nvidia = "¿Cuánto me queda libre para meterle a Nvidia?"
            let freeAns = answerQuestion(nvidia, state: fx.state, portfolio: portfolio, book: fx.book, now: fx.now, calendar: cal)
            #expect(freeAns.isAdviceRefusal, "[\(tag)]")
            #expect(plainLines(freeAns).first == investmentAdviceRefusal, "[\(tag)] \(plainLines(freeAns))")
            let freeLines = answerIntent(.freeMoney, state: fx.state, portfolio: portfolio, book: fx.book,
                                         now: fx.now, calendar: cal).lines
            #expect(Array(freeAns.lines.dropFirst()) == freeLines, "[\(tag)] \(plainLines(freeAns))")

            let gold = "¿Qué me cobran mañana si compro oro?"
            let goldAns = answerQuestion(gold, state: fx.state, portfolio: portfolio, book: fx.book, now: fx.now, calendar: cal)
            #expect(plainLines(goldAns).first == investmentAdviceRefusal, "[\(tag)] \(plainLines(goldAns))")
            let goldUnderlying = routeAssistantQuestionWithoutAdviceGate(gold, state: fx.state, portfolio: portfolio,
                                                                         now: fx.now, calendar: cal)
            if case .upcomingCharges = goldUnderlying {} else { Issue.record("[\(tag)] \(gold): \(goldUnderlying)") }
            let upcoming = answerIntent(goldUnderlying, state: fx.state, portfolio: portfolio, book: fx.book,
                                        now: fx.now, calendar: cal).lines
            #expect(Array(goldAns.lines.dropFirst()) == upcoming, "[\(tag)] \(plainLines(goldAns))")

            let plain = answerQuestion("¿Cuánto me queda libre?", state: fx.state, portfolio: portfolio, book: fx.book,
                                       now: fx.now, calendar: cal)
            #expect(!plain.isAdviceRefusal, "[\(tag)]")
            #expect(!plainLines(plain).contains(investmentAdviceRefusal), "[\(tag)]")
            #expect(plain.intent == .freeMoney, "[\(tag)] \(plain.intent)")

            // También cuando la intención la elige el modelo del dispositivo.
            let viaModel = answerQuestion(nvidia, state: fx.state, portfolio: portfolio, book: fx.book,
                                          modelIntent: .freeMoney, now: fx.now, calendar: cal)
            #expect(plainLines(viaModel).first == investmentAdviceRefusal, "[\(tag)] modelo: \(plainLines(viaModel))")
        }
    }
}
