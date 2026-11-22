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

private func samplePortfolio() -> Portfolio {
    var p = Portfolio()
    p.transactions = [
        InvestmentTransaction(id: "t1", date: at(2026, 3, 2, 9), instrument: "IE00B4L5Y983",
                              name: "iShares Core MSCI World", assetClass: "FUND",
                              shares: 8, cashCents: -77_067, priceEUR: 96),
        InvestmentTransaction(id: "t2", date: at(2026, 6, 15, 13), instrument: "US0378331005",
                              name: "Apple", assetClass: "STOCK",
                              shares: 3, cashCents: -54_100, priceEUR: 180),
        InvestmentTransaction(id: "t3", date: at(2026, 7, 1, 10), instrument: "ETH",
                              name: "Ethereum", assetClass: "CRYPTO",
                              shares: Decimal(string: "0.5")!, cashCents: -100_000, priceEUR: 2000),
    ]
    return p
}

private func sampleState() -> LedgerState {
    var state = LedgerState()
    state.balances[.rev] = ManualBalance(cents: 34_020, setAt: nov(20, 8), origin: .bank)
    state.movements = [
        Movement(bank: .rev, amountCents: -4_250, merchant: "Mercadona Torrejón", kind: .payment, source: .bank,
                 date: nov(18, 18), isShop: true, bankRef: "b1", bankStatus: .booked),
        Movement(bank: .rev, amountCents: -1_990, merchant: "Apple Store", kind: .payment, source: .bank,
                 date: nov(17, 12), isShop: true, bankRef: "b2", bankStatus: .booked),
    ]
    return state
}

@Suite struct AssistantRoutingTests {
    // MARK: Detector de peticiones de consejo (A3, J7, J15, J21(c), J22, C2)

    @Test(arguments: [
        // Preguntas directas en español
        "¿Qué acciones compro?",
        "¿Debería comprar más Apple?",
        "¿Vendo mis acciones?",
        "¿Vendo Apple ahora?",
        "¿Cuánto invierto este mes?",
        "¿Dónde invierto 1.000 euros?",
        "¿En qué invierto mi dinero?",
        "¿Me conviene vender el ETF?",
        "¿Me recomiendas comprar oro?",
        "¿Qué me recomiendas hacer con mi cartera?",
        "¿Qué hago con mis acciones?",
        "¿Qué hago con Apple?",
        "¿Es buen momento para comprar?",
        "¿Es buen momento para entrar en bolsa?",
        "¿Es hora de vender?",
        "¿Aguanto o vendo?",
        "¿Mantengo mis posiciones?",
        "¿Rebalanceo la cartera?",
        "¿Debería diversificar más?",
        "¿Aprovecho la caída?",
        "¿Promedio a la baja?",
        "¿Tomo beneficios en Apple?",
        "¿Merece la pena invertir en bitcoin?",
        "¿Vale la pena comprar fondos?",
        "¿Va a subir Apple mañana?",
        "¿Bajará la bolsa esta semana?",
        "¿Qué opinas de mi cartera?",
        "¿Mejor esperar antes de entrar?",
        // C2: asignación, salida, rotación, gerundios, clíticos, inglés `invest*` y Unicode ancho completo / matemático
        "¿Meto 500 € en MSCI?",
        "¿Pongo más dinero en Apple?",
        "¿Salgo de Ethereum?",
        "¿Me salgo de bolsa?",
        "¿Entro en Apple?",
        "¿Me deshago de Apple?",
        "¿Liquido mi cartera?",
        "¿Cambio mis acciones por bonos?",
        "¿Qué ETF elegir?",
        "¿Me quedo con Apple?",
        "¿Sigo aportando al fondo?",
        "¿Sigo comprando Apple?",
        "¿Sigo vendiendo acciones?",
        "¿Sigo invirtiendo en MSCI?",
        "¿Sigo manteniendo Apple?",
        "¿Sigo aguantando Ethereum?",
        "¿Comprarme acciones de Apple?",
        "¿Véndelo ya?",
        "Invest in Apple?",
        "Where to invest?",
        "Investing in gold?",
        "ｖｅｎｄｏ Apple",
        "ｃｏｍｐｒａｒ ETF",
        "𝐯𝐞𝐧𝐝𝐨 Apple",
        // R1 & R3: «venta» sin determinante, «mejor valor/posición/rendimiento» y «retiro/cierro» de bolsa/cartera
        "Venta Apple",
        "Venta ahora",
        "¿Hago venta en bolsa?",
        "¿Cuál es el mejor valor de bolsa?",
        "¿Cuál es la mejor posición para mi cartera?",
        "¿Qué fondo tiene mejor rendimiento?",
        "¿Retiro mi dinero de bolsa?",
        "¿Retiro todo de mi cartera?",
        "¿Cierro mi posición en Apple?",
        "No compres nada",
        // Tabla completa de J15 / J22
        "mejor esperar", "espera a que baje", "no toques tu cartera", "quédate como estás",
        "sal de esa posición", "entra en el fondo", "refuerza tu posición", "reduce exposición",
        "toma beneficios", "deshazte de", "acumula", "promedia a la baja",
        "time to take profits", "stay put", "get out", "Oye, compra ahora", "mejor compra ya",
        "si compras hoy", "convendría esperar", "tendrías que", "habría que",
        "te conviene vender", "mantén tus acciones", "aprovecha la caída", "yo que tú compraría",
        "te recomiendo que vendas", "no vendas", "invierte un poco cada mes",
        "buen momento de comprar", "es hora de vender", "vende.", "you should sell",
        "buy more", "hold", "Should I buy Apple?", "What should I invest in?",
        // Trucos de escritura / ofuscación (J15(b), J22)
        "ve\u{00AD}nde Apple", "ven\u{200B}do todo", "vеndo Apple", "comprаr acciones",
        "ven\nde", "ven-de", "ven-\nde", "v e n d o Apple", "v.e.n.d.o", "venđe", "vendø",
        "c o m p r a r ETF", "rebalancea", "mete dinero en oro", "Compra de nuevo",
        "purchase now", "bυy Apple",
    ]) func detectaPeticionesDeConsejo(_ question: String) {
        let portfolio = samplePortfolio()
        #expect(isAdviceRequest(question, portfolio: portfolio), "\(question)")
        let intent = routeAssistantQuestion(question, state: sampleState(), portfolio: portfolio, now: nov(20), calendar: cal)
        if case .adviceRequest = intent {
            // correcto
        } else {
            Issue.record("Esperaba .adviceRequest para «\(question)», salió \(intent)")
        }
    }

