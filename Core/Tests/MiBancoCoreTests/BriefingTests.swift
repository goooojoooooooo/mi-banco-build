import Foundation
import Testing
@testable import MiBancoCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Madrid")!
    c.locale = Locale(identifier: "es_ES")
    return c
}()

private func nov(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

/// Los textos esperados se escriben con espacios normales; el Core usa espacio duro antes de € y de %.
private func nb(_ s: String) -> String {
    s.replacingOccurrences(of: " €", with: "\u{00A0}€").replacingOccurrences(of: " %", with: "\u{00A0}%")
}

private func digest(_ name: String, _ cents: Int, _ bank: BankID = .rev, at date: Date = nov(20, 7)) -> MovementDigest {
    MovementDigest(id: UUID(), bank: bank, name: name, cents: cents, date: date)
}

private let spotify = UpcomingCharge(name: "Spotify", bank: .rev, cents: 1099, date: nov(22, 12))
private let netflix = UpcomingCharge(name: "Netflix", bank: .rev, cents: 1399, date: nov(25, 12))

private func summary(missing: Int = 0, stale: Bool = false, today: Bool = true, pricedAt: Date? = nov(19, 17, 35),
                     changeDay: Date?? = .none) -> PortfolioSummary {
    // El cambio es del día del precio salvo que se diga otro.
    let day: Date? = today ? (changeDay ?? pricedAt.map { cal.startOfDay(for: $0) }) : nil
    return PortfolioSummary(valueCents: 151_000, todayChangeCents: today ? 600 : nil, todayChangeTenths: today ? 4 : nil, changeDay: day,
                     costCents: 133_667,
                     gainCents: 17_333, gainTenths: 130, pricedAt: pricedAt, oldestPriceAt: stale ? nov(10, 9) : pricedAt,
                     hasStalePrice: stale, missingPrices: missing, positions: [])
}

private func busy() -> BriefingInput {
    BriefingInput(
        now: nov(20, 8, 30), since: nov(19, 22, 10), isFirst: false,
        banks: [BankLine(bank: .rev, cents: 34_020, estimated: false, changeCents: 13_755),
                BankLine(bank: .ima, cents: 128_455, estimated: true, changeCents: 165_000),
                BankLine(bank: .tr, cents: 215_000, estimated: true, changeCents: 0)],
        totalCents: 377_475, totalChangeCents: 178_755,
        income: [digest("Nómina ACME", 185_000, .ima, at: nov(20, 6, 5))],
        payments: [digest("Zara", 4_995), digest("Mercadona", 1_250)],
        transfers: [TransferDigest(from: .ima, to: .rev, cents: 20_000)],
        upcoming: [spotify, netflix],
        attention: [.bankProblem(.ima, .bankUnavailable), .consentExpiring(.rev, nov(30, 10))],
        month: MonthDigest(spentCents: 41_230, projectedCents: 69_000, paceDifferenceCents: -3_510, previousMonthName: "octubre"),
        investments: summary(), budgetTip: BudgetTip(name: "Comer fuera", remainingCents: 2_380),
        freeMoney: FreeMoney(cents: 154_977, daysLeft: 11))
}

private func quiet() -> BriefingInput {
    BriefingInput(
        now: nov(21, 9, 10), since: nov(20, 8, 30), isFirst: false,
        banks: [BankLine(bank: .rev, cents: 34_020, estimated: false, changeCents: 0),
                BankLine(bank: .ima, cents: 128_455, estimated: true, changeCents: 0),
                BankLine(bank: .tr, cents: 215_000, estimated: true, changeCents: 0)],
        totalCents: 377_475, totalChangeCents: 0, upcoming: [spotify, netflix],
        month: MonthDigest(spentCents: 41_230, projectedCents: 69_000, paceDifferenceCents: -3_510, previousMonthName: "octubre"),
        investments: summary(pricedAt: nov(20, 17, 35)), freeMoney: FreeMoney(cents: 154_977, daysLeft: 10))
}


/// Las líneas de un resumen ya escritas con importes (solo para las pruebas; el Core ya no las usa para nada).
private func displayFacts(_ briefing: Briefing) -> [String] {
    var facts = [render(briefing.headline, .plain)]
    for section in briefing.sections {
        for line in section.lines { facts.append(render(line.parts, .plain)) }
    }
    if let tip = briefing.tip { facts.append(render(tip.parts, .plain)) }
    return facts
}
private func lines(_ b: Briefing, _ kind: BriefingSectionKind) -> [String] {
    b.sections.first { $0.kind == kind }?.lines.map { render($0.parts, .plain) } ?? []
}

private func attentionBriefing(_ items: [AttentionItem]) -> Briefing {
    makeBriefing(BriefingInput(now: nov(20, 8, 30), since: nov(19, 22, 10), isFirst: false, attention: items), calendar: cal)
}

@Suite struct BriefingTests {
    @Test func saludos() {
        #expect(greeting(at: nov(20, 4, 59), calendar: cal) == "Buenas noches")
        #expect(greeting(at: nov(20, 5, 0), calendar: cal) == "Buenos días")
        #expect(greeting(at: nov(20, 13, 0), calendar: cal) == "Buenas tardes")
        #expect(greeting(at: nov(20, 21, 0), calendar: cal) == "Buenas noches")
    }

    @Test func periodos() {
        #expect(periodPhrase(since: nov(20, 8, 30), now: nov(20, 13), isFirst: false, calendar: cal) == "Desde las 08:30")
        #expect(periodPhrase(since: nov(19, 22, 10), now: nov(20, 8, 30), isFirst: false, calendar: cal) == "Desde ayer a las 22:10")
        #expect(periodPhrase(since: nov(18, 9), now: nov(20, 8, 30), isFirst: false, calendar: cal) == "Desde el miércoles")
        #expect(periodPhrase(since: nov(13, 8, 30), now: nov(20, 8, 30), isFirst: false, calendar: cal) == "Desde el 13 nov")
        #expect(periodPhrase(since: nov(19, 8), now: nov(20, 8, 30), isFirst: true, calendar: cal) == "En las últimas 24 horas")
    }

    @Test func resumenAjetreado() {
        let b = makeBriefing(busy(), calendar: cal)
        #expect(b.greeting == "Buenos días")
        #expect(!b.isQuiet)
        #expect(render(b.headline, .plain) == nb("Desde ayer a las 22:10 entraron 1.850,00 € y gastaste 62,45 € en 2 pagos."))
        #expect(b.sections.map(\.title) == ["Tu dinero", "Qué ha pasado", "Lo que viene", "Ojo con esto", "El mes", "Inversiones"])
        #expect(lines(b, .money) == [nb("En total, unos 3.774,75 € (+1.787,55 €)"), nb("Revolut: 340,20 € (+137,55 €)"),
                                     nb("imagin: unos 1.284,55 € (+1.650,00 €)"), nb("Trade Republic: unos 2.150,00 € (sin cambios)")])
        #expect(lines(b, .happened) == [nb("Entró Nómina ACME: 1.850,00 € en imagin"), nb("Zara: 49,95 € con Revolut"),
                                        nb("Mercadona: 12,50 € con Revolut"), nb("200,00 € de imagin a Revolut (entre tus cuentas)")])
        #expect(lines(b, .upcoming) == [nb("Domingo 22: Spotify, 10,99 € en Revolut"), nb("Miércoles 25: Netflix, 13,99 € en Revolut")])
        #expect(lines(b, .attention) == ["No he podido actualizar imagin: lo intentaré al volver a abrir.",
                                         "La conexión con Revolut caduca el 30 nov: renuévala en Ajustes."])
        let attention = b.sections.first { $0.kind == .attention }!.lines
        #expect(attention[0].action == nil)
        #expect(attention[1].action == .openBankSettings(.rev))
        #expect(lines(b, .month) == [nb("Llevas 412,30 € gastados; a este ritmo acabarás en unos 690 €."),
                                     nb("35,10 € menos que en octubre a estas alturas.")])
        #expect(lines(b, .investments) == [nb("Valen 1.510,00 €: +6,00 € en la última sesión (jueves) (+0,4 %)"),
                                           nb("Desde la compra: +173,33 € (+13,0 %) · precios de ayer, 17:35")])
        #expect(b.sections.first { $0.kind == .investments }!.lines.allSatisfy { $0.action == .openInvestments })
        #expect(render(b.tip!.parts, .plain) == nb("Te quedan 23,80 € para Comer fuera hasta fin de mes: unos 2 € al día."))
        #expect(b.tip?.action == .openBudgets)
    }

    @Test func laLineaDeUnPagoAbreElMovimiento() {
        let input = busy()
        let b = makeBriefing(input, calendar: cal)
        let zara = b.sections.first { $0.kind == .happened }!.lines[1]
        #expect(zara.action == .openMovement(input.payments[0].id))
    }

    @Test func masPagos() {
        var input = busy()
        input.income = []
        input.transfers = []
        input.payments = [digest("Zara", 4_995), digest("Mercadona", 1_250), digest("Cena", 900), digest("Taxi", 700), digest("Café", 500)]
        let happened = lines(makeBriefing(input, calendar: cal), .happened)
        #expect(happened == [nb("Zara: 49,95 € con Revolut"), nb("Mercadona: 12,50 € con Revolut"), nb("Cena: 9,00 € con Revolut"),
                             nb("Y 2 pagos más: 12,00 €")])
    }

    @Test func consejoPorFalta() {
        var input = busy()
        let charge = UpcomingCharge(name: "Netflix", bank: .rev, cents: 1_399, date: nov(21, 12))
        input.shortfalls = [Shortfall(bank: .rev, charge: charge, balanceCents: 920, missingCents: 479, suggestedFrom: .ima, suggestedCents: 1_000)]
        var tip = makeBriefing(input, calendar: cal).tip
        #expect(render(tip!.parts, .plain) == nb("Mañana te cobran Netflix (13,99 €) en Revolut y tienes 9,20 €. Pasa 10,00 € desde imagin."))
        #expect(tip?.action == .moveMoney(from: .ima, to: .rev, cents: 1_000))
        input.shortfalls = [Shortfall(bank: .rev, charge: charge, balanceCents: 920, missingCents: 479, suggestedFrom: nil, suggestedCents: 1_000)]
        tip = makeBriefing(input, calendar: cal).tip
        #expect(render(tip!.parts, .plain) == nb("Mañana te cobran Netflix (13,99 €) en Revolut y tienes 9,20 €. Pásale 10,00 € antes."))
        #expect(tip?.action == .moveMoney(from: nil, to: .rev, cents: 1_000))
        // Un saldo estimado se dice como aproximado.
        input.shortfalls = [Shortfall(bank: .rev, charge: charge, balanceCents: 920, missingCents: 479, suggestedFrom: .ima, suggestedCents: 1_000,
                                      isEstimated: true, suggestedIsEstimated: true)]
        let text = render(makeBriefing(input, calendar: cal).tip!.parts, .plain)
        #expect(text.contains("y tienes unos 9,20"))
        #expect(text.contains("El saldo de imagin es aproximado."))
    }

    @Test func consejoDineroLibre() {
        var input = busy()
        input.budgetTip = nil
        #expect(render(makeBriefing(input, calendar: cal).tip!.parts, .plain)
            == nb("Hasta fin de mes te quedan unos 1.550 € libres: unos 141 € al día, sin contar el gasto del día a día."))
        // Un banco sin saldo conocido se dice.
        input.freeMoney = FreeMoney(cents: 154_977, daysLeft: 11, missingBanks: [.ima])
        #expect(render(makeBriefing(input, calendar: cal).tip!.parts, .plain).hasSuffix(" al día. Sin contar imagin: no tengo su saldo, y sin contar el gasto del día a día."))
        input.freeMoney = nil
        #expect(makeBriefing(input, calendar: cal).tip == nil)
    }

    @Test func diaTranquilo() {
        let b = makeBriefing(quiet(), calendar: cal)
        #expect(b.isQuiet)
        #expect(render(b.headline, .plain) == "Nada nuevo desde ayer.")
        #expect(b.sections.map(\.title) == ["Tu dinero", "Lo que viene", "Inversiones"])
        #expect(lines(b, .money) == [nb("Sigues con unos 3.774,75 € en total.")])
        #expect(lines(b, .upcoming) == [nb("Mañana: Spotify, 10,99 € en Revolut")])
        #expect(lines(b, .investments) == [nb("Valen 1.510,00 €: +6,00 € en la última sesión (viernes) (+0,4 %)")])
        #expect(b.tip == nil)
        // Con una falta de saldo el día tranquilo conserva el consejo.
        var input = quiet()
        input.shortfalls = [Shortfall(bank: .rev, charge: spotify, balanceCents: 500, missingCents: 599, suggestedFrom: .ima, suggestedCents: 1_000)]
        #expect(makeBriefing(input, calendar: cal).tip?.id == "tip-shortfall")
    }

    @Test func unDiaConAvisosNoEsTranquilo() {
        var input = quiet()
        input.attention = [.bankProblem(.rev, .offline)]
        let b = makeBriefing(input, calendar: cal)
        #expect(!b.isQuiet)
        // J11: con un banco que no se ha podido leer, «nada nuevo» se limita a lo visto.
        #expect(render(b.headline, .plain) == "Nada nuevo en lo que he podido ver.")
        #expect(lines(b, .attention) == ["Sin conexión al actualizar Revolut."])
        // Un aviso que no es de conexión no cambia la frase.
        input.attention = [.warning(title: "Saldo bajo en Revolut", detail: nil)]
        #expect(render(makeBriefing(input, calendar: cal).headline, .plain) == "Nada nuevo desde ayer.")
    }

    @Test func vozPrivadaConAvisosDeBanco() {
        var input = quiet()
        input.attention = [.bankProblem(.rev, .offline)]
        let b = makeBriefing(input, calendar: cal)
        #expect(spokenBriefing(b, input: input, privateMode: true, calendar: cal)
            == "Buenos días. Tienes el modo privado activado, así que no leo importes. Nada nuevo en lo que he podido ver. Hay 1 aviso: Revolut. Esta semana vienen 2 cobros.")
        input.attention = [.bankProblem(.rev, .offline), .bankProblem(.ima, .bankUnavailable), .consentExpiring(.tr, nov(30, 10))]
        input.payments = [digest("Zara", 4_995)]
        let two = spokenBriefing(makeBriefing(input, calendar: cal), input: input, privateMode: true, calendar: cal)
        #expect(two.contains("Hay 2 avisos: Revolut y imagin."))
        #expect(two.contains("Desde ayer a las 08:30: 1 pago."))
    }

    // MARK: J10 — «hoy» solo si el cambio es de hoy

    @Test func elCambioDeUnaSesionAnteriorLoDice() {
        let friday = cal.startOfDay(for: nov(20))
        let thursday = cal.startOfDay(for: nov(19))
        func first(_ s: PortfolioSummary, now: Date = nov(20, 10)) -> String {
            let input = BriefingInput(now: now, since: nov(19, 22, 10), isFirst: false, investments: s)
            return lines(makeBriefing(input, calendar: cal), .investments)[0]
        }
        #expect(first(summary(changeDay: .some(friday))) == nb("Valen 1.510,00 €: +6,00 € hoy (+0,4 %)"))
        #expect(first(summary(changeDay: .some(thursday))) == nb("Valen 1.510,00 €: +6,00 € en la última sesión (jueves) (+0,4 %)"))
        // El lunes después de un viernes.
        #expect(first(summary(changeDay: .some(friday)), now: nov(23, 9))
            == nb("Valen 1.510,00 €: +6,00 € en la última sesión (viernes) (+0,4 %)"))
        // Sin día del cambio no hay texto de cambio, aunque haya cifra.
        var noDay = summary()
        noDay = PortfolioSummary(valueCents: noDay.valueCents, todayChangeCents: 600, todayChangeTenths: 4, changeDay: nil,
                                 costCents: noDay.costCents, gainCents: noDay.gainCents, gainTenths: noDay.gainTenths,
                                 pricedAt: noDay.pricedAt, oldestPriceAt: noDay.oldestPriceAt, hasStalePrice: false,
                                 missingPrices: 0, positions: [])
        #expect(first(noDay) == nb("Valen 1.510,00 €."))
    }

    // MARK: J13 — detalles

    @Test func enmascaraImportesEscritosDeOtraForma() {
        let texts = ["Cobro de 20 EUR", "Cobro de 5 euros", "Cobro de 13,99", "Cobro de 1.234,56 €", "Cobro de 20eur", "Cobro de 20 Euro"]
        for text in texts {
            let b = attentionBriefing([.warning(title: text, detail: nil)])
            let masked = render(b.sections[0].lines[0].parts, .masked)
            #expect(masked == "Cobro de •••", "\(text) -> \(masked)")
        }
        let shop = makeBriefing(BriefingInput(now: nov(20, 8, 30), since: nov(19, 22, 10), isFirst: false,
                                              payments: [digest("Cena 12,50 EUR", 1_000)]), calendar: cal)
        #expect(render(shop.sections.first { $0.kind == .happened }!.lines[0].parts, .masked) == "Cena •••: ••• con Revolut")
        // Lo que no es un importe se conserva.
        let plain = attentionBriefing([.warning(title: "Revisa el 12,5 por ciento", detail: "Euros de ayer")])
        #expect(render(plain.sections[0].lines[0].parts, .masked).contains("Euros de ayer"))
    }

    // MARK: J20 — lo que más subió y bajó

    private func mover(_ name: String, change: Int, value: Int = 10_000, at when: Date? = nov(20, 9)) -> PositionValue {
        let position = Position(instrument: name, name: name, assetClass: nil, shares: 1, costCents: 0, costIncomplete: false)
        guard let when else {
            return PositionValue(position: position, priceEUR: nil, origin: .none, valueCents: nil, todayChangeCents: nil,
                                 gainCents: nil, gainTenths: nil)
        }
        return PositionValue(position: position, priceEUR: 1, origin: .market(when), valueCents: value + change, todayChangeCents: change,
                             gainCents: nil, gainTenths: nil)
    }

    private func moversSummary(_ positions: [PositionValue], day: Date? = cal.startOfDay(for: nov(20))) -> PortfolioSummary {
        PortfolioSummary(valueCents: 151_000, todayChangeCents: 600, todayChangeTenths: 4, changeDay: day, costCents: 133_667,
                         gainCents: 17_333, gainTenths: 130, pricedAt: nov(20, 9), oldestPriceAt: nov(20, 9), hasStalePrice: false,
                         missingPrices: 0, positions: positions)
    }

    private func moversText(_ positions: [PositionValue], now: Date = nov(20, 10), day: Date? = cal.startOfDay(for: nov(20))) -> String? {
        let input = BriefingInput(now: now, since: nov(19, 22, 10), isFirst: false, investments: moversSummary(positions, day: day))
        let b = makeBriefing(input, calendar: cal)
        return b.sections.first { $0.kind == .investments }?.lines.first { $0.id == "inv-movers" }.map { render($0.parts, .plain) }
    }

    @Test func masSubioYMasBajo() {
        let text = moversText([mover("Alfa", change: 210), mover("Beta", change: -130), mover("Gamma", change: 10)])
        #expect(text == nb("Lo que más subió: Alfa (+2,1 %). Lo que más bajó: Beta (\u{2212}1,3 %)."))
        // Va justo después de la línea del valor.
        let input = BriefingInput(now: nov(20, 10), since: nov(19, 22, 10), isFirst: false,
                                  investments: moversSummary([mover("Alfa", change: 210), mover("Beta", change: -130)]))
        let ids = makeBriefing(input, calendar: cal).sections.first { $0.kind == .investments }!.lines.map(\.id)
        #expect(ids.prefix(2) == ["inv-value", "inv-movers"])
    }

    @Test func todoSubioSoloDiceLoQueMasSubio() {
        #expect(moversText([mover("Alfa", change: 210), mover("Beta", change: 50)]) == nb("Lo que más subió: Alfa (+2,1 %)."))
    }

    @Test func todoBajoSoloDiceLoQueMasBajo() {
        #expect(moversText([mover("Alfa", change: -130), mover("Beta", change: -400)]) == nb("Lo que más bajó: Beta (\u{2212}4,0 %)."))
    }

    @Test func sinLineaCuandoNoHayDosDistintas() {
        #expect(moversText([mover("Alfa", change: 210)]) == nil)
        #expect(moversText([]) == nil)
        // Todo a cero, o la misma subida en las dos.
        #expect(moversText([mover("Alfa", change: 0), mover("Beta", change: 0)]) == nil)
        #expect(moversText([mover("Alfa", change: 100), mover("Beta", change: 100)]) == nil)
        // Sin día del cambio.
        #expect(moversText([mover("Alfa", change: 210), mover("Beta", change: -130)], day: nil) == nil)
    }

    @Test func unPrecioDelViernesVistoElSabado() {
        let text = moversText([mover("Alfa", change: 210), mover("Beta", change: -130)], now: nov(21, 10))
        #expect(text == nb("En la última sesión (viernes), lo que más subió: Alfa (+2,1 %). Lo que más bajó: Beta (\u{2212}1,3 %)."))
        let onlyUp = moversText([mover("Alfa", change: 210), mover("Beta", change: 50)], now: nov(21, 10))
        #expect(onlyUp == nb("En la última sesión (viernes), lo que más subió: Alfa (+2,1 %)."))
    }

    @Test func lasPosicionesSinPrecioONoDelDiaSeIgnoran() {
        // Una sin precio no cuenta: con solo una válida no hay línea.
        #expect(moversText([mover("Alfa", change: 210), mover("Beta", change: 0, at: nil)]) == nil)
        // Con otra válida, sí, y la sin precio no aparece.
        let text = moversText([mover("Alfa", change: 210), mover("Beta", change: 0, at: nil), mover("Gamma", change: -130)])
        #expect(text == nb("Lo que más subió: Alfa (+2,1 %). Lo que más bajó: Gamma (\u{2212}1,3 %)."))
        // Un precio de otro día no es del mismo cambio.
        let old = moversText([mover("Alfa", change: 210), mover("Beta", change: -130, at: nov(18, 9))])
        #expect(old == nil)
    }

    @Test func losNombresLargosDeLasPosicionesSeRecortan() {
        let long = String(repeating: "N", count: 60)
        let text = moversText([mover(long, change: 210), mover("Beta", change: -130)])
        #expect(text?.contains(String(repeating: "N", count: 39) + "…") == true)
    }

    @Test func laLineaNoLlevaPalabrasDeAccionNiLlegaAlModelo() {
        var input = busy()
        input.investments = moversSummary([mover("Alfa", change: 210), mover("Beta", change: -130)])
        let b = makeBriefing(input, calendar: cal)
        let line = lines(b, .investments).first { $0.hasPrefix("Lo que más") } ?? ""
        #expect(!line.isEmpty)
        for action in ["compra", "vende", "mant", "espera", "aprovecha", "recomiend", "conviene", "debes"] {
            #expect(!line.lowercased().contains(action), "\(action)")
        }
        #expect(!briefingModelPrompt(b).contains("Lo que más"))
        // Con el modo privado los porcentajes se tapan igual que en la línea del valor; los nombres se quedan.
        let masked = render(b.sections.first { $0.kind == .investments }!.lines[1].parts, .masked)
        #expect(masked == "Lo que más subió: Alfa (•••). Lo que más bajó: Beta (•••).")
        // La voz normal la lee; la privada no.
        let spoken = spokenBriefing(b, input: input, privateMode: false, calendar: cal)
        #expect(spoken.contains("Lo que más subió: Alfa, más 2,1 por ciento."))
        #expect(spoken.contains("Lo que más bajó: Beta, menos 1,3 por ciento."))
        #expect(!spokenBriefing(b, input: input, privateMode: true, calendar: cal).contains("Lo que más"))
    }

    @Test func enmascaraLaMonedaEscritaAntesDelNumero() {
        let cases = [("Cobro de €13", "Cobro de •••"), ("Cobro de EUR 20", "Cobro de •••"), ("Cobro de € 13,50", "Cobro de •••"),
                     ("Cobro €13.", "Cobro •••."), ("Cobro de euros 5", "Cobro de •••"), ("Cobro de eur20", "Cobro de •••")]
        for (text, expected) in cases {
            let b = attentionBriefing([.warning(title: text, detail: nil)])
            #expect(render(b.sections[0].lines[0].parts, .masked) == expected, "\(text)")
        }
    }

    @Test func elTotalDiceUnosSiAlgunSaldoEsEstimado() {
        var input = BriefingInput(now: nov(20, 8, 30), since: nov(19, 22, 10), isFirst: false,
                                  banks: [BankLine(bank: .rev, cents: 10_000, estimated: false, changeCents: 0),
                                          BankLine(bank: .ima, cents: 20_000, estimated: true, changeCents: 0)],
                                  totalCents: 30_000, payments: [digest("Zara", 100)])
        #expect(lines(makeBriefing(input, calendar: cal), .money).first == nb("En total, unos 300,00 € (sin cambios)"))
        input.banks = [BankLine(bank: .rev, cents: 10_000, estimated: false, changeCents: 0)]
        input.totalCents = 10_000
        #expect(lines(makeBriefing(input, calendar: cal), .money).first == nb("En total, 100,00 € (sin cambios)"))
    }

    @Test func nuncaUnosCeroAlDia() {
        var input = busy()
        input.budgetTip = BudgetTip(name: "Comer fuera", remainingCents: 100)
        input.freeMoney = FreeMoney(cents: 154_977, daysLeft: 11)
        // El consejo del presupuesto saldría «unos 0 € al día»: se salta y vale el del dinero libre.
        #expect(makeBriefing(input, calendar: cal).tip?.id == "tip-free")
        input.freeMoney = FreeMoney(cents: 200, daysLeft: 11)
        #expect(makeBriefing(input, calendar: cal).tip == nil)
        for tip in [makeBriefing(busy(), calendar: cal).tip!] { #expect(!render(tip.parts, .plain).contains("unos 0")) }
    }

    @Test func valenAlMenosDiceDeCualesEs() {
        // Con un día movido (no tranquilo) sale también la línea de la ganancia.
        var input = busy()
        input.investments = summary(missing: 1)
        let partial = lines(makeBriefing(input, calendar: cal), .investments)
        #expect(partial[0].hasPrefix(nb("Valen al menos 1.510,00 € de las que tienen precio")))
        #expect(partial[1].hasPrefix(nb("Desde la compra, de las que tienen precio: +173,33 €")))
        input.investments = summary()
        #expect(!lines(makeBriefing(input, calendar: cal), .investments).joined().contains("de las que tienen precio"))
    }

    @Test func nombresLargosSeRecortanA40() {
        let long = String(repeating: "A", count: 60)
        let b = makeBriefing(BriefingInput(now: nov(20, 8, 30), since: nov(19, 22, 10), isFirst: false,
                                           income: [digest(long, 5_000)], payments: [digest(long, 1_000)],
                                           upcoming: [UpcomingCharge(name: long, bank: .rev, cents: 100, date: nov(21, 12))]),
                             calendar: cal)
        let clipped = String(repeating: "A", count: 39) + "…"
        #expect(lines(b, .happened)[0].hasPrefix("Entró \(clipped): "))
        #expect(lines(b, .happened)[1].hasPrefix("\(clipped): "))
        #expect(lines(b, .upcoming)[0].contains(", ") && lines(b, .upcoming)[0].contains(clipped))
        // Un nombre de 40 no se toca.
        let exact = String(repeating: "B", count: 40)
        let b2 = makeBriefing(BriefingInput(now: nov(20, 8, 30), since: nov(19, 22, 10), isFirst: false, payments: [digest(exact, 1_000)]),
                              calendar: cal)
        #expect(lines(b2, .happened)[0].hasPrefix("\(exact): "))
    }

    @Test func laVozNoReescribeElNombreDelComercio() {
        var input = BriefingInput(now: nov(20, 8, 30), since: nov(19, 22, 10), isFirst: false,
                                  payments: [digest("Gym +24 % -5€", 3_000)])
        input.totalCents = nil
        let b = makeBriefing(input, calendar: cal)
        let text = spokenBriefing(b, input: input, privateMode: false, calendar: cal)
        #expect(text.contains("Gym +24 % -5€: 30,00 euros con Revolut"))
        #expect(!text.contains("más 24"))
        // Lo que no es nombre sí se dice en palabras.
        let total = BriefingInput(now: nov(20, 8, 30), since: nov(19, 22, 10), isFirst: false,
                                  banks: [BankLine(bank: .rev, cents: 10_000, estimated: false, changeCents: 500)], totalCents: 10_000,
                                  totalChangeCents: 500, payments: [digest("Zara", 100)])
        #expect(spokenBriefing(makeBriefing(total, calendar: cal), input: total, privateMode: false, calendar: cal)
            .contains("más 5,00 euros"))
    }

    @Test func titulares() {
        func headline(since: Date, now: Date, income: [MovementDigest] = [], payments: [MovementDigest] = [],
                      transfers: [TransferDigest] = [], isFirst: Bool = false) -> String {
            let input = BriefingInput(now: now, since: since, isFirst: isFirst, income: income, payments: payments, transfers: transfers)
            return render(makeBriefing(input, calendar: cal).headline, .plain)
        }
        #expect(headline(since: nov(20, 8, 30), now: nov(20, 13), payments: [digest("Mercadona", 1_250)])
            == nb("Desde las 08:30 gastaste 12,50 € en 1 pago."))
        #expect(headline(since: nov(18, 9), now: nov(20, 8, 30), income: [digest("Nómina ACME", 185_000, .ima)])
            == nb("Desde el miércoles entraron 1.850,00 €."))
        #expect(headline(since: nov(19, 22, 10), now: nov(20, 8, 30), transfers: [TransferDigest(from: .ima, to: .rev, cents: 100)])
            == "Desde ayer a las 22:10 solo has movido dinero entre tus cuentas.")
        #expect(headline(since: nov(20, 8, 30), now: nov(20, 13)) == "Nada nuevo desde las 08:30.")
        #expect(headline(since: nov(18, 9), now: nov(20, 8, 30)) == "Nada nuevo desde el miércoles.")
        #expect(headline(since: nov(19, 8), now: nov(20, 8, 30), isFirst: true) == "Nada nuevo en las últimas 24 horas.")
    }

    @Test func problemasDeBanco() {
        func text(_ item: AttentionItem) -> String { lines(attentionBriefing([item]), .attention)[0] }
        func action(_ item: AttentionItem) -> BriefingAction? { attentionBriefing([item]).sections[0].lines[0].action }
        #expect(text(.bankProblem(.ima, .offline)) == "Sin conexión al actualizar imagin.")
        #expect(text(.bankProblem(.ima, .rateLimited)) == "imagin ha pedido una pausa: vuelvo a mirar en unas horas.")
        #expect(text(.bankProblem(.ima, .consentExpired)) == "La conexión con imagin ha caducado: renuévala en Ajustes.")
        #expect(text(.bankProblem(.ima, .keyRejected)) == "La conexión con imagin ha caducado: renuévala en Ajustes.")
        #expect(action(.bankProblem(.ima, .consentExpired)) == .openBankSettings(.ima))
        #expect(action(.bankProblem(.ima, .keyRejected)) == .openBankSettings(.ima))
        #expect(text(.budgetExceeded(name: "Comer fuera", spentCents: 12_540, limitCents: 12_000))
            == nb("Te has pasado en Comer fuera: 125,40 € de 120,00 €."))
        #expect(action(.budgetExceeded(name: "Comer fuera", spentCents: 12_540, limitCents: 12_000)) == .openBudgets)
        #expect(text(.warning(title: "Cobro repetido en Netflix", detail: "13,99 € dos veces hoy"))
            == "Cobro repetido en Netflix. 13,99 € dos veces hoy")
        #expect(text(.warning(title: "Saldo bajo en Revolut", detail: nil)) == "Saldo bajo en Revolut")
    }

    // MARK: Cartera honesta

    private func investmentLines(_ s: PortfolioSummary) -> [String] {
        let input = BriefingInput(now: nov(20, 8, 30), since: nov(19, 22, 10), isFirst: false, investments: s)
        return lines(makeBriefing(input, calendar: cal), .investments)
    }

    @Test func carteraParcialSeDiceParcial() {
        let partial = investmentLines(summary(missing: 2))
        #expect(partial[0].hasPrefix("Valen al menos "))
        #expect(partial.contains("Falta el precio de 2 posiciones."))
        #expect(investmentLines(summary(missing: 1)).contains("Falta el precio de 1 posición."))
        let stale = investmentLines(summary(stale: true))
        #expect(stale.contains { $0.contains("Algún precio es viejo") && $0.contains("10 nov") })
    }

    @Test func sinCambioDeHoyNoSeEscribe() {
        let lines = investmentLines(summary(today: false))
        #expect(lines[0] == nb("Valen 1.510,00 €."))
        #expect(!lines.contains { $0.contains("hoy") })
    }

    @Test func sinPreciosNoHayCifra() {
        let none = PortfolioSummary(valueCents: nil, todayChangeCents: nil, todayChangeTenths: nil, changeDay: nil, costCents: 10_000, gainCents: nil,
                                    gainTenths: nil, pricedAt: nil, oldestPriceAt: nil, hasStalePrice: false, missingPrices: 1, positions: [])
        let text = investmentLines(none)
        #expect(text == ["Aún no tengo precios de tus inversiones."])
    }

    @Test func saldosSinDatoYEstimados() {
        var input = BriefingInput(now: nov(20, 8, 30), since: nov(19, 22, 10), isFirst: false,
                                  banks: [BankLine(bank: .tr, cents: nil, estimated: false, changeCents: 20_000)],
                                  income: [digest("Venta", 20_000, .tr)])
        #expect(lines(makeBriefing(input, calendar: cal), .money) == [nb("Trade Republic: aún sin saldo (+200,00 €)")])
        // Si todos los saldos conocidos son estimados, el total también es aproximado.
        input.banks = [BankLine(bank: .ima, cents: 100_000, estimated: true, changeCents: 0)]
        input.totalCents = 100_000
        #expect(lines(makeBriefing(input, calendar: cal), .money).first == nb("En total, unos 1.000,00 € (sin cambios)"))
    }

    // MARK: Privacidad

    @Test func enmascarado() {
        let b = makeBriefing(busy(), calendar: cal)
        let total = b.sections[0].lines[0]
        #expect(render(total.parts, .masked) == "En total, unos ••• (•••)")
        var all = [render(b.headline, .masked)]
        for section in b.sections { all += section.lines.map { render($0.parts, .masked) } }
        all.append(render(b.tip!.parts, .masked))
        for line in all {
            #expect(!line.contains("€"), "\(line)")
            #expect(line.range(of: "[0-9],[0-9]{2}", options: .regularExpression) == nil, "\(line)")
            #expect(line.range(of: "[0-9]\\.[0-9]{3}", options: .regularExpression) == nil, "\(line)")
        }
        // Un importe escrito dentro de un texto también se tapa.
        let warning = attentionBriefing([.warning(title: "Cobro repetido en Netflix", detail: "13,99\u{00A0}€ dos veces hoy")])
        #expect(render(warning.sections[0].lines[0].parts, .masked) == "Cobro repetido en Netflix. ••• dos veces hoy")
        let plainSpace = attentionBriefing([.warning(title: "Cobro", detail: "13,99 € dos veces")])
        #expect(render(plainSpace.sections[0].lines[0].parts, .masked) == "Cobro. ••• dos veces")
    }

    @Test func vozEnModoPrivado() {
        let input = busy()
        let b = makeBriefing(input, calendar: cal)
        let text = spokenBriefing(b, input: input, privateMode: true, calendar: cal)
        #expect(text == "Buenos días. Tienes el modo privado activado, así que no leo importes. Desde ayer a las 22:10: 1 ingreso, 2 pagos y 1 traspaso entre tus cuentas. Hay 1 aviso: imagin. Esta semana vienen 2 cobros.")
        // Ningún importe, escrito de ninguna forma.
        #expect(!text.contains("€") && !text.contains("euros"))
        #expect(text.range(of: "[0-9],[0-9]{2}", options: .regularExpression) == nil)
        #expect(text.range(of: "[0-9]\\.[0-9]{3}", options: .regularExpression) == nil)
        var amounts = input.income.map(\.cents) + input.payments.map(\.cents) + input.transfers.map(\.cents) + input.upcoming.map(\.cents)
        amounts += input.banks.compactMap(\.cents) + [input.totalCents ?? 0, input.totalChangeCents]
        for cents in amounts {
            #expect(!text.contains(formatEUR(cents)))
            #expect(!text.contains(formatEURWhole(cents)))
        }
        let spoken = spokenBriefing(b, input: input, privateMode: false, calendar: cal)
        #expect(spoken.hasPrefix(nb("Buenos días. Desde ayer a las 22:10 entraron 1.850,00 € y gastaste 62,45 € en 2 pagos.")))
        #expect(spoken.contains("euros"))
        #expect(spoken.contains("más 1.787,55 euros"))
        #expect(!spoken.contains("+"))
    }

    @Test func vozPrivadaEnDiaTranquiloYConUnCobro() {
        var input = quiet()
        input.upcoming = [spotify]
        let b = makeBriefing(input, calendar: cal)
        #expect(spokenBriefing(b, input: input, privateMode: true, calendar: cal)
            == "Buenos días. Tienes el modo privado activado, así que no leo importes. Nada nuevo desde ayer. Esta semana viene 1 cobro.")
    }

    // MARK: Hechos y barreras

    @Test func hechos() {
        let b = makeBriefing(busy(), calendar: cal)
        let facts = displayFacts(b)
        #expect(facts.first == render(b.headline, .plain))
        #expect(facts.count == 1 + b.sections.reduce(0) { $0 + $1.lines.count } + 1)
        #expect(facts.last == render(b.tip!.parts, .plain))
    }


    @Test func modeloConConsejo() {
        #expect(containsInvestmentAdvice("Te recomiendo comprar más acciones de Apple."))
        #expect(containsInvestmentAdvice("Deberías vender el ETF."))
        #expect(containsInvestmentAdvice("Invierte en oro."))
        #expect(containsInvestmentAdvice("TE RECOMIENDO VENDER"))
        #expect(containsInvestmentAdvice("Es un buen momento para comprar."))
        // Hablar de inversiones con el modelo ya no se admite, digan lo que digan: la frase de las reglas las cuenta.
        #expect(containsInvestmentAdvice("Tus inversiones han subido un 0,4 % hoy."))
        #expect(!containsInvestmentAdvice("Buenos días, hoy no hay sorpresas."))
        #expect(investmentAdviceRefusal == "No puedo decirte qué comprar, vender o cuánto invertir: eso solo puede hacerlo un asesor financiero autorizado. Sí puedo contarte cómo van tus inversiones.")
    }

    // MARK: J7 — nunca consejos de inversión

    @Test(arguments: [
        "te conviene vender", "mantén tus acciones", "aprovecha la caída", "yo que tú compraría", "te recomiendo que vendas",
        "no vendas", "invierte un poco cada mes", "buen momento de comprar", "es hora de vender", "vende.", "you should sell",
        "buy more", "hold",
        // El resto de la lista del encargo.
        "Te CONVIENE esperar", "Te aconsejo esperar", "Te sugiero esperar", "Te sugerimos esperar", "Deberías esperar",
        "Debes esperar", "Tienes que esperar", "Hay que esperar", "Yo de ti esperaría", "Yo que tu esperaria", "El momento de actuar",
        "Es una buena idea", "Vale la pena", "Merece la pena", "Aguanta un poco", "Diversifica tu cartera", "Reequilibra la cartera",
        "Mantienes tus fondos", "Mantuviste tus fondos", "Compra más acciones", "Hoy. Compra algo de oro", "Invertir en oro",
        "Invertirías en oro", "Inviertes bien", "No compres nada", "Comprar o vender", "Vendería todo", "Sell now", "Please BUY",
        "I would hold", "You should wait", "Invest in gold", "I recommend waiting", "Te recomendamos esperar", "Aprovechando la subida",
        "Te lo recomiendo",
    ]) func rechazaConsejos(_ text: String) {
        #expect(containsAdvice(text), "\(text)")
        #expect(containsInvestmentAdvice(text))
    }

    @Test(arguments: [
        "has comprado en Mercadona", "tu compra más cara fue Zara", "venta de garaje", "Compraste algo ayer", "Vendiste algo ayer",
        "Has vendido tu bici", "Tus compras de hoy", "La compra de ayer fue grande", "Cada compra cuenta", "Buenos días, hoy no hay sorpresas",
        "Ha entrado tu nómina", "Ayer fue un día de pocos gastos", "Qué buena mañana",
    ]) func aceptaDescripciones(_ text: String) {
        #expect(!containsAdvice(text), "\(text)")
    }

    // MARK: J15 — consejos en capas

    /// Capa (b): formato, guiones y otras escrituras.
    @Test(arguments: [
        "ve\u{00AD}nde", "ven\u{200B}de", "ven\u{200D}de", "ven-de", "ven-\nde", "ven\nde", "ven\u{2010}de", "vеnde", "comprаr", "ΒΙΒΛΙΟ",
        "buenos días 日本",
    ]) func capaNormalizacion(_ text: String) {
        #expect(containsAdvice(text), "\(text)")
    }

    @Test func capaNormalizacionPorPartes() {
        #expect(withoutFormatCharacters("a\u{00AD}b\u{200B}c\u{200D}d") == "abcd")
        #expect(hasNonLatinLetter("vеnde"))
        #expect(!hasNonLatinLetter("Mañana, señor Ñandú, ¡sí! café"))
        // Una tilde descompuesta (e + U+0301) no es otra escritura.
        #expect(!hasNonLatinLetter("cafe\u{0301}"))
        #expect(wordReadings("ven-\nde").contains(["vende"]))
    }

    /// Capa (c): vocabulario de inversiones.
    @Test(arguments: [
        "Tus inversiones", "Tu cartera sube", "Las acciones", "Un fondo indexado", "La bolsa hoy", "El mercado", "Tu posición", "Exposición alta",
        "Beneficios del día", "Una pérdida", "La cotización", "Dividendos", "El valor total", "El precio", "Un ETF", "Cripto", "Bitcoin",
        "Tu broker", "Your stocks", "Your shares", "The market", "A fund", "The portfolio", "Profit today", "Crypto", "Your assets", "Holdings",
        "Invertiste", "Lo invertido", "Inversión",
    ]) func capaVocabulario(_ text: String) {
        #expect(hasInvestmentVocabulary(text), "\(text)")
        #expect(containsAdvice(text), "\(text)")
    }

    @Test func vocabularioNoRechazaMercadona() {
        #expect(!hasInvestmentVocabulary("has comprado en Mercadona"))
        #expect(!hasInvestmentVocabulary("Buenos días, hoy no hay sorpresas"))
    }

    /// Capa (d): marcadores.
    @Test(arguments: [
        "mejor esperar", "espera a que baje", "aguarda un poco", "convendría esperar", "tendrías que", "habría que", "debemos", "debería",
        "podrías", "considera esperar", "plantéate", "quédate como estás", "deshazte de", "acumula", "promedia a la baja", "reduce",
        "refuerza", "refuerzo", "sal de esa", "entra en el", "toma nota", "evita eso", "procura", "intenta", "wait a bit", "stay put",
        "get out", "take profits", "consider it", "avoid it", "better", "Mejor así",
    ]) func capaMarcadores(_ text: String) {
        #expect(hasAdviceMarker(text), "\(text)")
        #expect(containsAdvice(text), "\(text)")
    }

    /// Capa (e): compra y venta solo como sustantivo tras un determinante.
    @Test(arguments: [
        "compra", "Oye, compra ahora", "mejor compra ya", "si compras hoy", "compras", "venta", "ventas ya", "Hoy: venta", "Dos ventas",
        "no compra nada", "Compra más", "compra de ayer",
    ]) func capaCompraVentaVerbo(_ text: String) {
        #expect(hasTradeVerb(text), "\(text)")
        #expect(containsAdvice(text), "\(text)")
    }

    @Test(arguments: [
        "tu compra", "tus compras", "la venta", "las ventas", "una compra", "esa venta", "mi compra", "su venta", "de compras",
        "cada compra", "última compra", "primera venta", "venta de garaje",
    ]) func compraVentaComoSustantivo(_ text: String) {
        #expect(!hasTradeVerb(text), "\(text)")
    }

    /// La tabla grande del re-examen: todo lo que se coló.
    @Test(arguments: [
        "mejor esperar", "espera a que baje", "no toques tu cartera", "quédate como estás", "sal de esa posición", "entra en el fondo",
        "refuerza tu posición", "reduce exposición", "toma beneficios", "deshazte de", "acumula", "promedia a la baja",
        "time to take profits", "stay put", "get out", "Oye, compra ahora", "mejor compra ya", "si compras hoy", "convendría esperar",
        "tendrías que", "habría que", "ve\u{00AD}nde", "ven\u{200B}de", "vеnde", "ven\nde", "ven-de", "ven-\nde",
        "te conviene vender", "mantén tus acciones", "aprovecha la caída", "yo que tú compraría", "te recomiendo que vendas",
        "no vendas", "invierte un poco cada mes", "buen momento de comprar", "es hora de vender", "vende.", "you should sell",
        "buy more", "hold",
    ]) func tablaGrandeRechaza(_ text: String) {
        #expect(containsAdvice(text), "\(text)")
    }

    @Test func tablaGrandeAcepta() {
        for text in ["has comprado en Mercadona", "tu compra más cara fue Zara", "venta de garaje"] {
            #expect(!containsAdvice(text), "\(text)")
        }
    }

    // MARK: J16 — más palabras de número

    @Test(arguments: [
        "un par de cosas", "dos pares", "una docena", "unas docenas", "una decena", "decenas de", "un centenar", "centenares",
        "un millar", "millares", "un billón", "billones", "un cuarto", "tres cuartos", "un tercio", "tercios", "un quinto", "quintos",
        "a dozen", "dozens", "a couple", "couples", "a pair", "pairs", "a billion", "billions", "a quarter", "quarters", "a third",
        "thirds", "percent", "II", "XIV", "MMXXVI", "Hoy es XII", "ven\u{200B}ti cinco", "do\u{00AD}s", "d\u{200B}os euros",
    ]) func masPalabrasDeNumero(_ text: String) {
        #expect(containsNumber(text), "\(text)")
    }

    @Test(arguments: [
        "Un día", "Uno de ellos", "Una nómina", "mi casa", "di la verdad", "La mayoría de gastos", "Mix de pagos", "Buenos días",
    ]) func siguenSiendoValidasSinNumero(_ text: String) {
        #expect(!containsNumber(text), "\(text)")
    }

    // MARK: J8 — la frase del modelo no lleva números

    @Test(arguments: [
        "Ayer gastaste 62 €.", "Entraron 1.850,00 € ayer", "Has gastado 3 veces", "Tienes ½ de lo normal", "Gastaste dos euros",
        "Cinco pagos ayer", "Veinte euros menos", "Veinticinco pagos", "Veintiún pagos", "Treinta días", "Noventa euros",
        "Cien euros", "Ciento diez", "Doscientos euros", "Quinientos euros", "Mil euros", "Un millón", "Dos millones", "Medio mes",
        "La mitad", "El doble", "El triple", "Two payments", "Ten euros", "Twenty euros", "A hundred", "Thousand", "A million",
        "Half of it", "Double", "Cero gastos", "Seven days", "Hoy ٣ pagos", "Ⅳ pagos",
    ]) func rechazaNumeros(_ text: String) {
        #expect(containsNumber(text), "\(text)")
    }

    @Test(arguments: [
        "Buenos días, hoy no hay sorpresas.", "Un día tranquilo", "Una nómina ha llegado", "Uno de tus pagos", "Hoy cobras algo",
        "Ayer fue un día de pocos gastos", "Qué buena mañana",
    ]) func aceptaTextoSinNumeros(_ text: String) {
        #expect(!containsNumber(text), "\(text)")
    }

    // MARK: Del libro al texto

    @Test func delLibroAlTexto() {
        var state = LedgerState()
        state.movements = [
            Movement(bank: .rev, amountCents: -1_250, merchant: "Mercadona", kind: .payment, source: .notification,
                     date: nov(20, 7), isShop: true),
            // Un traspaso entre tus cuentas no es gasto ni ingreso.
            Movement(bank: .ima, amountCents: -20_000, merchant: "Transferencia a Revolut", kind: .payment, source: .notification,
                     date: nov(20, 7, 49)),
            Movement(bank: .rev, amountCents: 20_000, merchant: "Transferencia de imagin", kind: .income, source: .notification,
                     date: nov(20, 7, 50)),
        ]
        let record = BriefingRecord(shownAt: nov(20, 8, 30), since: nov(19, 22, 10))
        let input = briefingInput(state: state, portfolio: nil, book: AccountBook(), record: record, isFirst: false, now: nov(20, 8, 30),
                                  calendar: cal)
        let b = makeBriefing(input, calendar: cal)
        #expect(render(b.headline, .plain) == nb("Desde ayer a las 22:10 gastaste 12,50 € en 1 pago."))
        #expect(lines(b, .happened).last == nb("200,00 € de imagin a Revolut (entre tus cuentas)"))
    }
}
