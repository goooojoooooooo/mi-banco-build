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

/// Construye un escenario donde los SEIS temas de «Te puede interesar» están activos a la vez.
private func allSixSignalsFixture() -> (state: LedgerState, portfolio: Portfolio, book: AccountBook, now: Date) {
    let now = nov(20, 10, 0)
    var state = LedgerState()
    // 1. Shortfall: Revolut tiene 55 € con colchón 50 € y el 22 nov entra Spotify (10,99 €).
    state.balances[.rev] = ManualBalance(cents: 5_500, setAt: nov(20, 8), origin: .bank)
    state.balances[.ima] = ManualBalance(cents: 120_000, setAt: nov(20, 8), origin: .bank)
    // 2. Budget close: presupuesto de Comer fuera = 100 €, gastado 88 € (88 % -> warning).
    state.budgets = Budgets(monthlyCents: nil, byCategory: [.comerFuera: 10_000])

    state.movements = [
        // 3. Subscription price change: Netflix subió de 13,99 € (20 oct) a 15,99 € (19 nov) — y Spotify para shortfall el 22 nov.
        Movement(bank: .rev, amountCents: -1_399, merchant: "Netflix", kind: .payment, source: .bank,
                 date: at(2026, 10, 20, 12), isShop: true, bankRef: "nf1", bankStatus: .booked),
        Movement(bank: .rev, amountCents: -1_599, merchant: "Netflix", kind: .payment, source: .bank,
                 date: nov(19, 12), isShop: true, bankRef: "nf2", bankStatus: .booked),
        Movement(bank: .rev, amountCents: -1_099, merchant: "Spotify", kind: .payment, source: .bank,
                 date: at(2026, 9, 22, 12), isShop: true, bankRef: "sp1", bankStatus: .booked),
        Movement(bank: .rev, amountCents: -1_099, merchant: "Spotify", kind: .payment, source: .bank,
                 date: at(2026, 10, 22, 12), isShop: true, bankRef: "sp2", bankStatus: .booked),
        // 4. Unusual payment: Café Sol suele ser 3,00 € (3 pagos previos), hoy 15,00 € (5x).
        Movement(bank: .rev, amountCents: -300, merchant: "Café Sol", kind: .payment, source: .bank,
                 date: at(2026, 10, 1, 9), isShop: true, bankRef: "c1", bankStatus: .booked),
        Movement(bank: .rev, amountCents: -300, merchant: "Café Sol", kind: .payment, source: .bank,
                 date: at(2026, 10, 5, 9), isShop: true, bankRef: "c2", bankStatus: .booked),
        Movement(bank: .rev, amountCents: -300, merchant: "Café Sol", kind: .payment, source: .bank,
                 date: at(2026, 10, 10, 9), isShop: true, bankRef: "c3", bankStatus: .booked),
        Movement(bank: .rev, amountCents: -1_500, merchant: "Café Sol", kind: .payment, source: .bank,
                 date: nov(18, 9), isShop: true, bankRef: "c4", bankStatus: .booked),
        // 5. Spending pace + budget: comer fuera en nov 73 € + 15 € Café Sol = 88 € (octubre solo tuvo 22,99 € hasta día 20).
        Movement(bank: .rev, amountCents: -7_300, merchant: "Restaurante Luna", kind: .payment, source: .bank,
                 date: nov(10, 21), isShop: true, bankRef: "r1", bankStatus: .booked),
    ]

    // 6. Portfolio mover: MSCI +2,5 %, Apple −1,5 %.
    var portfolio = Portfolio()
    portfolio.transactions = [
        InvestmentTransaction(id: "i1", date: at(2026, 3, 2, 9), instrument: "IE00B4L5Y983",
                              name: "MSCI World", assetClass: "FUND", shares: 10, cashCents: -100_000, priceEUR: 100),
        InvestmentTransaction(id: "i2", date: at(2026, 6, 15, 13), instrument: "US0378331005",
                              name: "Apple", assetClass: "STOCK", shares: 5, cashCents: -90_000, priceEUR: 180),
    ]
    portfolio.quotes["IE00B4L5Y983"] = Quote(priceEUR: Decimal(string: "102.5")!, previousCloseEUR: 100,
                                             fetchedAt: nov(20, 9, 30), marketTime: nov(20, 9, 25))
    portfolio.quotes["US0378331005"] = Quote(priceEUR: Decimal(string: "197.0")!, previousCloseEUR: 200,
                                             fetchedAt: nov(20, 9, 30), marketTime: nov(20, 9, 25))

    var book = AccountBook()
    book.floors[.rev] = 5_000
    return (state, portfolio, book, now)
}

