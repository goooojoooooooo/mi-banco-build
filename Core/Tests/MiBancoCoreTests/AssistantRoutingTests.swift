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
    // MARK: Detector de peticiones de consejo (A3, J7, J15, J21(c), J22)

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
        // Preguntas bancarias cotidianas que no deben disparar falsos positivos
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

    // MARK: Enrutador determinista (todas las intenciones de A3)

    @Test func enrutaSaldos() {
        let state = sampleState()
        #expect(routeAssistantQuestion("¿Cuánto tengo?", state: state, portfolio: nil, now: nov(20), calendar: cal) == .balances(bank: nil))
        #expect(routeAssistantQuestion("¿Cuál es mi saldo en Revolut?", state: state, portfolio: nil, now: nov(20), calendar: cal) == .balances(bank: .rev))
        #expect(routeAssistantQuestion("¿Cuánto me queda en imagin?", state: state, portfolio: nil, now: nov(20), calendar: cal) == .balances(bank: .ima))
        #expect(routeAssistantQuestion("saldo en Trade Republic", state: state, portfolio: nil, now: nov(20), calendar: cal) == .balances(bank: .tr))
    }

    @Test func enrutaGastosPorMesCategoriaYComercio() {
        let state = sampleState()
        #expect(routeAssistantQuestion("¿Cuánto llevo gastado este mes?", state: state, portfolio: nil, now: nov(20), calendar: cal)
            == .spending(month: .current, category: nil, merchant: nil))
        #expect(routeAssistantQuestion("¿Cuánto gasté el mes pasado?", state: state, portfolio: nil, now: nov(20), calendar: cal)
            == .spending(month: .previous, category: nil, merchant: nil))
        #expect(routeAssistantQuestion("¿Cuánto gasté en octubre?", state: state, portfolio: nil, now: nov(20), calendar: cal)
            == .spending(month: .specific(year: 2026, month: 10), category: nil, merchant: nil))
        #expect(routeAssistantQuestion("¿Cuánto gasté en diciembre?", state: state, portfolio: nil, now: at(2026, 2, 10), calendar: cal)
            == .spending(month: .specific(year: 2025, month: 12), category: nil, merchant: nil))
        #expect(routeAssistantQuestion("¿Cuánto llevo en Comer fuera?", state: state, portfolio: nil, now: nov(20), calendar: cal)
            == .spending(month: .current, category: .comerFuera, merchant: nil))
        #expect(routeAssistantQuestion("¿Cuánto gasté en compras este mes?", state: state, portfolio: nil, now: nov(20), calendar: cal)
            == .spending(month: .current, category: .compras, merchant: nil))
        #expect(routeAssistantQuestion("¿Cuánto llevo en Mercadona?", state: state, portfolio: nil, now: nov(20), calendar: cal)
            == .spending(month: .current, category: nil, merchant: "Mercadona"))
        // Comercio aún sin pagos en el libro, y combinado con mes:
        #expect(routeAssistantQuestion("¿Cuánto gasté en Zara en octubre?", state: state, portfolio: nil, now: nov(20), calendar: cal)
            == .spending(month: .specific(year: 2026, month: 10), category: nil, merchant: "Zara"))
        #expect(routeAssistantQuestion("¿Cuánto gasté en octubre en Zara?", state: state, portfolio: nil, now: nov(20), calendar: cal)
            == .spending(month: .specific(year: 2026, month: 10), category: nil, merchant: "Zara"))
    }

    @Test func distingueComercioYPosicionConElMismoNombre() {
        let state = sampleState()
        let portfolio = samplePortfolio()
        // Con verbo de gasto -> gasto en el comercio Apple.
        #expect(routeAssistantQuestion("¿Cuánto gasté en Apple este mes?", state: state, portfolio: portfolio, now: nov(20), calendar: cal)
            == .spending(month: .current, category: nil, merchant: "Apple"))
        // Sin verbo de gasto -> posición Apple de la cartera.
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

    // MARK: Contrato con el modelo (A2, A6, J21(d))

    @Test func elPromptDelModeloNoLlevaDatosBancarios() {
        let prompt = assistantRoutingPrompt(question: "¿Cuánto llevo en Mercadona?", now: nov(20), calendar: cal)
        #expect(prompt.contains("Mes actual: 2026-11"))
        #expect(prompt.contains("Pregunta: ¿Cuánto llevo en Mercadona?"))
        #expect(!prompt.contains("€"))
        #expect(!prompt.contains("340,20"))
        #expect(assistantRoutingInstructions.contains("Onyx"))
        #expect(assistantRoutingInstructions.contains("CONSEJO"))
    }

    @Test func elParserDelModeloValidaEstrictamenteYNuncaSeSaltaElConsejo() {
        let portfolio = samplePortfolio()
        // Casos válidos
        #expect(parseAssistantModelRoute("SALDO banco=rev", originalQuestion: "¿Cuánto tengo en Revolut?",
                                         portfolio: portfolio, now: nov(20), calendar: cal) == .balances(bank: .rev))
        #expect(parseAssistantModelRoute("GASTO mes=2026-10 comercio=\"Mercadona\"", originalQuestion: "¿Cuánto en Mercadona en octubre?",
                                         portfolio: portfolio, now: nov(20), calendar: cal)
            == .spending(month: .specific(year: 2026, month: 10), category: nil, merchant: "Mercadona"))
        #expect(parseAssistantModelRoute("PRESUPUESTOS categoria=comerFuera", originalQuestion: "Presupuesto de bares",
                                         portfolio: portfolio, now: nov(20), calendar: cal) == .budgets(category: .comerFuera))
        #expect(parseAssistantModelRoute("INVERSIONES movers=si", originalQuestion: "¿Qué subió más?",
                                         portfolio: portfolio, now: nov(20), calendar: cal)
            == .investments(positionQuery: nil, moversOnly: true))

        // Inyección: el modelo intenta inventar un comercio que NO estaba en la pregunta -> rechazado (nil).
        #expect(parseAssistantModelRoute("GASTO comercio=\"Compra Apple ya\"", originalQuestion: "¿Cuánto llevo este mes?",
                                         portfolio: portfolio, now: nov(20), calendar: cal) == nil)
        // Basura, texto libre o parámetros inválidos -> nil (cae al enrutador determinista).
        for bad in ["", "Claro, te cuento tus saldos", "OTRO", "SALDO banco=bbva", "GASTO mes=2026-13",
                    "GASTO categoria=inventada", "SALDO foo=bar", "GASTO comercio=\"sin cerrar"] {
            #expect(parseAssistantModelRoute(bad, originalQuestion: "¿Cuánto tengo?",
                                             portfolio: portfolio, now: nov(20), calendar: cal) == nil, "\(bad)")
        }

        // Seguridad: aunque el modelo clasifique mal una petición de consejo como INVERSIONES o SALDO, manda `isAdviceRequest`.
        let forced = parseAssistantModelRoute("INVERSIONES posicion=Apple", originalQuestion: "¿Debería comprar más Apple?",
                                              portfolio: portfolio, now: nov(20), calendar: cal)
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
}
