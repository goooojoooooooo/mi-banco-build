import Foundation
import Testing
@testable import MiBancoCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Madrid")!
    c.locale = Locale(identifier: "es_ES")
    return c
}()

private func date(_ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, year: Int = 2026) -> Date {
    cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private func nov(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date { date(11, day, hour, minute) }

private func pay(_ cents: Int, _ merchant: String?, _ when: Date, bank: BankID = .rev, flagged: Bool = false) -> Movement {
    Movement(bank: bank, amountCents: -cents, merchant: merchant, kind: .payment, source: .notification, date: when,
             flaggedNotMine: flagged)
}

private func income(_ cents: Int, _ merchant: String?, _ when: Date) -> Movement {
    Movement(bank: .ima, amountCents: cents, merchant: merchant, kind: .income, source: .notification, date: when)
}

private func ledger(_ movements: [Movement], settings: AlertSettings = AlertSettings(), muted: Set<String> = [],
                    balances: [BankID: ManualBalance] = [:]) -> LedgerState {
    LedgerState(balances: balances, movements: movements, unread: [], alertSettings: settings, mutedMerchants: muted)
}

private func kinds(_ list: [Insight]) -> [InsightKind] { list.map(\.kind) }

@Suite struct SubscriptionTests {
    @Test func dosCargosMensuales() {
        let ms = [pay(1399, "Netflix", date(10, 19)), pay(1399, "Netflix", nov(19))]
        let subs = detectSubscriptions(in: ms, now: nov(19, 13), calendar: cal)
        #expect(subs.count == 1)
        #expect(subs[0].id == "netflix")
        #expect(subs[0].amountCents == 1399)
        #expect(subs[0].previousAmountCents == nil)
        #expect(subs[0].nextDate == date(12, 19))
    }

    @Test func tresCargosMensuales() {
        let plain = [pay(999, "Spotify", date(9, 19)), pay(999, "SPOTIFY", date(10, 19)), pay(999, "Spotify", nov(19))]
        #expect(detectSubscriptions(in: plain, now: nov(20), calendar: cal).count == 1)
    }

    @Test func veinteDiasNoEncaja() {
        let ms = [pay(1399, "Netflix", nov(1)), pay(1399, "Netflix", nov(21))]
        #expect(detectSubscriptions(in: ms, now: nov(22), calendar: cal).isEmpty)
    }

    @Test func limitesDeDias() {
        // 26 y 35 días sí; 25 y 36 no.
        func gap(_ days: Int) -> Int {
            let first = nov(1)
            let second = cal.date(byAdding: .day, value: days, to: first)!
            return detectSubscriptions(in: [pay(500, "Gym", first), pay(500, "Gym", second)], now: second, calendar: cal).count
        }
        #expect(gap(25) == 0)
        #expect(gap(26) == 1)
        #expect(gap(35) == 1)
        #expect(gap(36) == 0)
    }

    @Test func canceladaSiPasaron45Dias() {
        let ms = [pay(1399, "Netflix", date(9, 6)), pay(1399, "Netflix", date(10, 6))]
        #expect(detectSubscriptions(in: ms, now: nov(19), calendar: cal).count == 1)      // 44 días
        #expect(detectSubscriptions(in: ms, now: nov(20), calendar: cal).isEmpty)         // 45 días
    }

    @Test func subidaDePrecio() {
        let ms = [pay(1099, "Spotify", date(10, 19)), pay(1199, "Spotify", nov(19))]
        let subs = detectSubscriptions(in: ms, now: nov(19, 13), calendar: cal)
        #expect(subs.first?.amountCents == 1199)
        #expect(subs.first?.previousAmountCents == 1099)
    }

    @Test func importesMuyDistintosNoEncajan() {
        let ms = [pay(1000, "Tienda", date(10, 19)), pay(2000, "Tienda", nov(19))]
        #expect(detectSubscriptions(in: ms, now: nov(19, 13), calendar: cal).isEmpty)
        let near = [pay(1000, "Tienda", date(10, 19)), pay(1250, "Tienda", nov(19))]
        #expect(detectSubscriptions(in: near, now: nov(19, 13), calendar: cal).count == 1)
    }

    @Test func ignoraIngresosMarcadosYOtroBanco() {
        let flagged = [pay(999, "Spotify", date(10, 19), flagged: true), pay(999, "Spotify", nov(19))]
        #expect(detectSubscriptions(in: flagged, now: nov(19, 13), calendar: cal).isEmpty)
        let banks = [pay(999, "Spotify", date(10, 19), bank: .ima), pay(999, "Spotify", nov(19), bank: .rev)]
        #expect(detectSubscriptions(in: banks, now: nov(19, 13), calendar: cal).isEmpty)
        let inc = [income(999, "Spotify", date(10, 19)), income(999, "Spotify", nov(19))]
        #expect(detectSubscriptions(in: inc, now: nov(19, 13), calendar: cal).isEmpty)
    }

    @Test func ordenadasPorProximoCobro() {
        let ms = [pay(500, "B", date(10, 25)), pay(500, "B", date(9, 25)), pay(500, "A", date(10, 20)), pay(500, "A", date(9, 20))]
        #expect(detectSubscriptions(in: ms, now: nov(1), calendar: cal).map(\.id) == ["a", "b"])
    }
}

@Suite struct SpendingTests {
    @Test func ritmoMismoPuntoDelMesPasado() {
        let ms = [
            pay(10_000, "A", date(10, 5)), pay(5_000, "B", date(10, 19, 11)), pay(7_000, "C", date(10, 19, 13)),
            pay(20_000, "D", date(10, 25)), pay(3_000, "E", nov(2)), pay(3_500, "F", nov(18)),
            pay(99_999, "G", nov(5), flagged: true), income(50_000, "Nómina", nov(3)),
        ]
        let p = spendingPace(movements: ms, now: nov(19), calendar: cal)
        #expect(p == SpendingPace(thisMonthCents: 6_500, lastMonthSamePointCents: 15_000))
        #expect(p?.differenceCents == -8_500)
    }

    @Test func ritmoAjustaElDiaAlMesMasCorto() {
        let ms = [pay(1_000, "A", nov(15)), pay(2_000, "B", nov(30, 11)), pay(3_000, "C", nov(30, 13)), pay(500, "D", date(12, 2))]
        let p = spendingPace(movements: ms, now: date(12, 31), calendar: cal)
        #expect(p == SpendingPace(thisMonthCents: 500, lastMonthSamePointCents: 3_000))
    }

    @Test func ritmoMesCortoElOtroLado() {
        let ms = [pay(100, "A", date(10, 30, 11)), pay(200, "B", date(10, 31, 11)), pay(50, "C", nov(2))]
        let p = spendingPace(movements: ms, now: nov(30), calendar: cal)
        #expect(p?.lastMonthSamePointCents == 100)
    }

    @Test func ritmoNilSinPagosEnElMesAnterior() {
        let ms = [pay(1_000, "A", nov(2)), income(5_000, "Nómina", date(10, 3))]
        #expect(spendingPace(movements: ms, now: nov(19), calendar: cal) == nil)
        #expect(spendingPace(movements: [], now: nov(19), calendar: cal) == nil)
    }

    @Test func semanaCruzaElLunes() {
        let ms = [
            pay(1_000, "Mercadona", nov(22, 23, 30)), pay(2_000, "Zara", nov(23, 0, 30)), pay(500, "Mercadona", nov(16, 0, 10)),
            pay(300, "Zara", nov(15, 23, 50)), pay(400, "Zara", nov(9, 10)), pay(9_000, "Zara", nov(17), flagged: true),
        ]
        let w1 = weekSummary(movements: ms, weekContaining: nov(18), calendar: cal)
        #expect(w1 == WeekSummary(spentCents: 1_500, previousWeekSpentCents: 700, movementCount: 2, topMerchant: "Mercadona"))
        let w2 = weekSummary(movements: ms, weekContaining: nov(23), calendar: cal)
        #expect(w2 == WeekSummary(spentCents: 2_000, previousWeekSpentCents: 1_500, movementCount: 1, topMerchant: "Zara"))
        var sundayFirst = cal
        sundayFirst.firstWeekday = 1
        #expect(weekSummary(movements: ms, weekContaining: nov(18), calendar: sundayFirst) == w1)
        let empty = weekSummary(movements: [], weekContaining: nov(18), calendar: cal)
        #expect(empty == WeekSummary(spentCents: 0, previousWeekSpentCents: 0, movementCount: 0, topMerchant: nil))
    }

    @Test func historialDeUnComercio() {
        let ms = [
            pay(1_000, "Mercadona", date(9, 3)), pay(1_250, "MERCADONA Torrejón S.A.", nov(2)), pay(750, "Mercadona", nov(10)),
            pay(300, "Zara", nov(11)), pay(900, "Mercadona", nov(12), flagged: true), pay(100, "Mercadona", nov(25)),
        ]
        let h = merchantHistory(for: "mercadona torrejon", in: ms, now: nov(19), calendar: cal)
        #expect(h == MerchantHistory(countThisMonth: 1, totalThisMonthCents: 1_250, countAllTime: 1, firstDate: nov(2)))
        let h2 = merchantHistory(for: "Mercadona", in: ms, now: nov(19), calendar: cal)
        #expect(h2 == MerchantHistory(countThisMonth: 1, totalThisMonthCents: 750, countAllTime: 3, firstDate: date(9, 3)))
        let none = merchantHistory(for: "Nada", in: ms, now: nov(19), calendar: cal)
        #expect(none == MerchantHistory(countThisMonth: 0, totalThisMonthCents: 0, countAllTime: 0, firstDate: nil))
    }

    @Test func historialesEnUnaPasadaIgualQueUnoAUno() {
        let ms = [
            pay(1_000, "Mercadona", date(9, 3)), pay(1_250, "MERCADONA Torrejón S.A.", nov(2)), pay(750, "Mercadona", nov(10)),
            pay(300, "Zara", nov(11)), pay(900, "Mercadona", nov(12), flagged: true), pay(100, "Mercadona", nov(25)),
            pay(500, nil, nov(3)), income(5_000, "Mercadona", nov(4)), pay(450, "Zara", date(10, 30)),
        ]
        let all = merchantHistories(in: ms, now: nov(19), calendar: cal)
        #expect(Set(all.keys) == ["mercadona", "mercadona torrejon", "zara"])
        for key in all.keys {
            #expect(all[key] == merchantHistory(for: key, in: ms, now: nov(19), calendar: cal))
        }
        #expect(all["nada"] == nil)
    }

    @Test func busquedaSinTildesNiMayusculas() {
        var withNote = pay(1_250, "Mercadona", nov(1))
        withNote.note = "Café con María"
        let ms = [withNote, pay(1_200, "Panadería López", nov(2), bank: .ima), pay(4_000, "Zara", nov(3), bank: .tr)]
        #expect(searchMovements(ms, query: "panaderia").map(\.merchant) == ["Panadería López"])
        #expect(searchMovements(ms, query: "PANADERÍA").count == 1)
        #expect(searchMovements(ms, query: "revolut").map(\.merchant) == ["Mercadona"])
        #expect(searchMovements(ms, query: "trade").map(\.merchant) == ["Zara"])
        #expect(searchMovements(ms, query: "maria").map(\.merchant) == ["Mercadona"])
        #expect(searchMovements(ms, query: "cafe con").count == 1)
    }

    @Test func busquedaPorImporte() {
        let ms = [pay(1_250, "A", nov(1)), pay(1_200, "B", nov(2)), pay(4_000, "C", nov(3))]
        #expect(searchMovements(ms, query: "12,50").map(\.merchant) == ["A"])
        #expect(searchMovements(ms, query: "12.50").map(\.merchant) == ["A"])
        #expect(searchMovements(ms, query: "12,5").map(\.merchant) == ["A"])
        #expect(searchMovements(ms, query: "12").map(\.merchant) == ["A", "B"])
        #expect(searchMovements(ms, query: "40").map(\.merchant) == ["C"])
        #expect(searchMovements(ms, query: "13").isEmpty)
    }

    @Test func busquedaVaciaDevuelveTodoEnOrden() {
        let ms = [pay(1, "Z", nov(1)), pay(2, "A", nov(2))]
        #expect(searchMovements(ms, query: "").map(\.merchant) == ["Z", "A"])
        #expect(searchMovements(ms, query: "  \n ").map(\.merchant) == ["Z", "A"])
    }
}

@Suite struct MutationTests {
    @Test func notaSeRecortaYVacioLaBorra() {
        let m = pay(100, "A", nov(1))
        var l = Ledger(state: ledger([m]))
        l.setNote("  hola \n", for: m.id)
        #expect(l.state.movements[0].note == "hola")
        l.setNote("   ", for: m.id)
        #expect(l.state.movements[0].note == nil)
        l.setNote("x", for: m.id)
        l.setNote(nil, for: m.id)
        #expect(l.state.movements[0].note == nil)
        l.setNote("x", for: UUID())
        #expect(l.state.movements[0].note == nil)
    }

    @Test func marcarNoEsMio() {
        let m = pay(100, "A", nov(1))
        var l = Ledger(state: ledger([m]))
        l.setFlaggedNotMine(true, for: m.id)
        #expect(l.state.movements[0].flaggedNotMine)
        l.setFlaggedNotMine(false, for: m.id)
        #expect(!l.state.movements[0].flaggedNotMine)
    }

    @Test func silenciarUsaLaClaveNormalizada() {
        var l = Ledger()
        l.setMuted(true, merchant: "MERCADONA Torrejón, S.A.")
        #expect(l.state.mutedMerchants == ["mercadona torrejon"])
        #expect(l.isMuted(merchant: "Mercadona Torrejón"))
        #expect(!l.isMuted(merchant: "Zara"))
        #expect(!l.isMuted(merchant: nil))
        l.setMuted(false, merchant: "mercadona torrejon")
        #expect(l.state.mutedMerchants.isEmpty)
        l.setMuted(true, merchant: "  ")
        #expect(l.state.mutedMerchants.isEmpty)
    }

    @Test func ajustesYBorrado() {
        let a = pay(100, "A", nov(1)), b = pay(200, "B", nov(2))
        var l = Ledger(state: ledger([a, b]))
        l.updateAlertSettings { $0.lowBalance = false; $0.largePaymentThresholdCents = 500 }
        #expect(!l.state.alertSettings.lowBalance)
        #expect(l.state.alertSettings.largePaymentThresholdCents == 500)
        l.deleteMovement(id: a.id)
        #expect(l.state.movements.map(\.id) == [b.id])
    }

    @Test func librosAntiguosSeLeen() throws {
        let old = """
        {"balances":["rev",{"cents":1000,"setAt":800000000,"fromBank":true}],
         "movements":[{"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","bank":"rev","amountCents":-1250,"merchant":"Mercadona",
         "kind":"payment","source":"notification","date":800000100}],"unread":[]}
        """
        let state = try JSONDecoder().decode(LedgerState.self, from: Data(old.utf8))
        #expect(state.movements.count == 1)
        #expect(state.movements[0].note == nil)
        #expect(!state.movements[0].flaggedNotMine)
        #expect(state.alertSettings == AlertSettings())
        #expect(state.mutedMerchants.isEmpty)
        #expect(state.balances[.rev]?.cents == 1000)
    }

    @Test func ajustesParcialesCaenAlValorPorDefecto() throws {
        let s = try JSONDecoder().decode(AlertSettings.self, from: Data(#"{"lowBalance":false,"largePaymentThresholdCents":99}"#.utf8))
        #expect(!s.lowBalance)
        #expect(s.largePaymentThresholdCents == 99)
        #expect(s.everyMovement && s.income && s.subscriptions && s.duplicateCharge && s.weeklyDigest && s.spendingPace)
        #expect(s.lowBalanceThresholdCents == 10_000)
        #expect(try JSONDecoder().decode(AlertSettings.self, from: Data("{}".utf8)) == AlertSettings())
    }

    @Test func idaYVueltaConCamposNuevos() throws {
        var m = pay(100, "A", nov(1))
        m.note = "nota"
        m.flaggedNotMine = true
        let state = LedgerState(movements: [m], alertSettings: AlertSettings(lowBalance: false), mutedMerchants: ["a"])
        let again = try JSONDecoder().decode(LedgerState.self, from: JSONEncoder().encode(state))
        #expect(again == state)
    }
}

@Suite struct ImmediateAlertTests {
    private func alerts(_ movements: [Movement], settings: AlertSettings = AlertSettings(), muted: Set<String> = [],
                        balances: [BankID: ManualBalance] = [:], for m: Movement? = nil, now: Date? = nil) -> [Insight] {
        let last = m ?? movements.last!
        return immediateAlerts(afterStoring: last, in: ledger(movements, settings: settings, muted: muted, balances: balances),
                               now: now ?? last.date, calendar: cal)
    }

    // Saldo bajo

    private let base = [BankID.rev: ManualBalance(cents: 10_500, setAt: nov(1), fromBank: true)]

    @Test func saldoBajoAlCruzarElUmbral() {
        let out = alerts([pay(1_000, "Mercadona", nov(19))], balances: base)
        #expect(kinds(out) == [.lowBalance])
        #expect(out[0].title == "Saldo bajo en Revolut")
        #expect(out[0].detail == "Te quedan 95,00\u{00A0}€")
        #expect(out[0].severity == .warning)
        #expect(out[0].bank == .rev)
    }

    @Test func saldoBajoSoloUnaVez() {
        let ms = [pay(1_000, "Mercadona", nov(19)), pay(500, "Zara", nov(19, 13))]
        #expect(alerts(ms, balances: base).isEmpty)                      // ya estaba por debajo
        #expect(kinds(alerts(ms, balances: base, for: ms[0])) == [.lowBalance])
    }

    @Test func saldoBajoLimites() {
        // Queda exactamente en el umbral: no es "por debajo".
        #expect(alerts([pay(500, "Mercadona", nov(19))], balances: base).isEmpty)
        // Un céntimo menos: sí.
        #expect(kinds(alerts([pay(501, "Mercadona", nov(19))], balances: base)) == [.lowBalance])
        // Sin saldo conocido o con un ingreso: no.
        #expect(alerts([pay(1_000, "Mercadona", nov(19))]).isEmpty)
        #expect(alerts([income(1_000, "Bizum de Ana", nov(19))], balances: base).isEmpty)
    }

    @Test func saldoBajoApagadoOSilenciado() {
        let ms = [pay(1_000, "Mercadona", nov(19))]
        #expect(alerts(ms, settings: AlertSettings(lowBalance: false), balances: base).isEmpty)
        #expect(alerts(ms, settings: AlertSettings(lowBalanceThresholdCents: 5_000), balances: base).isEmpty)
    }

    @Test func saldoBajoAunqueElComercioEsteSilenciado() {
        // El saldo ha bajado de verdad: se avisa aunque Mercadona esté silenciado (y solo eso).
        let ms = [pay(32_000, "Mercadona", nov(19))]
        let rich = [BankID.rev: ManualBalance(cents: 41_000, setAt: nov(1), fromBank: true)]
        #expect(kinds(alerts(ms, muted: ["mercadona"], balances: rich)) == [.lowBalance])
        #expect(kinds(alerts(ms, balances: rich)) == [.lowBalance, .largePayment])
    }

    // Pago grande

    @Test func pagoGrande() {
        let out = alerts([pay(32_000, "MediaMarkt", nov(19))])
        #expect(kinds(out) == [.largePayment])
        #expect(out[0].title == "Pago grande: 320,00\u{00A0}€ en MediaMarkt")
        #expect(out[0].severity == .warning)
        #expect(out[0].merchant == "MediaMarkt")
        #expect(alerts([pay(32_000, nil, nov(19))])[0].title == "Pago grande: 320,00\u{00A0}€")
    }

    @Test func pagoGrandeLimites() {
        #expect(alerts([pay(14_999, "A", nov(19))]).isEmpty)
        #expect(kinds(alerts([pay(15_000, "A", nov(19))])) == [.largePayment])
        #expect(alerts([pay(15_000, "A", nov(19))], settings: AlertSettings(largePaymentThresholdCents: 15_001)).isEmpty)
        #expect(alerts([income(32_000, "Bizum de Ana", nov(19))]).isEmpty)
    }

    @Test func pagoGrandeApagadoSilenciadoOMarcado() {
        let ms = [pay(32_000, "MediaMarkt", nov(19))]
        #expect(alerts(ms, settings: AlertSettings(largePayment: false)).isEmpty)
        #expect(alerts(ms, muted: ["mediamarkt"]).isEmpty)
        #expect(alerts([pay(32_000, "MediaMarkt", nov(19), flagged: true)]).isEmpty)
    }

    // Pago poco habitual

    private let zara = [pay(3_000, "Zara", nov(1)), pay(4_000, "Zara", nov(5)), pay(5_000, "Zara", nov(9))]

    @Test func pagoPocoHabitual() {
        let out = alerts(zara + [pay(12_000, "Zara", nov(19))])
        #expect(kinds(out) == [.unusualPayment])
        #expect(out[0].title == "Pago poco habitual en Zara: 120,00\u{00A0}€")
        #expect(out[0].detail == "Sueles gastar unos 40,00\u{00A0}€")
        #expect(out[0].severity == .info)
    }

    @Test func pagoPocoHabitualLimites() {
        #expect(alerts(zara + [pay(11_999, "Zara", nov(19))]).isEmpty)
        #expect(alerts(Array(zara.suffix(2)) + [pay(12_000, "Zara", nov(19))]).isEmpty)        // solo 2 previos
        #expect(alerts(zara + [pay(20_000, "Zara", nov(19))]).map(\.kind) == [.largePayment]) // grande: no "poco habitual"
        #expect(alerts(zara + [pay(12_000, "Zara", nov(19))], settings: AlertSettings(largePayment: false)).isEmpty)
        #expect(alerts(zara + [pay(12_000, "Zara", nov(19))], muted: ["zara"]).isEmpty)
        var flaggedPrev = zara
        flaggedPrev[0].flaggedNotMine = true
        #expect(alerts(flaggedPrev + [pay(12_000, "Zara", nov(19))]).isEmpty)
    }

    // Nómina

    @Test func nomina() {
        let out = alerts([income(145_000, "Nómina Empresa SL", nov(19))])
        #expect(kinds(out) == [.salary])
        #expect(out[0].title == "Has recibido tu nómina: 1.450,00\u{00A0}€")
        #expect(out[0].severity == .positive)
        #expect(kinds(alerts([income(50_000, "NOMINA", nov(19))])) == [.salary])
    }

    @Test func ingresoGrande() {
        let out = alerts([income(90_000, "Laura", nov(19))])
        #expect(kinds(out) == [.largeIncome])
        #expect(out[0].title == "Ingreso grande: 900,00\u{00A0}€ de Laura")
        #expect(out[0].severity == .positive)
        #expect(out[0].movementID != nil)
        #expect(kinds(alerts([income(80_000, "Transferencia", nov(19))])) == [.largeIncome])
        let anonymous = alerts([income(80_000, nil, nov(19))])
        #expect(anonymous.map(\.title) == ["Ingreso grande: 800,00\u{00A0}€"])
        // Una nómina que no llega a 500 € no es nómina ni ingreso grande.
        #expect(alerts([income(49_999, "Nómina", nov(19))]).isEmpty)
        // Una nómina enorme sigue siendo nómina.
        #expect(kinds(alerts([income(250_000, "Nomina Empresa", nov(19))])) == [.salary])
        #expect(alerts([income(90_000, "Laura", nov(19))], settings: AlertSettings(income: false)).isEmpty)
        #expect(alerts([income(90_000, "Laura", nov(19))], muted: ["laura"]).isEmpty)
    }

    @Test func nominaLimites() {
        #expect(alerts([income(49_999, "Nómina Empresa", nov(19))]).isEmpty)
        #expect(alerts([income(79_999, "Transferencia", nov(19))]).isEmpty)
        #expect(alerts([income(3_500, "Bizum de Carlos", nov(19))]).isEmpty)
    }

    @Test func nominaApagadaOSilenciada() {
        let ms = [income(145_000, "Nómina Empresa SL", nov(19))]
        #expect(alerts(ms, settings: AlertSettings(income: false)).isEmpty)
        #expect(alerts(ms, muted: ["nomina empresa"]).isEmpty)
    }

    // Cobro duplicado

    @Test func cobroDuplicado() {
        let ms = [pay(1_250, "Mercadona", nov(19, 12, 0)), pay(1_250, "Mercadona", nov(19, 12, 10))]
        let out = alerts(ms)
        #expect(kinds(out) == [.duplicateCharge])
        #expect(out[0].title == "Posible cobro duplicado: 12,50\u{00A0}€ en Mercadona")
        #expect(out[0].detail == "Dos cargos iguales en pocos minutos")
        #expect(alerts(ms, for: ms[0]).isEmpty)
    }

    @Test func cobroDuplicadoMismaHoraUnSoloAviso() {
        let ms = [pay(1_250, "Mercadona", nov(19, 12, 0)), pay(1_250, "Mercadona", nov(19, 12, 0))]
        let both = alerts(ms, for: ms[0]) + alerts(ms, for: ms[1])
        #expect(kinds(both) == [.duplicateCharge])
        let feedOut = insights(for: ledger(ms), now: nov(19, 13), calendar: cal).filter { $0.kind == .duplicateCharge }
        #expect(feedOut.count == 1)
    }

    @Test func cobroDuplicadoLimites() {
        #expect(kinds(alerts([pay(1_250, "Mercadona", nov(19, 12, 0)), pay(1_250, "Mercadona", nov(19, 12, 15))])) == [.duplicateCharge])
        #expect(alerts([pay(1_250, "Mercadona", nov(19, 12, 0)), pay(1_250, "Mercadona", nov(19, 12, 16))]).isEmpty)
        #expect(alerts([pay(1_250, "Mercadona", nov(19, 12, 0)), pay(1_251, "Mercadona", nov(19, 12, 5))]).isEmpty)
        #expect(alerts([pay(1_250, "Mercadona", nov(19, 12, 0), bank: .ima), pay(1_250, "Mercadona", nov(19, 12, 5))]).isEmpty)
        #expect(alerts([pay(1_250, "Mercadona", nov(19, 12, 0)), pay(1_250, "Zara", nov(19, 12, 5))]).isEmpty)
        #expect(alerts([pay(1_250, "Mercadona", nov(19, 12, 0), flagged: true), pay(1_250, "Mercadona", nov(19, 12, 5))]).isEmpty)
    }

    @Test func cobroDuplicadoApagadoOSilenciado() {
        let ms = [pay(1_250, "Mercadona", nov(19, 12, 0)), pay(1_250, "Mercadona", nov(19, 12, 10))]
        #expect(alerts(ms, settings: AlertSettings(duplicateCharge: false)).isEmpty)
        #expect(alerts(ms, muted: ["mercadona"]).isEmpty)
    }

    // Cambio de precio

    @Test func cambioDePrecio() {
        let up = [pay(1_099, "Spotify", date(10, 19)), pay(1_199, "Spotify", nov(19))]
        let out = alerts(up)
        #expect(kinds(out) == [.subscriptionPriceChange])
        #expect(out[0].title == "Spotify ha subido 1,00\u{00A0}€")
        #expect(out[0].detail == "Ahora 11,99\u{00A0}€ al mes")
        let down = [pay(1_199, "Spotify", date(10, 19)), pay(1_099, "Spotify", nov(19))]
        #expect(alerts(down)[0].title == "Spotify ha bajado 1,00\u{00A0}€")
        #expect(alerts(down)[0].detail == "Ahora 10,99\u{00A0}€ al mes")
    }

    @Test func cambioDePrecioLimites() {
        #expect(alerts([pay(1_099, "Spotify", date(10, 19)), pay(1_099, "Spotify", nov(19))]).isEmpty)       // mismo precio
        let pair = [pay(1_099, "Spotify", date(10, 19)), pay(1_199, "Spotify", nov(19))]
        #expect(alerts(pair, for: pair[0]).isEmpty)                                                              // no es el último cargo
        let up = [pay(1_099, "Spotify", date(10, 19)), pay(1_199, "Spotify", nov(19))]
        #expect(alerts(up, settings: AlertSettings(subscriptions: false)).isEmpty)
        #expect(alerts(up, muted: ["spotify"]).isEmpty)
    }
}

@Suite struct FeedTests {
    private func feed(_ movements: [Movement], now: Date, settings: AlertSettings = AlertSettings(), muted: Set<String> = [],
                      balances: [BankID: ManualBalance] = [:]) -> [Insight] {
        insights(for: ledger(movements, settings: settings, muted: muted, balances: balances), now: now, calendar: cal)
    }

    private func only(_ kind: InsightKind, _ list: [Insight]) -> [Insight] { list.filter { $0.kind == kind } }

    // Saldo bajo

    @Test func saldoBajoMientrasEsteDebajo() {
        let low = [BankID.rev: ManualBalance(cents: 9_000, setAt: nov(1), fromBank: true)]
        let out = only(.lowBalance, feed([], now: nov(19), balances: low))
        #expect(out.count == 1)
        #expect(out[0].title == "Saldo bajo en Revolut")
        #expect(out[0].detail == "Te quedan 90,00\u{00A0}€")
        let exact = [BankID.rev: ManualBalance(cents: 10_000, setAt: nov(1), fromBank: true)]
        #expect(only(.lowBalance, feed([], now: nov(19), balances: exact)).isEmpty)
        #expect(only(.lowBalance, feed([], now: nov(19), settings: AlertSettings(lowBalance: false), balances: low)).isEmpty)
    }

    // Pago grande y compañia en el feed

    @Test func eventosRecientesEntranEnElFeed() {
        let ms = [pay(32_000, "MediaMarkt", nov(17)), pay(32_000, "Antigua", nov(1)), income(145_000, "Nómina X", nov(18))]
        let out = feed(ms, now: nov(19))
        #expect(only(.largePayment, out).map(\.merchant) == ["MediaMarkt"])
        #expect(only(.salary, out).count == 1)
        #expect(feed(ms, now: nov(19), muted: ["mediamarkt", "nomina x"]).isEmpty)
        #expect(feed(ms, now: nov(19), settings: AlertSettings(largePayment: false, income: false)).isEmpty)
    }

    // Suscripciones proximas

    private let netflix = [pay(1_399, "Netflix", date(9, 22)), pay(1_399, "Netflix", date(10, 22))]

    @Test func suscripcionProxima() {
        let out = only(.subscriptionUpcoming, feed(netflix, now: nov(19)))
        #expect(out.count == 1)
        #expect(out[0].title == "Netflix se cobra el domingo: 13,99\u{00A0}€")
        #expect(out[0].severity == .info)
        #expect(only(.subscriptionUpcoming, feed(netflix, now: nov(22)))[0].title == "Netflix se cobra hoy: 13,99\u{00A0}€")
        #expect(only(.subscriptionUpcoming, feed(netflix, now: nov(21)))[0].title == "Netflix se cobra mañana: 13,99\u{00A0}€")
    }

    @Test func suscripcionProximaLimites() {
        #expect(only(.subscriptionUpcoming, feed(netflix, now: nov(14))).isEmpty)       // faltan 8 días
        #expect(only(.subscriptionUpcoming, feed(netflix, now: nov(15))).count == 1)    // faltan 7
        #expect(only(.subscriptionUpcoming, feed(netflix, now: nov(23))).isEmpty)       // ayer: ya no es próximo
        #expect(only(.subscriptionUpcoming, feed(netflix, now: nov(24))).isEmpty)       // hace 2 días
        #expect(only(.subscriptionUpcoming, feed(netflix, now: nov(19), settings: AlertSettings(subscriptions: false))).isEmpty)
        #expect(only(.subscriptionUpcoming, feed(netflix, now: nov(19), muted: ["netflix"])).isEmpty)
    }

    @Test func suscripcionEnDosBancosNoChoca() {
        let both = netflix + [pay(1_399, "Netflix", date(9, 22), bank: .ima), pay(1_399, "Netflix", date(10, 22), bank: .ima)]
        let out = only(.subscriptionUpcoming, feed(both, now: nov(19)))
        #expect(out.count == 2)
        #expect(Set(out.map(\.id)).count == 2)
        #expect(Set(out.compactMap(\.bank)) == [.rev, .ima])
    }

    // Ritmo de gasto

    private func paceMovements(thisMonth: Int) -> [Movement] {
        [pay(5_000, nil, date(10, 2)), pay(thisMonth, nil, nov(18))]
    }

    @Test func ritmoPorDebajo() {
        let out = only(.spendingPace, feed(paceMovements(thisMonth: 4_000), now: nov(19)))
        #expect(out.count == 1)
        #expect(out[0].title == "Vas 10,00\u{00A0}€ por debajo del mes pasado")
        #expect(out[0].detail == "Llevas 40,00\u{00A0}€ este mes")
        #expect(out[0].severity == .positive)
    }

    @Test func ritmoPorEncima() {
        let out = only(.spendingPace, feed(paceMovements(thisMonth: 9_000), now: nov(19)))
        #expect(out[0].title == "Vas 40,00\u{00A0}€ por encima del mes pasado")
        #expect(out[0].severity == .info)
    }

    @Test func ritmoLimites() {
        #expect(only(.spendingPace, feed(paceMovements(thisMonth: 4_001), now: nov(19))).isEmpty)   // diferencia 999
        #expect(only(.spendingPace, feed(paceMovements(thisMonth: 6_000), now: nov(19))).count == 1) // diferencia 1000
        #expect(only(.spendingPace, feed([pay(5_000, nil, date(10, 2)), pay(100, nil, nov(2))], now: nov(5))).isEmpty) // día 5
        #expect(only(.spendingPace, feed([pay(5_000, nil, date(10, 2)), pay(100, nil, nov(2))], now: nov(6))).count == 1)
        #expect(only(.spendingPace, feed(paceMovements(thisMonth: 4_000), now: nov(19), settings: AlertSettings(spendingPace: false))).isEmpty)
        #expect(only(.spendingPace, feed([pay(9_000, nil, nov(18))], now: nov(19))).isEmpty)          // sin mes anterior
    }

    // Resumen semanal

    private let week = [pay(7_994, nil, nov(17)), pay(5_000, nil, nov(19)), pay(14_194, nil, nov(10))]

    @Test func resumenSemanalDomingo() {
        let out = only(.weeklyDigest, feed(week, now: nov(22)))
        #expect(out.count == 1)
        #expect(out[0].title == "Esta semana has gastado 129,94\u{00A0}€")
        #expect(out[0].detail == "12,00\u{00A0}€ menos que la anterior")
    }

    @Test func resumenSemanalLunesResumeLaSemanaPasada() {
        let out = only(.weeklyDigest, feed(week, now: nov(23)))
        #expect(out[0].title == "Esta semana has gastado 129,94\u{00A0}€")
    }

    @Test func resumenSemanalOtrosDiasYApagado() {
        #expect(only(.weeklyDigest, feed(week, now: nov(24))).isEmpty)
        #expect(only(.weeklyDigest, feed(week, now: nov(21))).isEmpty)
        #expect(only(.weeklyDigest, feed(week, now: nov(22), settings: AlertSettings(weeklyDigest: false))).isEmpty)
        #expect(only(.weeklyDigest, feed([], now: nov(22))).isEmpty)
    }

    @Test func textoDelResumenSemanal() {
        func text(previous: Int) -> (title: String, body: String) {
            let ms = [pay(12_994, nil, nov(18)), pay(previous, nil, nov(10))]
            return weeklyDigestText(for: ledger(ms), weekContaining: nov(18), calendar: cal)
        }
        #expect(text(previous: 14_194).body == "12,00\u{00A0}€ menos que la anterior")
        #expect(text(previous: 11_994).body == "10,00\u{00A0}€ más que la anterior")
        #expect(text(previous: 12_994).body == "Igual que la anterior")
        #expect(text(previous: 12_994).title == "Esta semana has gastado 129,94\u{00A0}€")
    }

    // Identificadores y limite

    @Test func idsEstablesYUnicos() {
        let ms = (0..<20).map { pay(20_000 + $0, "Tienda \($0)", nov(18, 8, $0)) }
        let a = feed(ms, now: nov(19))
        let b = feed(ms, now: nov(19, 15))
        #expect(a.map(\.id) == b.map(\.id))
        #expect(Set(a.map(\.id)).count == a.count)
        #expect(a.allSatisfy { $0.id.hasPrefix("largePayment|") && $0.id.hasSuffix("|2026-11-18") })
    }

    @Test func maximoDoceAvisos() {
        let ms = (0..<20).map { pay(20_000 + $0, "Tienda \($0)", nov(18, 8, $0)) }
        let out = feed(ms, now: nov(19))
        #expect(out.count == 12)
        #expect(out.first?.merchant == "Tienda 19")   // lo más reciente primero
    }
}