@Suite struct InterestCardsTests {
    @Test func maximoTresTarjetasYPrioridadPorDefecto() {
        let fx = allSixSignalsFixture()
        let cards = interestCards(state: fx.state, portfolio: fx.portfolio, book: fx.book, now: fx.now, calendar: cal)
        #expect(cards.count == maxInterestCards)
        #expect(cards.map(\.topic) == [.shortfall, .budgetClose, .subscriptionPriceChange])
    }

    @Test func cadaUnoDeLosSeisTemasGeneraSuTarjetaConTextoYAccionCorrectos() {
        let fx = allSixSignalsFixture()
        for topic in AssistantTopic.allCases {
            var prefs = AssistantPreferences()
            for other in AssistantTopic.allCases where other != topic { prefs.setEnabled(false, for: other) }
            let cards = interestCards(state: fx.state, portfolio: fx.portfolio, book: fx.book,
                                      now: fx.now, calendar: cal, preferences: prefs)
            #expect(cards.count == 1, "Faltó tarjeta para \(topic)")
            let card = cards[0]
            #expect(card.topic == topic)
            let text = render(card.parts, .plain)
            switch topic {
            case .shortfall:
                #expect(text.contains("Spotify") && text.contains("desde imagin"))
                if case .moveMoney(from: .ima, to: .rev, cents: _) = card.action { } else { Issue.record("Esperaba moveMoney") }
            case .budgetClose:
                #expect(text == nb("Llevas 88,00 € de 100,00 € en Comer fuera: te quedan 12,00 €."))
                #expect(card.action == .openBudgets)
            case .subscriptionPriceChange:
                #expect(text == nb("Netflix ha subido 2,00 €: ahora son 15,99 € al mes."))
            case .unusualPayment:
                #expect(text == nb("Café Sol: 15,00 €. Sueles gastar unos 3,00 €."))
                if case .openMovement = card.action { } else { Issue.record("Esperaba openMovement") }
            case .spendingPace:
                #expect(text.contains("por encima de octubre"))
                #expect(card.action == .openBudgets)
            case .portfolioMover:
                #expect(text == nb("Lo que más subió: MSCI World (+2,5 %). Lo que más bajó: Apple (\u{2212}1,5 %)."))
                #expect(card.action == .openInvestments)
            }
        }
    }

    @Test func meInteresaYNoMeInteresaAjustanPesosYDescartarShortfallNoLoResucita() {
        let fx = allSixSignalsFixture()
        var prefs = AssistantPreferences()

        // Subimos el peso de portfolioMover (+3) y bajamos el de subscriptionPriceChange (-2).
        prefs.recordFeedback(.interested, cardID: "old-p1", topic: .portfolioMover, now: nov(18))
        prefs.recordFeedback(.interested, cardID: "old-p2", topic: .portfolioMover, now: nov(19))
        prefs.recordFeedback(.interested, cardID: "old-p3", topic: .portfolioMover, now: nov(20))
        prefs.recordFeedback(.notInterested, cardID: "old-s1", topic: .subscriptionPriceChange, now: nov(18))
        prefs.recordFeedback(.notInterested, cardID: "old-s2", topic: .subscriptionPriceChange, now: nov(19))

        #expect(prefs.weight(for: .portfolioMover) == 3)
        #expect(prefs.weight(for: .subscriptionPriceChange) == -2)

        let ranked = interestCards(state: fx.state, portfolio: fx.portfolio, book: fx.book,
                                   now: fx.now, calendar: cal, preferences: prefs)
        #expect(ranked.count == 3)
        #expect(ranked.map(\.topic).contains(.portfolioMover))
        #expect(!ranked.map(\.topic).contains(.subscriptionPriceChange))

        // I4 REGRESIÓN: descartar la tarjeta urgente de shortfall NO resucita un «shortfall-cal» del mismo banco.
        let urgentShortfall = ranked.first { $0.topic == .shortfall }!
        prefs.recordFeedback(.notInterested, for: urgentShortfall, now: fx.now)
        let afterDismiss = interestCards(state: fx.state, portfolio: fx.portfolio, book: fx.book,
                                         now: fx.now, calendar: cal, preferences: prefs)
        #expect(!afterDismiss.contains { $0.topic == .shortfall })
    }

