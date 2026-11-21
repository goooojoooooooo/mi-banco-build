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
        let prompt = assistantRoutingPrompt(question: "¿Cuánto llevo en Mercadona?", now: nov(20), calendar: cal)
        #expect(prompt.contains("Mes actual: 2026-11"))
        #expect(prompt.contains("Pregunta: ¿Cuánto llevo en Mercadona?"))
        #expect(!prompt.contains("€"))
        #expect(!prompt.contains("340,20"))
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
}