    @Test(arguments: [
        // Preguntas factuales neutras sobre inversiones (NO son consejo)
        "¿Cómo van mis inversiones?",
        "¿Cuánto vale mi cartera?",
        "¿Cuánto valen mis acciones?",
        "¿Cómo va Apple?",
        "¿Cuánto tengo en MSCI World?",
        "¿Cuánto tengo en Ethereum?",
        "¿Cuánto llevo invertido?",
        "¿Cuánto he ganado con mis inversiones?",
        "¿Qué es lo que más ha subido hoy?",
        "¿Cuál ha bajado más en mi cartera?",
        // I1: preguntas factuales que antes daban falso positivo
        "¿Qué es lo que mejor ha ido en mi cartera?",
        "¿Qué acción ha ido mejor hoy?",
        "¿Cuál de mis fondos ha ido mejor?",
        "¿Cómo va el presupuesto para compras?",
        "¿Cuántas compras hice este mes?",
        "¿Qué compras tengo este mes?",
        "¿Cuánto me queda para compras?",
        "¿Compras del mes pasado?",
        "¿Qué compré en Mercadona?",
        "¿Cuánto compré el mes pasado?",
        "¿Cuánto compré en Apple Store?",
        "¿Cuánto compramos en Mercadona?",
        "¿Cómo va Ørsted?",
        "¿Cuánto gasté en Straße?",
        "¿Cuánto gasté en Møller?",
        "¿Cuándo espero el cobro de Apple?",
        "¿Qué dividendos espero este mes?",
        "¿Cuánto tengo que dejar en Revolut?",
        "¿Cuánto dinero tengo que meter en imagin?",
        "¿Mi alquiler va a subir?",
        "¿Qué hago con el presupuesto de Comer fuera?",
        // R2: palabras cotidianas que empiezan por compr-/manten-/acumul- (no son consejos)
        "¿Puedes comprobar mi saldo?",
        "Comprueba mis presupuestos",
        "¿Cuánto dinero tengo comprometido este mes?",
        "¿Cuánto gasté en mantenimiento este mes?",
        "¿Cuál es mi gasto acumulado este mes?",
        "Venta de garaje",
        "Mi venta en Wallapop",
        // Preguntas bancarias cotidianas
        "¿Cuánto gasté en compras este mes?",
        "¿Cuánto llevo en compras?",
        "¿Cuál fue mi compra más cara?",
        "¿Qué compras hice en octubre?",
        "¿Cuánto compré en Mercadona?",
        "¿Cuánto dinero entra en Revolut este mes?",
        "¿Qué cobros espero esta semana?",
        "¿Qué tengo que pagar este mes?",
        "¿Cuánto puedo gastar hasta fin de mes?",
        "¿Cuánto tengo en total?",
        "¿Me quedo corto en algún banco?",
        "¿Qué ha pasado desde ayer?",
    ]) func noBloqueaPreguntasFactuales(_ question: String) {
        #expect(!isAdviceRequest(question, portfolio: samplePortfolio()), "Falso positivo en: \(question)")
    }

    // MARK: Enrutador determinista (todas las intenciones de A3 + I2 + I3)

    @Test func enrutaSaldos() {
        let state = sampleState()
        #expect(routeAssistantQuestion("¿Cuánto tengo?", state: state, portfolio: nil, now: nov(20), calendar: cal) == .balances(bank: nil))
        #expect(routeAssistantQuestion("¿Cuál es mi saldo en Revolut?", state: state, portfolio: nil, now: nov(20), calendar: cal) == .balances(bank: .rev))
        #expect(routeAssistantQuestion("¿Cuánto me queda en imagin?", state: state, portfolio: nil, now: nov(20), calendar: cal) == .balances(bank: .ima))
        #expect(routeAssistantQuestion("saldo en Trade Republic", state: state, portfolio: nil, now: nov(20), calendar: cal) == .balances(bank: .tr))
    }