    @Test func bancoBajoMinimoSinCobrosNoSacaTarjetaFalsa() {
        // I5 REGRESIÓN: Revolut tiene 40 € y colchón 50 €, pero CERO cobros próximos -> no debe salir «Saldo justo para un cobro».
        var state = LedgerState()
        state.balances[.rev] = ManualBalance(cents: 4_000, setAt: nov(20, 8), origin: .bank)
        var book = AccountBook()
        book.floors[.rev] = 5_000
        let cards = interestCards(state: state, portfolio: nil, book: book, now: nov(20, 10), calendar: cal)
        #expect(cards.isEmpty)
    }

    @Test func repetirToqueEsIdempotenteYCambioDeOpinionEnElTopeEsExacto() {
        var prefs = AssistantPreferences()
        let now = nov(20)
        // Tocar dos veces «Me interesa» en la misma tarjeta solo suma una vez.
        prefs.recordFeedback(.interested, cardID: "c1", topic: .unusualPayment, now: now)
        prefs.recordFeedback(.interested, cardID: "c1", topic: .unusualPayment, now: now)
        #expect(prefs.weight(for: .unusualPayment) == 1)

        // Cambiar de opinión en la misma tarjeta invierte el cambio (+1 -> -1).
        prefs.recordFeedback(.notInterested, cardID: "c1", topic: .unusualPayment, now: now)
        #expect(prefs.weight(for: .unusualPayment) == -1)

        // El peso nunca sale de minWeight...maxWeight.
        for i in 0..<20 {
            prefs.recordFeedback(.interested, cardID: "up-\(i)", topic: .portfolioMover, now: now)
            prefs.recordFeedback(.notInterested, cardID: "down-\(i)", topic: .spendingPace, now: now)
        }
        #expect(prefs.weight(for: .portfolioMover) == AssistantPreferences.maxWeight)
        #expect(prefs.weight(for: .spendingPace) == AssistantPreferences.minWeight)

        // Minor 9: si estando en el tope (+5) se pulsa «Me interesa» (delta real 0) y luego cambia a «No me interesa», baja a 4 (no a 3).
        prefs.recordFeedback(.interested, cardID: "at-cap", topic: .portfolioMover, now: now)
        #expect(prefs.weight(for: .portfolioMover) == 5)
        prefs.recordFeedback(.notInterested, cardID: "at-cap", topic: .portfolioMover, now: now)
        #expect(prefs.weight(for: .portfolioMover) == 4)

        // Minor 9: `init(topicWeights:)` descarta ceros para mantener igualdad tras codificar/decodificar.
        let withZero = AssistantPreferences(topicWeights: [.shortfall: 0, .budgetClose: 2])
        #expect(withZero == AssistantPreferences(topicWeights: [.budgetClose: 2]))

        // Las respuestas de más de 30 días se limpian automáticamente.
        prefs.recordFeedback(.notInterested, cardID: "very-old", topic: .budgetClose, now: at(2026, 9, 1))
        prefs.recordFeedback(.interested, cardID: "fresh", topic: .budgetClose, now: nov(20))
        #expect(prefs.feedback(for: "very-old") == nil)
        #expect(prefs.feedback(for: "fresh") == .interested)
    }

