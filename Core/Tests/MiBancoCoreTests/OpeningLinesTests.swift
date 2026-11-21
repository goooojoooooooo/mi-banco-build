import Foundation
import Testing
@testable import MiBancoCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Madrid")!
    c.locale = Locale(identifier: "es_ES")
    return c
}()

private func at(_ month: Int, _ day: Int, _ hour: Int = 10, _ minute: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}

private func digest(_ name: String, _ cents: Int, _ bank: BankID = .rev) -> MovementDigest {
    MovementDigest(id: UUID(), bank: bank, name: name, cents: cents, date: at(11, 20, 7))
}

private func situation(now: Date, since: Date, isFirst: Bool = false, income: [MovementDigest] = [], payments: [MovementDigest] = [],
                       attention: [AttentionItem] = []) -> OpeningSituation {
    let input = BriefingInput(now: now, since: since, isFirst: isFirst, income: income, payments: payments, attention: attention)
    return makeBriefing(input, calendar: cal).situation
}

private func briefing(_ s: OpeningSituation) -> Briefing {
    Briefing(greeting: "Buenos días", headline: [], sections: [], tip: nil, isQuiet: false, situation: s)
}

@Suite struct OpeningLinesTests {
    // MARK: El catálogo

    @Test func hayDiezSituacionesConAlMenosOchoFrases() {
        #expect(OpeningSituation.allCases.count == 10)
        for s in OpeningSituation.allCases {
            let lines = openingCandidates(for: s)
            #expect(lines.count >= 8, "\(s)")
            #expect(Set(lines).count == lines.count, "\(s) tiene frases repetidas")
        }
    }

    @Test func ningunaFraseAconsejaNiLlevaCifrasNiEsLarga() {
        for s in OpeningSituation.allCases {
            for line in openingCandidates(for: s) {
                #expect(!containsAdvice(line), "\(line)")
                #expect(!containsNumber(line), "\(line)")
                #expect(!hasNonLatinLetter(line), "\(line)")
                #expect(!hasInvestmentVocabulary(line), "\(line)")
                #expect(line.count <= 90, "\(line.count): \(line)")
                #expect(!line.contains { $0.isNumber }, "\(line)")
                #expect(!line.contains("€") && !line.contains("%"), "\(line)")
                #expect(line == line.trimmingCharacters(in: .whitespacesAndNewlines), "\(line)")
                #expect(line.hasSuffix(".") || line.hasSuffix("?"), "\(line)")
            }
        }
    }

    // MARK: Situación por reglas (precedencia)

    @Test func laSituacionSaleDeLasReglas() {
        let now = at(11, 25, 9)  // miércoles
        let since = at(11, 24, 9)
        #expect(situation(now: now, since: since) == .quietDay)
        #expect(situation(now: now, since: since, income: [digest("Nómina", 100_000)]) == .incomeArrived)
        let many = (0..<4).map { digest("P\($0)", 500) }
        #expect(situation(now: now, since: since, payments: many) == .busyDay)
        #expect(situation(now: now, since: since, payments: Array(many.prefix(3))) == .quietDay)
        #expect(situation(now: now, since: since, attention: [.warning(title: "Saldo bajo", detail: nil)]) == .needsAttention)
        #expect(situation(now: now, since: since, attention: [.bankProblem(.rev, .offline)]) == .bankUnreadable)
        #expect(situation(now: now, since: at(11, 22, 9)) == .backAfterDays)
        #expect(situation(now: now, since: at(11, 23, 9)) == .quietDay)
        #expect(situation(now: now, since: since, isFirst: true) == .firstEver)
    }