    @Test func enrutaGastosPorMesCategoriaComercioYBanco() {
        let state = sampleState()
        #expect(routeAssistantQuestion("¿Cuánto llevo gastado este mes?", state: state, portfolio: nil, now: nov(20), calendar: cal)
            == .spending(month: .current, category: nil, merchant: nil, bank: nil))
        #expect(routeAssistantQuestion("¿Cuánto gasté el mes pasado?", state: state, portfolio: nil, now: nov(20), calendar: cal)
            == .spending(month: .previous, category: nil, merchant: nil, bank: nil))
        #expect(routeAssistantQuestion("¿Cuánto gasté en octubre?", state: state, portfolio: nil, now: nov(20), calendar: cal)
            == .spending(month: .specific(year: 2026, month: 10), category: nil, merchant: nil, bank: nil))
        #expect(routeAssistantQuestion("¿Cuánto gasté en diciembre?", state: state, portfolio: nil, now: at(2026, 2, 10), calendar: cal)
            == .spending(month: .specific(year: 2025, month: 12), category: nil, merchant: nil, bank: nil))
        #expect(routeAssistantQuestion("¿Cuánto gasté en octubre de 2019?", state: state, portfolio: nil, now: nov(20), calendar: cal)
            == .spending(month: .specific(year: 2019, month: 10), category: nil, merchant: nil, bank: nil))
        #expect(routeAssistantQuestion("¿Cuánto llevo en Comer fuera?", state: state, portfolio: nil, now: nov(20), calendar: cal)
            == .spending(month: .current, category: .comerFuera, merchant: nil, bank: nil))
        #expect(routeAssistantQuestion("¿Cuánto gasté en compras este mes?", state: state, portfolio: nil, now: nov(20), calendar: cal)
            == .spending(month: .current, category: .compras, merchant: nil, bank: nil))
        #expect(routeAssistantQuestion("¿Cuánto llevo en Mercadona?", state: state, portfolio: nil, now: nov(20), calendar: cal)
            == .spending(month: .current, category: nil, merchant: "Mercadona", bank: nil))
        // Comercio aún sin pagos en el libro, combinado con mes y puntuación:
        #expect(routeAssistantQuestion("¿Cuánto gasté en Zara en octubre?", state: state, portfolio: nil, now: nov(20), calendar: cal)
            == .spending(month: .specific(year: 2026, month: 10), category: nil, merchant: "Zara", bank: nil))
        #expect(routeAssistantQuestion("¿Cuánto gasté en octubre en Zara?", state: state, portfolio: nil, now: nov(20), calendar: cal)
            == .spending(month: .specific(year: 2026, month: 10), category: nil, merchant: "Zara", bank: nil))
        // I3: coma antes del sufijo temporal, «en el último mes», «en Revolut», categoría vs comercio genérico.
        #expect(routeAssistantQuestion("¿Cuánto gasté en Zara, el mes pasado?", state: state, portfolio: nil, now: nov(20), calendar: cal)
            == .spending(month: .previous, category: nil, merchant: "Zara", bank: nil))
        #expect(routeAssistantQuestion("¿Cuánto gasté en el último mes?", state: state, portfolio: nil, now: nov(20), calendar: cal)
            == .spending(month: .previous, category: nil, merchant: nil, bank: nil))
        #expect(routeAssistantQuestion("¿Cuánto gasté en lo que va de mes?", state: state, portfolio: nil, now: nov(20), calendar: cal)
            == .spending(month: .current, category: nil, merchant: nil, bank: nil))
        #expect(routeAssistantQuestion("¿Cuánto gasté en Revolut?", state: state, portfolio: nil, now: nov(20), calendar: cal)
            == .spending(month: .current, category: nil, merchant: nil, bank: .rev))

        var withRest = state
        withRest.movements.append(Movement(bank: .rev, amountCents: -2_000, merchant: "Restaurante Sol", kind: .payment,
                                           source: .bank, date: nov(15, 21), isShop: true, bankRef: "r1", bankStatus: .booked))
        withRest.movements.append(Movement(bank: .rev, amountCents: -999, merchant: "APPLE.COM/BILL", kind: .payment,
                                           source: .bank, date: nov(14, 12), isShop: true, bankRef: "a1", bankStatus: .booked))
        // Preguntar por «restaurante» va a categoría Comer fuera, no solo a «Restaurante Sol».
        #expect(routeAssistantQuestion("¿Cuánto gasté en restaurante este mes?", state: withRest, portfolio: nil, now: nov(20), calendar: cal)
            == .spending(month: .current, category: .comerFuera, merchant: nil, bank: nil))
        // «APPLE.COM/BILL» no contamina el nombre extraído al preguntar por Apple.
        #expect(routeAssistantQuestion("¿Cuánto gasté en Apple este mes?", state: withRest, portfolio: nil, now: nov(20), calendar: cal)
            == .spending(month: .current, category: nil, merchant: "Apple", bank: nil))
    }

    @Test func precedenciaDeEnrutadoSinSecuestros() {
        let state = sampleState()
        var portfolio = samplePortfolio()
        portfolio.transactions.append(
            InvestmentTransaction(id: "cb1", date: at(2026, 4, 1, 9), instrument: "ES0140609019",
                                  name: "CaixaBank", assetClass: "STOCK", shares: 10, cashCents: -5_000, priceEUR: 5)
        )
        portfolio.transactions.append(
            InvestmentTransaction(id: "san1", date: at(2026, 4, 2, 9), instrument: "ES0113900J37",
                                  name: "Banco Santander", assetClass: "STOCK", shares: 10, cashCents: -4_000, priceEUR: 4)
        )

        // I2 #1: «al día» en dinero libre nunca es secuestrado por el resumen diario.
        #expect(routeAssistantQuestion("¿Cuánto puedo gastar al día?", state: state, portfolio: portfolio, now: nov(20), calendar: cal)
            == .freeMoney)
        #expect(routeAssistantQuestion("¿Cuánto dinero tengo libre al día?", state: state, portfolio: portfolio, now: nov(20), calendar: cal)
            == .freeMoney)

        // I2 #2: «más bajo» (menor) en saldo o pago nunca va a movers de inversiones.
        #expect(routeAssistantQuestion("¿Qué banco tiene el saldo más bajo?", state: state, portfolio: portfolio, now: nov(20), calendar: cal)
            == .balances(bank: nil))
        #expect(routeAssistantQuestion("¿Cuál es mi saldo más bajo?", state: state, portfolio: portfolio, now: nov(20), calendar: cal)
            == .balances(bank: nil))
        #expect(routeAssistantQuestion("¿Qué es lo que mejor ha ido en mi cartera?", state: state, portfolio: portfolio, now: nov(20), calendar: cal)
            == .investments(positionQuery: nil, moversOnly: true))
        #expect(routeAssistantQuestion("¿Cuál es lo que más bajó hoy?", state: state, portfolio: portfolio, now: nov(20), calendar: cal)
            == .investments(positionQuery: nil, moversOnly: true))

        // I2 #3: «llevo» con una posición de cartera va a inversiones, no a comercio sin pagos.
        #expect(routeAssistantQuestion("¿Cuánto llevo en MSCI World?", state: state, portfolio: portfolio, now: nov(20), calendar: cal)
            == .investments(positionQuery: "IE00B4L5Y983", moversOnly: false))
        #expect(routeAssistantQuestion("¿Cuánto llevo ganado en Apple?", state: state, portfolio: portfolio, now: nov(20), calendar: cal)
            == .investments(positionQuery: "US0378331005", moversOnly: false))

        // I2 #4: saldo en CaixaBank / saldo en cada banco van a saldos aunque el dueño tenga acciones de bancos.
        #expect(routeAssistantQuestion("¿Cuál es mi saldo en CaixaBank?", state: state, portfolio: portfolio, now: nov(20), calendar: cal)
            == .balances(bank: .ima))
        #expect(routeAssistantQuestion("¿Cuánto tengo en CaixaBank?", state: state, portfolio: portfolio, now: nov(20), calendar: cal)
            == .balances(bank: .ima))
        #expect(routeAssistantQuestion("¿Cuánto saldo tengo en cada banco?", state: state, portfolio: portfolio, now: nov(20), calendar: cal)
            == .balances(bank: nil))
    }

    @Test func distingueComercioYPosicionConElMismoNombre() {
        let state = sampleState()
        let portfolio = samplePortfolio()
        #expect(routeAssistantQuestion("¿Cuánto gasté en Apple este mes?", state: state, portfolio: portfolio, now: nov(20), calendar: cal)
            == .spending(month: .current, category: nil, merchant: "Apple", bank: nil))
        #expect(routeAssistantQuestion("¿Cómo va Apple?", state: state, portfolio: portfolio, now: nov(20), calendar: cal)
            == .investments(positionQuery: "US0378331005", moversOnly: false))
        #expect(routeAssistantQuestion("¿Cuánto tengo en MSCI World?", state: state, portfolio: portfolio, now: nov(20), calendar: cal)
            == .investments(positionQuery: "IE00B4L5Y983", moversOnly: false))
        #expect(routeAssistantQuestion("¿Qué suscripciones tengo de Apple?", state: state, portfolio: portfolio, now: nov(20), calendar: cal)
            == .subscriptions)
    }

    @Test func enrutaRestoDeIntencionesDeA3() {
        let state = sampleState()
        let portfolio = samplePortfolio()
        #expect(routeAssistantQuestion("¿Cuáles fueron mis mayores pagos este mes?", state: state, portfolio: portfolio, now: nov(20), calendar: cal)
            == .biggestPayments(month: .current))
        #expect(routeAssistantQuestion("¿Cuál fue mi pago más grande el mes pasado?", state: state, portfolio: portfolio, now: nov(20), calendar: cal)
            == .biggestPayments(month: .previous))
        #expect(routeAssistantQuestion("¿Qué suscripciones tengo?", state: state, portfolio: portfolio, now: nov(20), calendar: cal)
            == .subscriptions)
        #expect(routeAssistantQuestion("¿Qué cobros vienen y me quedo corto en algún banco?", state: state, portfolio: portfolio, now: nov(20), calendar: cal)
            == .upcomingCharges(bank: nil))
        #expect(routeAssistantQuestion("¿Me va a faltar saldo en Revolut?", state: state, portfolio: portfolio, now: nov(20), calendar: cal)
            == .upcomingCharges(bank: .rev))
        #expect(routeAssistantQuestion("¿Cómo van mis presupuestos?", state: state, portfolio: portfolio, now: nov(20), calendar: cal)
            == .budgets(category: nil))
        #expect(routeAssistantQuestion("¿Cómo va el presupuesto de Comer fuera?", state: state, portfolio: portfolio, now: nov(20), calendar: cal)
            == .budgets(category: .comerFuera))
        #expect(routeAssistantQuestion("¿Qué ingresos han entrado este mes?", state: state, portfolio: portfolio, now: nov(20), calendar: cal)
            == .income(month: .current))
        #expect(routeAssistantQuestion("¿Qué traspasos hice entre mis cuentas el mes pasado?", state: state, portfolio: portfolio, now: nov(20), calendar: cal)
            == .ownTransfers(month: .previous))
        #expect(routeAssistantQuestion("¿Cuánto dinero libre tengo?", state: state, portfolio: portfolio, now: nov(20), calendar: cal)
            == .freeMoney)
        #expect(routeAssistantQuestion("¿Cuánto puedo gastar hasta fin de mes?", state: state, portfolio: portfolio, now: nov(20), calendar: cal)
            == .freeMoney)
        #expect(routeAssistantQuestion("¿Cómo van mis inversiones?", state: state, portfolio: portfolio, now: nov(20), calendar: cal)
            == .investments(positionQuery: nil, moversOnly: false))
        #expect(routeAssistantQuestion("¿Qué es lo que más ha subido hoy?", state: state, portfolio: portfolio, now: nov(20), calendar: cal)
            == .investments(positionQuery: nil, moversOnly: true))
        #expect(routeAssistantQuestion("¿Qué ha pasado desde ayer?", state: state, portfolio: portfolio, now: nov(20), calendar: cal)
            == .briefingRecap)
        #expect(routeAssistantQuestion("¿Qué tiempo hace en Madrid?", state: state, portfolio: portfolio, now: nov(20), calendar: cal)
            == .unknown)
        #expect(routeAssistantQuestion("   ", state: state, portfolio: portfolio, now: nov(20), calendar: cal) == .unknown)
    }

    // MARK: Contrato con el modelo (A2, A6, J21(d), C1, Minor 1)

    @Test func elPromptDelModeloNoLlevaDatosBancarios() {
        // U7: firma sin `LedgerState` + comprobación frente a un libro rico con importes y comercios ajenos a la pregunta.
        let fn: (String, Date, Calendar) -> String = assistantRoutingPrompt
        let state = sampleState()
        let prompt = fn("¿Cuánto llevo en Mercadona?", nov(20), cal)
        #expect(prompt.contains("Mes actual: 2026-11"))
        #expect(prompt.contains("Pregunta: ¿Cuánto llevo en Mercadona?"))
        #expect(!prompt.contains("€"))
        for (_, bal) in state.balances {
            let formatted = formatEUR(bal.cents).replacingOccurrences(of: "\u{00A0}€", with: "")
            #expect(!prompt.contains(formatted), "El prompt no puede filtrar el saldo \(formatted)")
        }
        for m in state.movements {
            let formatted = formatEUR(abs(m.amountCents)).replacingOccurrences(of: "\u{00A0}€", with: "")
            #expect(!prompt.contains(formatted), "El prompt no puede filtrar el importe \(formatted)")
            if let merchant = m.merchant, !merchant.localizedCaseInsensitiveContains("Mercadona") {
                #expect(!prompt.contains(merchant), "El prompt no puede filtrar el comercio \(merchant)")
            }
        }
        #expect(assistantRoutingInstructions.contains("Onyx"))
        #expect(assistantRoutingInstructions.contains("CONSEJO"))
    }

    @Test func elParserDelModeloValidaEstrictamenteYBloqueaInyecciones() {
        let portfolio = samplePortfolio()
        // Casos válidos
        #expect(parseAssistantModelRoute("SALDO banco=rev", originalQuestion: "¿Cuánto tengo en Revolut?",
                                         portfolio: portfolio) == .balances(bank: .rev))
        #expect(parseAssistantModelRoute("GASTO mes=2026-10 comercio=\"Mercadona\"", originalQuestion: "¿Cuánto en Mercadona en octubre?",
                                         portfolio: portfolio)
            == .spending(month: .specific(year: 2026, month: 10), category: nil, merchant: "Mercadona", bank: nil))
        #expect(parseAssistantModelRoute("GASTO comercio=\"McDonald's\"", originalQuestion: "¿Cuánto en McDonald's?",
                                         portfolio: portfolio)
            == .spending(month: .current, category: nil, merchant: "McDonald's", bank: nil))
        // M3: comercios con guion o «&» y tilde devuelta en NFC.
        #expect(parseAssistantModelRoute("GASTO comercio=\"Basic-Fit\"", originalQuestion: "¿Cuánto gasté en Basic-Fit?",
                                         portfolio: portfolio)
            == .spending(month: .current, category: nil, merchant: "Basic-Fit", bank: nil))
        #expect(parseAssistantModelRoute("GASTO comercio=\"El Corte Inglés\"", originalQuestion: "¿Cuánto gasté en El Corte Inglés?",
                                         portfolio: portfolio)
            == .spending(month: .current, category: nil, merchant: "El Corte Inglés", bank: nil))
        #expect(parseAssistantModelRoute("PRESUPUESTOS categoria=comerFuera", originalQuestion: "Presupuesto de bares",
                                         portfolio: portfolio) == .budgets(category: .comerFuera))
        #expect(parseAssistantModelRoute("INVERSIONES movers=si", originalQuestion: "¿Qué subió más?",
                                         portfolio: portfolio)
            == .investments(positionQuery: nil, moversOnly: true))

        // C1: el modelo intenta inyectar cirílico, símbolos €/% o subcadenas de 1 letra en `comercio` -> rechazado (nil).
        for injected in [
            "GASTO mes=2026-08 comercio=\"Mercadona (веиде!!)\"",
            "GASTO comercio=\"€Mercadona%\"",
            "GASTO comercio=\"Mercadona S.A.\"",
            "GASTO comercio=\"a\"",
            "GASTO comercio=\"en\"",
            "GASTO comercio=\"Compra Apple ya\"",
        ] {
            #expect(parseAssistantModelRoute(injected, originalQuestion: "¿Cuánto gasté en Mercadona en agosto?",
                                             portfolio: portfolio) == nil, "\(injected)")
        }

        // Minor 1: parámetros irrelevantes para el comando o duplicados -> rechazados (nil).
        for bad in [
            "", "Claro, te cuento tus saldos", "OTRO", "SALDO banco=bbva", "GASTO mes=2026-13",
            "GASTO categoria=inventada", "SALDO foo=bar", "GASTO comercio=\"sin cerrar",
            "SALDO mes=2025-01", "RESUMEN banco=rev", "SUSCRIPCIONES mes=actual", "SALDO banco=rev banco=ima",
        ] {
            #expect(parseAssistantModelRoute(bad, originalQuestion: "¿Cuánto tengo?",
                                             portfolio: portfolio) == nil, "\(bad)")
        }

        // Seguridad: aunque el modelo clasifique mal una petición de consejo como INVERSIONES o SALDO, manda `isAdviceRequest`.
        let forced = parseAssistantModelRoute("INVERSIONES posicion=Apple", originalQuestion: "¿Debería comprar más Apple?",
                                              portfolio: portfolio)
        #expect(forced == .adviceRequest(positionQuery: "US0378331005"))
    }

    @Test func fichasSugeridasSeAdaptanALoQueHay() {
        var state = LedgerState()
        let minimal = suggestedAssistantChips(state: state, portfolio: nil, now: nov(20), calendar: cal)
        #expect(minimal.count >= 4 && minimal.count <= 6)
        #expect(!minimal.contains { $0.id == "investments" })
        #expect(!minimal.contains { $0.id == "budgets" })

        state.budgets.monthlyCents = 80_000
        let full = suggestedAssistantChips(state: state, portfolio: samplePortfolio(), now: nov(20), calendar: cal)
        #expect(full.contains { $0.id == "investments" })
        #expect(full.contains { $0.id == "budgets" })
    }

    @Test func auditoriaC1C2I4BloqueaBypassesYValidaTramoOriginal() {
        let state = sampleState()
        let portfolio = samplePortfolio()

        // C1: ISINs, SP500, consejo/advice, determinantes en bolsa, verbos de cartera, plurales y confusables extendidos.
        for advice in [
            "¿Meto 500 € en SP500?",
            "¿Meto 500 € en US0378331005?",
            "¿Debería entrar en IE00B4L5Y983?",
            "Dame un consejo sobre Apple",
            "¿Qué consejo me das sobre mis inversiones?",
            "Any advice on Apple?",
            "¿Hago una venta en bolsa?",
            "¿Hago una compra de Apple?",
            "¿Programo una compra de MSCI World?",
            "¿Aumento mi posición en Apple?",
            "¿Amplío mi posición en MSCI World?",
            "¿Apuesto por Apple?",
            "¿Qué piensas de Apple?",
            "¿Va a caer Apple?",
            "¿Qué acciones merecen la pena?",
            "¿Valen la pena mis ETFs?",
            "¿Meto 500 € en Tesla?",
            "¿Pongo 1.000 euros en Nvidia?",
            "Will Apple go up?",
            "Dump Apple",
            "vɇndo Apple",
            "ħold Apple",
            "v е\u{0301} n d o Apple",
            "Ayer compré Apple, ¿que compre más?",
            "Ayer compré Apple, ¿que c o m p r e más?",
            "¿Es buena una compra de Apple?",
            "¿Meto 500 € en Tesla desde Revolut?",
        ] {
            #expect(isAdviceRequest(advice, portfolio: portfolio), "Debió rechazar como consejo: \(advice)")
        }

        // C2: el tramo devuelto de `originalQuestion` tampoco puede contener €/%/$/cirílico, categorías ni interrogativos;
        // preposiciones al borde («en Mercadona») se recortan limpiamente.
        #expect(parseAssistantModelRoute("GASTO comercio=\"Tienda 50\"", originalQuestion: "¿Cuánto gasté en Tienda €50?",
                                         portfolio: portfolio) == nil)
        #expect(parseAssistantModelRoute("GASTO comercio=\"Tienda 50\"", originalQuestion: "¿Cuánto gasté en Tienda Ж50?",
                                         portfolio: portfolio) == nil)
        #expect(parseAssistantModelRoute("GASTO comercio=\"cuanto gaste\"", originalQuestion: "¿Cuánto gasté en comida este mes?",
                                         portfolio: portfolio) == nil)
        #expect(parseAssistantModelRoute("GASTO comercio=\"Supermercado\"", originalQuestion: "¿Cuánto gasté en Supermercado?",
                                         portfolio: portfolio) == nil)
        #expect(parseAssistantModelRoute("GASTO comercio=\"en Mercadona\"", originalQuestion: "¿Cuánto gasté en Mercadona?",
                                         portfolio: portfolio) == .spending(month: .current, category: nil, merchant: "Mercadona", bank: nil))

        // I4: «¿Cuánto llevo gastado en Apple?» sin pagos previos en tienda sigue siendo gasto, no cartera.
        var emptyShopState = state
        emptyShopState.movements.removeAll { ($0.merchant ?? "").lowercased().contains("apple") }
        let appleSpend = routeAssistantQuestion("¿Cuánto llevo gastado en Apple?", state: emptyShopState, portfolio: portfolio,
                                                now: nov(20), calendar: cal)
        #expect(appleSpend == .spending(month: .current, category: nil, merchant: "Apple", bank: nil))

        // Minor 7: «¿Qué me han cobrado este mes?» es gasto, no ingreso.
        let charged = routeAssistantQuestion("¿Qué me han cobrado este mes?", state: state, portfolio: portfolio,
                                             now: nov(20), calendar: cal)
        #expect(charged == .spending(month: .current, category: nil, merchant: nil, bank: nil))

        // Minor 11: un año fuera de rango no cae al año actual.
        let oldYear = routeAssistantQuestion("¿Cuánto gasté en octubre de 1999?", state: state, portfolio: portfolio,
                                             now: nov(20), calendar: cal)
        #expect(oldYear == .spending(month: .specific(year: 1999, month: 10), category: nil, merchant: nil, bank: nil))
    }

    // MARK: U1 — Detector estructural de peticiones de consejo (dos tablas literales)

    private static func merchantKeys(in state: LedgerState) -> Set<String> {
        var keys = Set<String>()
        for m in state.movements {
            for raw in [m.merchant, m.bankMerchant].compactMap({ $0 }) {
                let k = normalizeMerchant(raw)
                if !k.isEmpty { keys.insert(k) }
            }
        }
        return keys
    }

    @Test func detectaPeticionesDeConsejoDelInforme() throws {
        let state = sampleState()
        let known = Self.merchantKeys(in: state)
        let questions = [
            "¿Añado 100 € al fondo indexado?",
            "¿Añado más al MSCI World?",
            "¿Es Apple una buena inversión?",
            "¿Apple es una buena inversión?",
            "¿Suelto mis acciones?",
            "¿Pillo acciones de Apple?",
            "¿Qué ETF me pillo?",
            "¿Cojo más acciones?",
            "¿Me hago con acciones de Tesla?",
            "¿Recompro Apple?",
            "¿Revendo Apple?",
            "¿Cancelo el plan de inversión?",
            "¿Subo la aportación al ETF?",
            "¿Cuánto aporto al mes?",
            "¿Hago DCA en bitcoin?",
            "¿Bendo mis acciones?",
            "¿Bendo Apple?",
            "¿Cuánto debería inbertir?",
            "¿Cuánto imbierto?",
            "¿Kompro bitcoin?",
            "¿V3ndo Apple?",
            "¿C0mpro Tesla?",
            "¿Apuesto por Nvidia?",
            "¿Subirá Nvidia?",
            "¿Le meto más a Tesla?",
            "¿Qué hago con Tesla?",
            "¿Qué hago con 1000 €?",
            "¿Está cara Tesla?",
            "¿Es rentable Tesla?",
            "¿Me compensa Apple?",
            "¿Bitcoin o Ethereum?",
            "Is Apple overvalued?",
            "Which ETF?",
        ]
        for portfolio in [samplePortfolio() as Portfolio?, nil] {
            let tag = portfolio == nil ? "sin cartera" : "con cartera"
            for q in questions {
                #expect(isAdviceRequest(q, portfolio: portfolio, knownMerchants: known), "[\(tag)] isAdviceRequest: \(q)")
                let intent = routeAssistantQuestion(q, state: state, portfolio: portfolio, now: nov(20), calendar: cal)
                if case .adviceRequest = intent {
                } else {
                    Issue.record("[\(tag)] Esperaba .adviceRequest para «\(q)», salió \(intent)")
                }
                let ans = answerQuestion(q, state: state, portfolio: portfolio, book: AccountBook(), now: nov(20), calendar: cal)
                #expect(ans.isAdviceRefusal, "[\(tag)] isAdviceRefusal: \(q)")
                let firstLine = try #require(ans.lines.first, "[\(tag)] sin líneas para \(q)")
                #expect(render(firstLine.parts, .plain) == investmentAdviceRefusal, "[\(tag)] negativa literal: \(q)")
            }
        }
    }

    @Test func noBloqueaFalsosPositivosDelInforme() {
        var state = sampleState()
        state.movements += [
            Movement(bank: .rev, amountCents: -250, merchant: "Vending Sur", kind: .payment, source: .bank,
                     date: nov(10, 11), isShop: true, bankRef: "v1", bankStatus: .booked),
            Movement(bank: .rev, amountCents: -600, merchant: "El vendedor de lotería", kind: .payment, source: .bank,
                     date: nov(11, 11), isShop: true, bankRef: "v2", bankStatus: .booked),
            Movement(bank: .rev, amountCents: -1_800, merchant: "Vendome", kind: .payment, source: .bank,
                     date: nov(12, 11), isShop: true, bankRef: "v3", bankStatus: .booked),
            Movement(bank: .rev, amountCents: -2_200, merchant: "Comprarte", kind: .payment, source: .bank,
                     date: nov(13, 11), isShop: true, bankRef: "v4", bankStatus: .booked),
        ]
        let known = Self.merchantKeys(in: state)
        let questions = [
            "¿Qué compre ayer?",
            "¿Que compre ayer?",
            "¿Cuánto he pagado a la asesoría?",
            "¿Cuánto me cobra el asesor?",
            "¿Cuánto pagué en la Asesoría Pérez?",
            "¿Cuál es mi gasto promedio al mes?",
            "¿Cuánto gasto de promedio?",
            "¿Con cuánto voy a quedarme a fin de mes?",
            "¿Cuánto debería quedarme en Revolut a fin de mes?",
            "¿Cuánto tengo que pagar de la renta?",
            "¿Cuándo tengo que pagar la renta?",
            "¿Debo algo de la renta?",
            "¿Tengo que pagar el bono del gimnasio?",
            "¿Tengo que recargar el bono transporte?",
            "¿Cuánto tengo que pagar por el depósito?",
            "Compras",
            "Compra",
            "Ventas",
            "Compras este mes",
            "¿Cuánto gasté comprando ropa?",
            "¿Cuánto gasté en comprar regalos?",
            "¿Qué compraron con mi tarjeta?",
            "¿Cuánto me queda tras comprar el coche?",
            "¿Cuánto me he gastado en vending?",
            "¿Cuánto me he gastado en el vendedor de lotería?",
            "¿Cuánto me he gastado en Vendome?",
            "¿Cuánto me he gastado en Comprarte?",
            "¿Cuánto dinero meto en la hucha?",
            "¿Cuánto dinero pongo en el súper cada mes?",
            "¿Cuál fue el momento de más gasto?",
            "¿Cuánto mantengo en Revolut?",
            "¿Cuánto me cuesta mantener el coche?",
            "¿Cuánto me paso en el mercado?",
            "¿Cuánto paso cada mes a la fundación?",
        ]
        let comprasExact: Set<String> = ["Compras", "Compra", "Compras este mes"]
        let unsupportedExact: Set<String> = ["¿Qué compre ayer?", "¿Que compre ayer?"]
        let spendingExact: Set<String> = [
            "¿Cuánto he pagado a la asesoría?",
            "¿Cuánto me cobra el asesor?",
            "¿Cuánto pagué en la Asesoría Pérez?",
            "¿Cuánto gasté comprando ropa?",
            "¿Cuánto gasté en comprar regalos?",
            "¿Cuánto me he gastado en vending?",
            "¿Cuánto me he gastado en el vendedor de lotería?",
            "¿Cuánto me he gastado en Vendome?",
            "¿Cuánto me he gastado en Comprarte?",
        ]
        for portfolio in [samplePortfolio() as Portfolio?, nil] {
            let tag = portfolio == nil ? "sin cartera" : "con cartera"
            for q in questions {
                #expect(!isAdviceRequest(q, portfolio: portfolio, knownMerchants: known), "[\(tag)] falso positivo: \(q)")
                let intent = routeAssistantQuestion(q, state: state, portfolio: portfolio, now: nov(20), calendar: cal)
                if case .adviceRequest = intent {
                    Issue.record("[\(tag)] routeAssistantQuestion dio .adviceRequest para «\(q)»")
                }
                if comprasExact.contains(q) {
                    #expect(intent == .spending(month: .current, category: .compras, merchant: nil, bank: nil), "[\(tag)] \(q) -> \(intent)")
                } else if unsupportedExact.contains(q) {
                    #expect(intent == .unsupportedPeriod, "[\(tag)] \(q) -> \(intent)")
                } else if spendingExact.contains(q) {
                    if case .spending = intent {
                    } else {
                        Issue.record("[\(tag)] esperaba .spending para «\(q)», salió \(intent)")
                    }
                }
            }
        }
    }

    // MARK: U3 — Periodos («del año pasado», importes de 4 cifras y hoy/ayer/semana/año)

    @Test func mesDelAnoPasado() {
        let state = sampleState()
        #expect(routeAssistantQuestion("¿Cuánto gasté en octubre del año pasado?", state: state, portfolio: nil, now: nov(20), calendar: cal)
            == .spending(month: .specific(year: 2025, month: 10), category: nil, merchant: nil, bank: nil))
        #expect(routeAssistantQuestion("¿Cuánto gasté en noviembre del año pasado?", state: state, portfolio: nil, now: nov(20), calendar: cal)
            == .spending(month: .specific(year: 2025, month: 11), category: nil, merchant: nil, bank: nil))
    }

    @Test func importeNoEsAno() {
        let state = sampleState()
        #expect(routeAssistantQuestion("¿Gasté más de 1000 € en octubre?", state: state, portfolio: nil, now: nov(20), calendar: cal)
            == .spending(month: .specific(year: 2026, month: 10), category: nil, merchant: nil, bank: nil))
    }

    @Test func hoyAyerSemanaAnoNoSonElMes() throws {
        let state = sampleState()
        for q in [
            "¿Cuánto he gastado hoy?",
            "¿Qué compré ayer?",
            "¿Cuánto gasté esta semana?",
            "¿Cuánto he gastado este año?",
        ] {
            #expect(routeAssistantQuestion(q, state: state, portfolio: nil, now: nov(20), calendar: cal) == .unsupportedPeriod, "\(q)")
            let ans = answerQuestion(q, state: state, portfolio: nil, book: AccountBook(), now: nov(20), calendar: cal)
            let line = try #require(ans.lines.first)
            #expect(render(line.parts, .plain) == "Aún no sé contarte el gasto por días, semanas o años; sí por meses.", "\(q)")
            #expect(ans.chips.map(\.label) == ["¿Cuánto llevo este mes?", "¿Cuánto gasté el mes pasado?"], "\(q)")
        }
        // Control: el resumen diario sigue siendo `.briefingRecap`.
        #expect(routeAssistantQuestion("¿Qué ha pasado desde ayer?", state: state, portfolio: nil, now: nov(20), calendar: cal) == .briefingRecap)
        // El modelo no puede emitir `.unsupportedPeriod`.
        #expect(parseAssistantModelRoute("PERIODO_NO_SOPORTADO", originalQuestion: "¿Cuánto gasté hoy?", portfolio: nil) == nil)
    }

    // MARK: Re-revisión U1–U7 (N1–N4)

    @Test func u1ReRevisionPositivosYNegativosSinRegresiones() {
        let state = sampleState()
        let known = ledgerMerchantKeys(in: state)
        let shouldRefuse = [
            // 2a.1–3: activo al principio de la frase y elección «X o Y»
            "¿Nvidia está barata?",
            "¿Tesla es rentable?",
            "Nvidia worth it?",
            "¿Nvidia subirá?",
            "¿Tesla va a subir?",
            "¿Tesla o Nvidia?",
            "¿Apple o Microsoft?",
            // 2a.4: condicionales merecería/valdría
            "¿Merecería la pena Nvidia?",
            "¿Valdría la pena Tesla?",
            // 2a.5: dígitos y «mil euros»
            "¿En qué meto 1.000 €?",
            "¿Dónde pongo 1000 €?",
            "¿Qué hago con mil euros?",
            // 2a.6: mantengo/promedio/me quedo con/sigo
            "¿Mantengo Nvidia?",
            "¿Promedio Nvidia?",
            "¿Hago bien en mantener Tesla?",
            "¿Me quedo con Tesla?",
            "¿Sigo en Tesla?",
            "¿Sigo con Nvidia?",
            // 2a.7: oro con decisión o predicción
            "¿Meto mis ahorros en oro?",
            "¿Paso mis ahorros a oro?",
            "¿Me pongo en oro?",
            "¿Meto todo en oro?",
            "¿Cuánto meto en oro?",
            "¿Subirá el oro?",
            "¿Va a subir el oro?",
            // 2a.8: opinión sobre un activo sin cartera
            "¿Qué opinas de Nvidia?",
            "¿Qué piensas de Tesla?",
            "¿Qué te parece Nvidia?",
            // 2a.9: vocabulario financiero cotidiano
            "¿Contrato un plan de pensiones?",
            "¿Cuánto debería meter en el plan de pensiones?",
            "¿Shorteo Tesla?",
            "¿Hago trading con Tesla?",
            "¿Qué hago con la herencia?",
            "¿Qué hago con la paga extra?",
            "¿Compensa el oro?",
            "¿Me suscribo a letras del Tesoro?",
            "¿Renuevo el depósito?",
        ]
        for portfolio in [samplePortfolio() as Portfolio?, nil] {
            let tag = portfolio == nil ? "sin cartera" : "con cartera"
            for q in shouldRefuse {
                #expect(isAdviceRequest(q, portfolio: portfolio, knownMerchants: known), "[\(tag)] debía rechazar: \(q)")
            }
        }

        let mustAllow = [
            // 2b: preguntas corrientes de cartera e inversiones
            "¿Qué acciones tengo?",
            "¿Qué posiciones tengo?",
            "¿Cuántas posiciones tengo?",
            "¿Qué ETFs tengo?",
            "¿Qué fondos tengo?",
            "¿Cuántas acciones de Apple tengo?",
            "¿Tengo acciones de Apple?",
            "¿Cuál es mi cartera?",
            "Mi cartera",
            "Cartera",
            "Inversiones",
            "Mis inversiones",
            "Resumen de mi cartera",
            "Valor de mi cartera",
            "¿Qué tal van mis acciones?",
            "¿Cuál es mi posición en Apple?",
            "¿Cuál es la rentabilidad de mi cartera?",
            "Dividendos",
            "¿Qué dividendos me tocan?",
            "¿Cuándo cobro el dividendo de Apple?",
            "¿Cuántos dividendos he cobrado este año?",
            "¿Cuánto he cobrado en dividendos?",
            "¿Cuándo es la próxima aportación?",
            "¿A qué precio compré Apple?",
            "¿A cuánto cotiza Apple?",
            "¿Cuál es la cotización de Apple?",
            "¿Cuánto ha caído Apple?",
            "¿Qué tal va Apple?",
            "¿Cuánto me ha dado Apple?",
            // 2b: verbos de gasto (cobró, pagó, cuesta, pago de cuota)
            "¿Cuánto me cobró el broker?",
            "¿Cuánto me cobró Trade Republic por el ETF?",
            "¿Cuánto me cuesta el ETF de comisión?",
            "¿Cuánto me pagó Apple de dividendo?",
            "¿Cuánto me cobró la academia Bitcoin Escuela?",
            "¿Cuánto pago de cuota en Fondo Social?",
            // 2b: «entró» en pasado + sustantivo «aumento» / adjetivo «líquido»
            "¿Cuánto me entró de Wallapop?",
            "¿Cuánto me entró de Hacienda?",
            "¿Cuándo entró la nómina de Acme?",
            "¿Cuánto fue el aumento de la factura de Iberdrola?",
            "¿Cuánto dinero líquido tengo en ING?",
            // 2b: imperfecto de comprar/vender
            "¿Cuánto compraba en Mercadona antes?",
            "¿Cuánto vendía en Wallapop?",
            // 2b: «compre» sin tilde y «Compras» corto
            "¿Qué compre el finde?",
            "¿Qué compre esta mañana?",
            "¿Dónde compre las zapatillas?",
            "Compras ayer",
            "Compras hoy",
            "Compras esta semana",
        ]
        for portfolio in [samplePortfolio() as Portfolio?, nil] {
            let tag = portfolio == nil ? "sin cartera" : "con cartera"
            for q in mustAllow {
                #expect(!isAdviceRequest(q, portfolio: portfolio, knownMerchants: known), "[\(tag)] falso positivo: \(q)")
            }
        }
    }

    @Test func u3ComparacionConAnoPasadoYDiaNoPisaComercioMasLargo() {
        var state = sampleState()
        state.movements.append(
            Movement(bank: .rev, amountCents: -1_800, merchant: "DIA Market", kind: .payment, source: .bank,
                     date: nov(12, 10), isShop: true, bankRef: "dia-n4", bankStatus: .booked)
        )
        // N3: «¿Gasté más en octubre que el año pasado?» habla de octubre de 2026, no de 2025.
        #expect(routeAssistantQuestion("¿Gasté más en octubre que el año pasado?", state: state, portfolio: nil, now: nov(20), calendar: cal)
            == .spending(month: .specific(year: 2026, month: 10), category: nil, merchant: nil, bank: nil))
        // N4: con DIA en el libro, «Mercadona» gana a «Dia» por longitud.
        #expect(routeAssistantQuestion("¿Cuánto gasté en Mercadona el Dia 5?", state: state, portfolio: nil, now: nov(20), calendar: cal)
            == .spending(month: .current, category: nil, merchant: "Mercadona", bank: nil))
    }
}