    @Test func interruptoresDeAjustesApaganPorCompletoUnTema() {
        let fx = allSixSignalsFixture()
        var prefs = AssistantPreferences()
        for topic in AssistantTopic.allCases { prefs.setEnabled(false, for: topic) }
        #expect(interestCards(state: fx.state, portfolio: fx.portfolio, book: fx.book,
                              now: fx.now, calendar: cal, preferences: prefs).isEmpty)
    }

    @Test func decodificacionToleranteDePreferenciasYTiposRotos() throws {
        // JSON con temas desconocidos, pesos fuera de rango, floats y entradas corruptas.
        let json = """
        {
          "disabledTopics": ["shortfall", "temaInventado", 123],
          "topicWeights": {"portfolioMover": 99, "spendingPace": -99, "temaRaro": 2, "budgetClose": "mal", "unusualPayment": 1.5},
          "cardFeedback": {"ok": {"feedback": "interested", "date": 0}, "roto": "basura"}
        }
        """
        let decoded = try JSONDecoder().decode(AssistantPreferences.self, from: Data(json.utf8))
        #expect(!decoded.isEnabled(.shortfall))
        #expect(decoded.isEnabled(.budgetClose))
        #expect(decoded.weight(for: .portfolioMover) == AssistantPreferences.maxWeight)
        #expect(decoded.weight(for: .spendingPace) == AssistantPreferences.minWeight)
        #expect(decoded.weight(for: .budgetClose) == 0)
        #expect(decoded.feedback(for: "ok") == .interested)
        #expect(decoded.feedback(for: "roto") == nil)

        // Claves raíz con tipo totalmente incorrecto no rompen la decodificación.
        let wrongRoot = #"{"disabledTopics": "mal", "topicWeights": [1,2], "cardFeedback": 42}"#
        let empty = try JSONDecoder().decode(AssistantPreferences.self, from: Data(wrongRoot.utf8))
        #expect(empty == AssistantPreferences())

        // Ida y vuelta limpia.
        let roundTrip = try JSONDecoder().decode(AssistantPreferences.self, from: JSONEncoder().encode(decoded))
        #expect(roundTrip == decoded)
    }

    @Test func privacidadYZeroConsejosEnTodasLasTarjetas() {
        let fx = allSixSignalsFixture()
        for topic in AssistantTopic.allCases {
            var prefs = AssistantPreferences()
            for other in AssistantTopic.allCases where other != topic { prefs.setEnabled(false, for: other) }
            let cards = interestCards(state: fx.state, portfolio: fx.portfolio, book: fx.book,
                                      now: fx.now, calendar: cal, preferences: prefs)
            for card in cards {
                #expect(!card.title.contains { $0.isNumber }, "\(card.title)")
                #expect(!card.title.contains("€") && !card.title.contains("%"), "\(card.title)")
                let masked = render(card.parts, .masked)
                #expect(!masked.contains("€") && !masked.contains("%"), "\(masked)")
                #expect(masked.range(of: "[0-9],[0-9]{2}", options: .regularExpression) == nil, "\(masked)")
                #expect(masked.range(of: "[0-9]\\.[0-9]{3}", options: .regularExpression) == nil, "\(masked)")
                if card.topic == .portfolioMover {
                    let plain = render(card.parts, .plain)
                    #expect(!hasAdviceMarker(plain), "\(plain)")
                    #expect(!hasTradeVerb(plain), "\(plain)")
                }
            }
        }
    }

    @Test func ignoraMovimientosHistoricosSilenciadosPreciosViejosYDiaCinco() {
        let fx = allSixSignalsFixture()
        // Día 4 del mes: no debe salir spendingPace.
        var onlyPace = AssistantPreferences()
        for t in AssistantTopic.allCases where t != .spendingPace { onlyPace.setEnabled(false, for: t) }
        #expect(interestCards(state: fx.state, portfolio: nil, book: fx.book, now: nov(4, 10),
                              calendar: cal, preferences: onlyPace).isEmpty)

        // Comercio silenciado: no debe salir unusualPayment.
        var mutedState = fx.state
        mutedState.mutedMerchants.insert(normalizeMerchant("Café Sol"))
        var onlyUnusual = AssistantPreferences()
        for t in AssistantTopic.allCases where t != .unusualPayment { onlyUnusual.setEnabled(false, for: t) }
        #expect(interestCards(state: mutedState, portfolio: nil, book: fx.book, now: fx.now,
                              calendar: cal, preferences: onlyUnusual).isEmpty)

        // Movimiento histórico (fecha > 48h anterior a importedAt): tampoco salta como pago poco habitual.
        var histState = fx.state
        if let idx = histState.movements.firstIndex(where: { $0.bankRef == "c4" }) {
            histState.movements[idx].importedAt = nov(21, 10)
        }
        #expect(interestCards(state: histState, portfolio: nil, book: fx.book, now: fx.now,
                              calendar: cal, preferences: onlyUnusual).isEmpty)

        // Minor 8: una cotización de hace 10 días (vieja) no genera tarjeta diaria de movimiento en inversiones.
        var stalePortfolio = fx.portfolio
        stalePortfolio.quotes["IE00B4L5Y983"] = Quote(priceEUR: Decimal(string: "102.5")!, previousCloseEUR: 100,
                                                      fetchedAt: nov(10, 9, 30), marketTime: nov(10, 9, 25))
        stalePortfolio.quotes["US0378331005"] = Quote(priceEUR: Decimal(string: "197.0")!, previousCloseEUR: 200,
                                                      fetchedAt: nov(10, 9, 30), marketTime: nov(10, 9, 25))
        var onlyMover = AssistantPreferences()
        for t in AssistantTopic.allCases where t != .portfolioMover { onlyMover.setEnabled(false, for: t) }
        #expect(interestCards(state: LedgerState(), portfolio: stalePortfolio, book: AccountBook(),
                              now: fx.now, calendar: cal, preferences: onlyMover).isEmpty)

        // M1: una cotización del lunes a las 17:00 vista el viernes a las 08:00 (3 días 15 h <= 4 días) NO es vieja y sí sale.
        var fridayMorningPortfolio = fx.portfolio
        fridayMorningPortfolio.quotes["IE00B4L5Y983"] = Quote(priceEUR: Decimal(string: "102.5")!, previousCloseEUR: 100,
                                                              fetchedAt: nov(16, 17, 5), marketTime: nov(16, 17, 0))
        fridayMorningPortfolio.quotes["US0378331005"] = Quote(priceEUR: Decimal(string: "197.0")!, previousCloseEUR: 200,
                                                              fetchedAt: nov(16, 17, 5), marketTime: nov(16, 17, 0))
        #expect(interestCards(state: LedgerState(), portfolio: fridayMorningPortfolio, book: AccountBook(),
                              now: nov(20, 8, 0), calendar: cal, preferences: onlyMover).count == 1)
    }

    @Test func unaSolaPosicionConMovimientoFuerteTambienGeneraTarjeta() {
        var portfolio = Portfolio()
        portfolio.transactions = [
            InvestmentTransaction(id: "only", date: at(2026, 3, 2, 9), instrument: "US0378331005",
                                  name: "Apple", assetClass: "STOCK", shares: 3, cashCents: -50_000, priceEUR: 166),
        ]
        portfolio.quotes["US0378331005"] = Quote(priceEUR: 205, previousCloseEUR: 200,
                                                 fetchedAt: nov(20, 9, 30), marketTime: nov(20, 9, 25))
        let cards = interestCards(state: LedgerState(), portfolio: portfolio, book: AccountBook(),
                                  now: nov(20, 10), calendar: cal)
        #expect(cards.count == 1)
        #expect(cards[0].topic == .portfolioMover)
        #expect(render(cards[0].parts, .plain) == nb("Apple hoy: +2,5 %."))
    }

    @Test func almacenLocalDePreferenciasDelAsistente() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("assistant-prefs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AssistantPreferencesStore(directory: dir)

        // Sin archivo -> preferencias de fábrica (todos los temas activos).
        #expect(try store.load() == AssistantPreferences())

        // Actualizar y releer desde disco.
        try store.update { prefs in
            prefs.setEnabled(false, for: .spendingPace)
            prefs.recordFeedback(.interested, cardID: "card-1", topic: .portfolioMover, now: nov(20, 10))
        }
        let reloaded = try store.load()
        #expect(!reloaded.isEnabled(.spendingPace))
        #expect(reloaded.weight(for: .portfolioMover) == 1)
        #expect(reloaded.feedback(for: "card-1") == .interested)

        // Archivo corrupto (texto roto, vacío o JSON no-objeto): `load()` lanza error, `loadRecovering()` devuelve valores de
        // fábrica y `update` se autorrepara sobrescribiendo atómicamente el archivo dañado.
        let file = dir.appendingPathComponent("assistant-preferences.json")
        for corruptPayload in ["esto no es json", "", "[]"] {
            try Data(corruptPayload.utf8).write(to: file)
            #expect(throws: Error.self) { _ = try store.load() }
            #expect(store.loadRecovering() == AssistantPreferences())
            try store.update { prefs in
                prefs.setEnabled(false, for: .shortfall)
            }
            let healed = try store.load()
            #expect(!healed.isEnabled(.shortfall), "\(corruptPayload)")
        }

        // Error real de E/S (la ruta de carpeta es un archivo regular) sí se propaga en `update` y `save`.
        let blockerFile = FileManager.default.temporaryDirectory.appendingPathComponent("assistant-blocker-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: blockerFile) }
        try Data("x".utf8).write(to: blockerFile)
        let brokenStore = AssistantPreferencesStore(directory: blockerFile)
        #expect(throws: Error.self) {
            try brokenStore.update { $0.setEnabled(false, for: .budgetClose) }
        }
    }
}