    @Test func laPrecedenciaEsLaDocumentada() {
        let now = at(11, 25, 9)
        let since = at(11, 24, 9)
        let income = [digest("Nómina", 100_000)]
        let many = (0..<4).map { digest("P\($0)", 500) }
        // Primera vez > vuelta > banco sin leer > aviso > ingreso > movido.
        #expect(situation(now: now, since: at(11, 20, 9), isFirst: true, income: income,
                          attention: [.bankProblem(.rev, .offline)]) == .firstEver)
        #expect(situation(now: now, since: at(11, 20, 9), income: income, attention: [.bankProblem(.rev, .offline)]) == .backAfterDays)
        #expect(situation(now: now, since: since, income: income,
                          attention: [.warning(title: "x", detail: nil), .bankProblem(.rev, .offline)]) == .bankUnreadable)
        #expect(situation(now: now, since: since, income: income, payments: many,
                          attention: [.warning(title: "x", detail: nil)]) == .needsAttention)
        #expect(situation(now: now, since: since, income: income, payments: many) == .incomeArrived)
        #expect(situation(now: now, since: since, payments: many) == .busyDay)
    }

    @Test func losDiasDeCalendarioSoloCuentanSiElDiaEsTranquilo() {
        // 2026: el 21 de noviembre es sábado, el 22 domingo, el 30 lunes; el 1 de noviembre es domingo; el 2 de diciembre, miércoles.
        #expect(situation(now: at(11, 21), since: at(11, 20)) == .weekend)
        #expect(situation(now: at(11, 22), since: at(11, 21)) == .weekend)
        #expect(situation(now: at(11, 30), since: at(11, 29)) == .monthEnd)
        #expect(situation(now: at(11, 28), since: at(11, 27)) == .weekend)  // sábado y a tres del final: gana el fin de semana
        #expect(situation(now: at(11, 27), since: at(11, 26)) == .quietDay)
        #expect(situation(now: at(12, 2), since: at(12, 1)) == .monthStart)
        #expect(situation(now: at(12, 4), since: at(12, 3)) == .quietDay)
        #expect(situation(now: at(11, 1), since: at(10, 31)) == .weekend)
        // Con un ingreso, un aviso o un día movido, el calendario no pisa al hecho.
        #expect(situation(now: at(11, 21), since: at(11, 20), income: [digest("Nómina", 100_000)]) == .incomeArrived)
        #expect(situation(now: at(12, 2), since: at(12, 1), attention: [.warning(title: "x", detail: nil)]) == .needsAttention)
        #expect(situation(now: at(11, 30), since: at(11, 29), payments: (0..<5).map { digest("P\($0)", 100) }) == .busyDay)
    }

    // MARK: Rotación

    @Test func laFraseEsEstableEnElDiaYNuncaIgualQueLaDeAyer() {
        for s in OpeningSituation.allCases {
            let b = briefing(s)
            for offset in 0..<60 {
                let day = at(11, 1).addingTimeInterval(Double(offset) * 86_400)
                let today = openingLine(briefing: b, choice: nil, day: day, privateMode: false)
                // Reabrir a otra hora del mismo día: la misma frase.
                #expect(openingLine(briefing: b, choice: nil, day: day.addingTimeInterval(3 * 3600), privateMode: false) == today)
                let tomorrow = openingLine(briefing: b, choice: nil, day: day.addingTimeInterval(86_400), privateMode: false)
                #expect(today != tomorrow, "\(s) día \(offset)")
                #expect(openingCandidates(for: s).contains(today))
            }
        }
    }

    @Test func laRotacionAguantaCambiosDeHoraYDeAnio() {
        // 25 de octubre de 2026: el día de 25 horas; 31 de diciembre -> 1 de enero; 28 de febrero -> 1 de marzo (2027 no es bisiesto).
        let starts = [DateComponents(year: 2026, month: 10, day: 24, hour: 10), DateComponents(year: 2026, month: 12, day: 30, hour: 10),
                      DateComponents(year: 2027, month: 2, day: 27, hour: 10), DateComponents(year: 2027, month: 3, day: 27, hour: 10)]
        for s in OpeningSituation.allCases {
            let b = briefing(s)
            for start in starts {
                var day = cal.date(from: start)!
                for _ in 0..<4 {
                    let next = cal.date(byAdding: .day, value: 1, to: day)!
                    let morning = cal.date(bySettingHour: 0, minute: 30, second: 0, of: day)!
                    let night = cal.date(bySettingHour: 23, minute: 30, second: 0, of: day)!
                    let today = openingLine(briefing: b, choice: nil, day: day, privateMode: false)
                    #expect(openingLine(briefing: b, choice: nil, day: morning, privateMode: false) == today, "\(s) \(day)")
                    #expect(openingLine(briefing: b, choice: nil, day: night, privateMode: false) == today, "\(s) \(day)")
                    #expect(openingLine(briefing: b, choice: nil, day: next, privateMode: false) != today, "\(s) \(day)")
                    day = next
                }
            }
        }
    }

    @Test func laCopiaNoUsaPalabrasProhibidas() {
        func words(_ line: String) -> [String] {
            line.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
                .components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
        }
        let calendarDays: [OpeningSituation] = [.quietDay, .weekend, .monthStart, .monthEnd]
        for s in OpeningSituation.allCases {
            for line in openingCandidates(for: s) {
                let list = words(line)
                for forbidden in ["bienvenido", "encantado", "encantada"] { #expect(!list.contains(forbidden), "\(line)") }
                // «la bienvenida» sí; «bienvenida» para el dueño, no.
                for (i, w) in list.enumerated() where w == "bienvenida" { #expect(i > 0 && list[i - 1] == "la", "\(line)") }
                // «listo» y «lista» como adjetivos de una persona, no; «un repaso rápido y listo» es una muletilla.
                for (i, w) in list.enumerated() where w == "listo" || w == "lista" { #expect(i > 0 && list[i - 1] == "y", "\(line)") }
                #expect(!line.lowercased().contains("buenas noticias"), "\(line)")
                if s == .incomeArrived || s == .busyDay { #expect(!list.contains("hoy"), "\(line)") }
                if calendarDays.contains(s) {
                    for w in list {
                        #expect(w != "calma" && !w.hasPrefix("tranquil") && !w.hasPrefix("sobresalto") && !w.hasPrefix("sorpresa"), "\(line)")
                    }
                }
                // J26: frases por palabras enteras, con el mismo plegado de mayúsculas y acentos.
                let phrase = " " + list.joined(separator: " ") + " "
                // Nada de «a su ritmo»: da por hecho que todo va normal.
                #expect(!phrase.contains(" a su ritmo "), "\(line)")
                // Pueden fallar varios bancos, o todos.
                if s == .bankUnreadable {
                    #expect(!phrase.hasPrefix(" un banco "), "\(line)")
                    for forbidden in ["uno de tus bancos", "el resto", "del resto"] { #expect(!phrase.contains(" \(forbidden) "), "\(line)") }
                }
                // El periodo no es un día.
                if s == .busyDay || s == .incomeArrived { #expect(!list.contains("dia") && !list.contains("dias"), "\(line)") }
                if s == .monthEnd { #expect(!phrase.contains(" ha ido el dia "), "\(line)") }
                // Con un solo ingreso ya basta.
                if s == .incomeArrived { #expect(!list.contains("ingresos"), "\(line)") }
                // Ningún adjetivo de persona: «bienvenid…» solo como «la bienvenida»; «encantad…», nunca.
                for (i, w) in list.enumerated() where w.hasPrefix("bienvenid") {
                    #expect(w == "bienvenida" && i > 0 && list[i - 1] == "la", "\(line)")
                }
                for w in list { #expect(!w.hasPrefix("encantad"), "\(line)") }
            }
        }
    }

    @Test func ningunaFraseChocaConOtraDeSuSituacionSalvoPorPuntuacion() {
        func key(_ line: String) -> String {
            line.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
                .components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }.joined(separator: " ")
        }
        for s in OpeningSituation.allCases {
            let keys = openingCandidates(for: s).map(key)
            #expect(Set(keys).count == keys.count, "\(s)")
        }
    }

    @Test func laMismaFraseDuranteTodoElDia() {
        let b = briefing(.quietDay)
        let morning = openingLine(briefing: b, choice: nil, day: at(11, 25, 6), privateMode: false)
        #expect(openingLine(briefing: b, choice: nil, day: at(11, 25, 23, 59), privateMode: false) == morning)
        #expect(openingLine(briefing: b, choice: nil, day: at(11, 25, 12), privateMode: true) == morning)
        #expect(openingLine(briefing: b, choice: nil, day: at(11, 26, 0, 1), privateMode: false) != morning)
    }

    @Test func recorreTodasLasFrasesConElTiempo() {
        let b = briefing(.busyDay)
        var seen = Set<String>()
        for offset in 0..<30 { seen.insert(openingLine(briefing: b, choice: nil, day: at(11, 1).addingTimeInterval(Double(offset) * 86_400), privateMode: false)) }
        #expect(seen.count == openingCandidates(for: .busyDay).count)
    }

    // MARK: La elección del modelo

    @Test func laEleccionDelModeloSoloValeEnRango() {
        let b = briefing(.incomeArrived)
        let lines = openingCandidates(for: .incomeArrived)
        let day = at(11, 25)
        let rotated = openingLine(briefing: b, choice: nil, day: day, privateMode: false)
        for n in 1...lines.count { #expect(openingLine(briefing: b, choice: n, day: day, privateMode: false) == lines[n - 1]) }
        for bad in [0, -1, lines.count + 1, 99, Int.max, Int.min] {
            #expect(openingLine(briefing: b, choice: bad, day: day, privateMode: false) == rotated, "\(bad)")
        }
    }

    @Test func laRespuestaDelModeloSeLeeComoEntero() {
        #expect(openingChoice(from: "3", count: 9) == 3)
        #expect(openingChoice(from: " 3 \n", count: 9) == 3)
        #expect(openingChoice(from: "3.", count: 9) == 3)
        #expect(openingChoice(from: "9", count: 9) == 9)
        #expect(openingChoice(from: "1", count: 9) == 1)
        for bad in ["0", "10", "-1", "", "  ", "tres", "3 y 4", "1.5", "3,5", "Elijo la 3", "٣", "３", "99999999999999999999", "+3", "03", "01", "00", "003"] {
            #expect(openingChoice(from: bad, count: 9) == nil, "\(bad)")
        }
        #expect(openingChoice(from: "1", count: 0) == nil)
    }

    // MARK: El mensaje al modelo

    @Test func elMensajeListaLasFrasesYNadaMas() {
        var input = BriefingInput(
            now: at(11, 25, 9), since: at(11, 24, 9), isFirst: false,
            banks: [BankLine(bank: .rev, cents: 34_020, estimated: false, changeCents: 13_755)], totalCents: 34_020,
            income: [digest("Nómina ACME", 185_000)], payments: [digest("Zara", 4_995), digest("Mercadona", 1_250)],
            upcoming: [UpcomingCharge(name: "Spotify", bank: .rev, cents: 1_099, date: at(11, 26, 12))])
        input.investments = PortfolioSummary(valueCents: 151_000, todayChangeCents: 600, todayChangeTenths: 4, changeDay: at(11, 25, 0),
                                             costCents: 133_667, gainCents: 17_333, gainTenths: 130, pricedAt: at(11, 25, 8),
                                             oldestPriceAt: at(11, 25, 8), hasStalePrice: false, missingPrices: 0, positions: [])
        let b = makeBriefing(input, calendar: cal)
        #expect(b.situation == .incomeArrived)
        let prompt = briefingModelPrompt(b)
        let lines = openingCandidates(for: .incomeArrived)
        for (i, line) in lines.enumerated() { #expect(prompt.contains("\(i + 1). \(line)")) }
        // Los únicos dígitos son los números de la lista.
        let digits = prompt.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
        #expect(digits == (1...lines.count).map(String.init))
        for forbidden in ["€", "%", "Zara", "Mercadona", "Spotify", "Nómina", "ACME", "Revolut", "Valen", "inversion", "Inversion",
                          "340", "1.850", "precio", "cartera"] {
            #expect(!prompt.contains(forbidden), "\(forbidden)")
        }
        #expect(prompt.contains("Situación: ha entrado dinero."))
        #expect(prompt.hasSuffix("Responde solo con el número de la frase."))
        // Las instrucciones piden un número y nada más.
        #expect(briefingModelInstructions.contains("responde solo con su número"))
        #expect(!briefingModelInstructions.contains("saludo en una o dos frases"))
    }

    @Test func elMensajeDeCadaSituacionSoloLlevaLosNumerosDeLaLista() {
        for s in OpeningSituation.allCases {
            let prompt = briefingModelPrompt(briefing(s))
            let digits = prompt.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
            #expect(digits == (1...openingCandidates(for: s).count).map(String.init), "\(s)")
        }
    }

    // MARK: J22 — barreras: lo que se coló al detector de peticiones

    @Test(arguments: [
        "v e n d e", "v.e.n.d.e", "v-e-n-d-e", "ve*nde", "v_e_n_d_e", "venđe", "vendø", "rebalancea", "rebalancea tu mezcla",
        "mete dinero en oro", "Compra de nuevo", "compra de ayer", "ganancias", "renta fija", "bonos", "ibex", "nasdaq", "un depósito",
        "tesoro público", "purchase now", "gold", "gain", "bond", "oro", "c o m p r a r",
    ]) func detectaLoQueSeColaba(_ text: String) {
        #expect(containsAdvice(text), "\(text)")
    }

    @Test func laCapaLatinaMiraTrasDescomponer() {
        #expect(hasNonLatinLetter("venđe"))
        #expect(hasNonLatinLetter("vendø"))
        #expect(hasNonLatinLetter("łódź"))
        #expect(hasNonLatinLetter("vеnde"))
        #expect(!hasNonLatinLetter("Mañana, señor Ñandú: ¿qué tal? ¡Bien! Cigüeña, café, París, ÁÉÍÓÚ"))
        #expect(!hasNonLatinLetter("cafe\u{0301}"))
    }

    @Test func loBuenoSigueAceptandose() {
        for text in ["has comprado en Mercadona", "tu compra más cara fue Zara", "venta de garaje", "Buenos días, hoy no hay sorpresas",
                     "Vamos a ver", "Ayer y hoy fueron tranquilos"] {
            #expect(!containsAdvice(text), "\(text)")
        }
    }

    // MARK: J23

    @Test func laMonedaPrimeraNecesitaFronteraPorLaIzquierda() {
        func masked(_ text: String) -> String {
            let b = makeBriefing(BriefingInput(now: at(11, 20, 8), since: at(11, 19, 22), isFirst: false,
                                               attention: [.warning(title: text, detail: nil)]), calendar: cal)
            return render(b.sections.first { $0.kind == .attention }!.lines[0].parts, .masked)
        }
        #expect(masked("seguro 5") == "seguro 5")
        #expect(masked("reeuro 5") == "reeuro 5")
        #expect(masked("tareur 20") == "tareur 20")
        #expect(masked("Cobro de euro 5") == "Cobro de •••")
        #expect(masked("Cobro €13") == "Cobro •••")
        #expect(masked("Cobro (EUR 20)") == "Cobro (•••)")
    }

    @Test func unSoloSignoMenosEnTodoElResumen() {
        let input = BriefingInput(
            now: at(11, 20, 8), since: at(11, 19, 22), isFirst: false,
            banks: [BankLine(bank: .rev, cents: 34_020, estimated: false, changeCents: -13_755)], totalCents: 34_020,
            totalChangeCents: -13_755, payments: [digest("Zara", 4_995)],
            month: MonthDigest(spentCents: 41_230, projectedCents: 69_000, paceDifferenceCents: -3_510, previousMonthName: "octubre"))
        let b = makeBriefing(input, calendar: cal)
        var all = [render(b.headline, .plain)]
        for section in b.sections { all += section.lines.map { render($0.parts, .plain) } }
        let text = all.joined(separator: "\n")
        #expect(text.contains("\u{2212}137,55"))
        #expect(text.range(of: "-[0-9]", options: .regularExpression) == nil)
    }

    @Test func losPorcentajesDeInversionesSeTapanEnPrivado() {
        let position = Position(instrument: "A", name: "Alfa", assetClass: nil, shares: 1, costCents: 0, costIncomplete: false)
        let up = PositionValue(position: position, priceEUR: 1, origin: .market(at(11, 20, 7)), valueCents: 10_210,
                               todayChangeCents: 210, gainCents: nil, gainTenths: nil)
        let down = PositionValue(position: Position(instrument: "B", name: "Beta", assetClass: nil, shares: 1, costCents: 0,
                                                    costIncomplete: false), priceEUR: 1, origin: .market(at(11, 20, 7)),
                                 valueCents: 9_870, todayChangeCents: -130, gainCents: nil, gainTenths: nil)
        let summary = PortfolioSummary(valueCents: 20_080, todayChangeCents: 80, todayChangeTenths: 4, changeDay: at(11, 20, 0),
                                       costCents: 0, gainCents: nil, gainTenths: nil, pricedAt: at(11, 20, 7), oldestPriceAt: at(11, 20, 7),
                                       hasStalePrice: false, missingPrices: 0, positions: [up, down])
        let input = BriefingInput(now: at(11, 20, 10), since: at(11, 19, 22), isFirst: false, investments: summary)
        let section = makeBriefing(input, calendar: cal).sections.first { $0.kind == .investments }!
        for line in section.lines.prefix(2) {
            let masked = render(line.parts, .masked)
            #expect(!masked.contains("%"), "\(masked)")
            #expect(masked.range(of: "[0-9]", options: .regularExpression) == nil, "\(masked)")
        }
        #expect(render(section.lines[1].parts, .masked) == "Lo que más subió: Alfa (•••). Lo que más bajó: Beta (•••).")
        #expect(render(section.lines[1].parts, .plain).contains("\u{2212}1,3"))
    }

    @Test func unaFilaQueLlegaOchoDiasTardeDeUnCapturadoSinConfirmarNoSale() {
        var state = LedgerState()
        var link = BankLinkInfo(connectedAt: at(10, 1), consentValidUntil: at(12, 31))
        link.lastSuccessAt = at(11, 10, 7)
        state.links[.rev] = link
        // Una fila antigua con clave marca desde cuándo se ve el banco.
        let old = Movement(bank: .rev, amountCents: -100, merchant: "Antiguo", kind: .payment, source: .bank, date: at(11, 1, 9),
                           bankRef: "old", bankStatus: .booked, importedAt: at(11, 1, 9))
        let capture = Movement(bank: .rev, amountCents: -5_000, merchant: "Bar", kind: .payment, source: .notification,
                               date: at(11, 2, 12), isShop: true)
        // La fila del mismo pago llega ocho días tarde.
        let row = Movement(bank: .rev, amountCents: -5_100, merchant: "Bar", kind: .payment, source: .bank, date: at(11, 2, 21),
                           isShop: true, bankRef: "late", bankStatus: .booked, importedAt: at(11, 10, 8))
        state.movements = [old, capture, row]
        #expect(unconfirmedCaptureIDs(in: state, now: at(11, 10, 9)) == [capture.id])
        let record = BriefingRecord(shownAt: at(11, 10, 9), since: at(11, 9, 20))
        let input = briefingInput(state: state, portfolio: nil, book: AccountBook(), record: record, isFirst: false,
                                  now: at(11, 10, 9), calendar: cal)
        #expect(input.payments.isEmpty)
        #expect(input.banks.allSatisfy { $0.changeCents == 0 })
    }
}
