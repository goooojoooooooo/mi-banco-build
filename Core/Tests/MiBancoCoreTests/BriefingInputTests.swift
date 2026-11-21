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

private func mv(_ bank: BankID, _ cents: Int, _ merchant: String?, at when: Date, shop: Bool = false, flagged: Bool = false,
                category: SpendingCategory? = nil) -> Movement {
    Movement(bank: bank, amountCents: cents, merchant: merchant, kind: cents < 0 ? .payment : .income, source: .notification,
             date: when, isShop: shop, flaggedNotMine: flagged, category: category)
}

private func link(validUntil: Date, problem: SyncProblem? = nil, lastSuccess: Date? = nil) -> BankLinkInfo {
    var l = BankLinkInfo(connectedAt: nov(1), consentValidUntil: validUntil)
    l.problem = problem
    l.lastSuccessAt = lastSuccess
    return l
}

private func input(_ state: LedgerState, since: Date = nov(19, 22, 10), now: Date = nov(20, 8, 30), book: AccountBook = AccountBook(),
                   portfolio: Portfolio? = nil) -> BriefingInput {
    briefingInput(state: state, portfolio: portfolio, book: book, record: BriefingRecord(shownAt: now, since: since), isFirst: false,
                  now: now, calendar: cal)
}

private func subscription(_ bank: BankID, _ name: String, _ cents: Int, _ first: Date, _ second: Date) -> [Movement] {
    [mv(bank, -cents, name, at: first, shop: true), mv(bank, -cents, name, at: second, shop: true)]
}

@Suite struct BriefingInputTests {
    // MARK: Horario

    @Test func primeraVez() {
        let record = BriefingSchedule.due(previous: nil, now: nov(20, 8, 30), calendar: cal)
        #expect(record == BriefingRecord(shownAt: nov(20, 8, 30), since: nov(19, 8, 30)))
        #expect(BriefingSchedule.dayStartHour == 5)
    }

    @Test func unaVezAlDia() {
        let previous = BriefingRecord(shownAt: nov(20, 8, 30), since: nov(19, 8, 30))
        #expect(BriefingSchedule.due(previous: previous, now: nov(20, 23), calendar: cal) == nil)
        #expect(BriefingSchedule.due(previous: previous, now: nov(21, 5), calendar: cal)
            == BriefingRecord(shownAt: nov(21, 5), since: nov(20, 8, 30)))
    }

    @Test func limiteDeLas5() {
        let previous = BriefingRecord(shownAt: nov(19, 10), since: nov(18, 10))
        #expect(BriefingSchedule.due(previous: previous, now: nov(20, 4, 59), calendar: cal) == nil)
        #expect(BriefingSchedule.due(previous: previous, now: nov(20, 5, 0), calendar: cal)
            == BriefingRecord(shownAt: nov(20, 5, 0), since: nov(19, 10)))
        // Segunda apertura del mismo día.
        let today = BriefingRecord(shownAt: nov(20, 5, 0), since: nov(19, 10))
        #expect(BriefingSchedule.due(previous: today, now: nov(20, 5, 1), calendar: cal) == nil)
        #expect(BriefingSchedule.due(previous: today, now: nov(21, 4, 59), calendar: cal) == nil)
    }

    @Test func madrugadaCuentaComoAyer() {
        let evening = BriefingRecord(shownAt: nov(20, 8, 30), since: nov(19, 8, 30))
        #expect(BriefingSchedule.due(previous: evening, now: nov(21, 1, 30), calendar: cal) == nil)
        let night = BriefingRecord(shownAt: nov(20, 1, 30), since: nov(19, 8, 30))
        #expect(BriefingSchedule.due(previous: night, now: nov(20, 8), calendar: cal) == BriefingRecord(shownAt: nov(20, 8), since: nov(20, 1, 30)))
        // Dos aperturas de madrugada del mismo "día": solo la primera.
        #expect(BriefingSchedule.due(previous: night, now: nov(20, 4, 59), calendar: cal) == nil)
    }

    @Test func semanaComoMucho() {
        let previous = BriefingRecord(shownAt: nov(12, 9), since: nov(11, 9))
        let record = BriefingSchedule.due(previous: previous, now: nov(20, 8, 30), calendar: cal)
        #expect(record?.since == nov(13, 8, 30))
        #expect(record?.shownAt == nov(20, 8, 30))
        // Seis días: no se recorta.
        let recent = BriefingRecord(shownAt: nov(14, 9), since: nov(13, 9))
        #expect(BriefingSchedule.due(previous: recent, now: nov(20, 8, 30), calendar: cal)?.since == nov(14, 9))
    }

    @Test func manual() {
        let today = BriefingRecord(shownAt: nov(20, 6), since: nov(19, 8))
        #expect(BriefingSchedule.manual(previous: today, now: nov(20, 15), calendar: cal) == BriefingRecord(shownAt: nov(20, 15), since: today.since))
        let yesterday = BriefingRecord(shownAt: nov(19, 8), since: nov(18, 8))
        #expect(BriefingSchedule.manual(previous: yesterday, now: nov(20, 15), calendar: cal)
            == BriefingSchedule.due(previous: yesterday, now: nov(20, 15), calendar: cal))
        #expect(BriefingSchedule.manual(previous: nil, now: nov(20, 15), calendar: cal)
            == BriefingSchedule.due(previous: nil, now: nov(20, 15), calendar: cal))
    }

    @Test func cambiosDeHora() {
        // Primavera: el domingo 29 de marzo de 2026 la 02:00 salta a las 03:00.
        let before = BriefingRecord(shownAt: date(3, 28, 9), since: date(3, 27, 9))
        #expect(BriefingSchedule.due(previous: before, now: date(3, 29, 4, 59), calendar: cal) == nil)
        #expect(BriefingSchedule.due(previous: before, now: date(3, 29, 5, 0), calendar: cal)
            == BriefingRecord(shownAt: date(3, 29, 5, 0), since: date(3, 28, 9)))
        let sunday = BriefingRecord(shownAt: date(3, 29, 8), since: date(3, 28, 9))
        #expect(BriefingSchedule.due(previous: sunday, now: date(3, 29, 23, 59), calendar: cal) == nil)
        #expect(BriefingSchedule.due(previous: sunday, now: date(3, 30, 5, 0), calendar: cal)
            == BriefingRecord(shownAt: date(3, 30, 5, 0), since: date(3, 29, 8)))
        // Otoño: el domingo 25 de octubre de 2026 la hora 02:00 se repite.
        let night = BriefingRecord(shownAt: date(10, 24, 23, 30), since: date(10, 24, 8))
        #expect(BriefingSchedule.due(previous: night, now: date(10, 25, 4, 59), calendar: cal) == nil)
        #expect(BriefingSchedule.due(previous: night, now: date(10, 25, 5, 0), calendar: cal)
            == BriefingRecord(shownAt: date(10, 25, 5, 0), since: date(10, 24, 23, 30)))
        let autumn = BriefingRecord(shownAt: date(10, 25, 5, 0), since: date(10, 24, 23, 30))
        #expect(BriefingSchedule.due(previous: autumn, now: date(10, 25, 18), calendar: cal) == nil)
        #expect(BriefingSchedule.due(previous: autumn, now: date(10, 26, 5, 0), calendar: cal)?.since == date(10, 25, 5, 0))
    }

    @Test func elDesdeEmpalmaSinHuecosNiSolapes() {
        var record = BriefingSchedule.due(previous: nil, now: nov(18, 9), calendar: cal)!
        var seen: [BriefingRecord] = [record]
        for day in 19...22 {
            let next = BriefingSchedule.due(previous: record, now: nov(day, 7, 30), calendar: cal)!
            #expect(next.since == record.shownAt)
            seen.append(next)
            record = next
        }
        #expect(seen.count == 5)
    }

    // MARK: Lo que ha pasado

    private func busyState() -> LedgerState {
        var state = LedgerState()
        state.movements = [
            mv(.rev, -800, "Café", at: nov(19, 21)),
            mv(.rev, -1250, "Mercadona", at: nov(19, 22, 40), shop: true),
            mv(.rev, -4995, "Zara", at: nov(19, 23, 5), shop: true),
            mv(.ima, 185_000, "Nómina ACME", at: nov(20, 6, 5)),
            mv(.ima, -20_000, "Transferencia a Revolut", at: nov(20, 7, 49)),
            mv(.rev, 20_000, "Transferencia de imagin", at: nov(20, 7, 50)),
            mv(.rev, -300, "Cobro raro", at: nov(20, 8), flagged: true),
        ] + subscription(.rev, "Spotify", 1099, date(9, 22), date(10, 22))
        state.balances[.rev] = ManualBalance(cents: 34_020, setAt: nov(20, 8, 20), origin: .manual)
        return state
    }

    @Test func recogeLoQueHaPasado() {
        let i = input(busyState())
        #expect(i.income.map(\.name) == ["Nómina ACME"])
        #expect(i.income[0].cents == 185_000)
        #expect(i.payments.map(\.name) == ["Zara", "Mercadona"])
        #expect(i.payments.map(\.cents) == [4995, 1250])
        #expect(i.transfers == [TransferDigest(from: .ima, to: .rev, cents: 20_000)])
        #expect(i.banks == [BankLine(bank: .rev, cents: 34_020, estimated: true, changeCents: 13_755),
                            BankLine(bank: .ima, cents: nil, estimated: false, changeCents: 165_000)])
        // imagin no tiene saldo conocido: su cambio no entra en el total.
        #expect(i.totalChangeCents == 13_755)
        #expect(i.totalCents == 34_020)
        #expect(i.upcoming.first == UpcomingCharge(name: "Spotify", bank: .rev, cents: 1099, date: nov(22, 12)))
        #expect(i.since == nov(19, 22, 10))
        #expect(i.now == nov(20, 8, 30))
        #expect(!i.isFirst)
    }

    @Test func elPeriodoEsAbiertoPorAbajoYCerradoPorArriba() {
        var state = LedgerState()
        state.movements = [mv(.rev, -500, "Justo en el límite", at: nov(19, 22, 10), shop: true),
                           mv(.rev, -700, "Justo después", at: nov(19, 22, 10).addingTimeInterval(1), shop: true),
                           mv(.rev, -900, "Justo ahora", at: nov(20, 8, 30), shop: true),
                           mv(.rev, -1100, "Futuro", at: nov(20, 8, 30).addingTimeInterval(1), shop: true)]
        #expect(input(state).payments.map(\.name) == ["Justo ahora", "Justo después"])
    }

    // MARK: J3 — el periodo es cuándo se enteró la app

    private func imported(_ bank: BankID, _ cents: Int, _ name: String, date: Date, at importedAt: Date) -> Movement {
        Movement(bank: bank, amountCents: cents, merchant: name, kind: cents < 0 ? .payment : .income, source: .bank, date: date,
                 isShop: true, bankRef: "ref-\(name)", bankStatus: .booked, importedAt: importedAt)
    }

    @Test func unMovimientoImportadoTardeSaleEnUnSoloResumen() {
        var state = LedgerState()
        // Fechado antes del «desde» del resumen de hoy, pero la app lo supo esta mañana.
        state.movements = [imported(.rev, -2_000, "Cena", date: nov(19, 20), at: nov(20, 7))]
        let previous = input(state, since: nov(18, 22, 10), now: nov(19, 22, 10))
        let today = input(state, since: nov(19, 22, 10), now: nov(20, 8, 30))
        #expect(previous.payments.isEmpty)
        #expect(today.payments.map(\.name) == ["Cena"])
        #expect(today.banks.first?.changeCents == -2_000)
        // Y no se repite al día siguiente.
        #expect(input(state, since: nov(20, 8, 30), now: nov(21, 8, 30)).payments.isEmpty)
    }

    @Test func fechadoHoyAlMediodiaEImportadoEstaManianaSaleHoy() {
        var state = LedgerState()
        state.movements = [imported(.rev, -2_000, "Comida", date: nov(20, 12), at: nov(20, 8)),
                           imported(.rev, 90_000, "Nomina", date: nov(20, 12), at: nov(20, 8))]
        let i = input(state, since: nov(20, 6), now: nov(20, 13))
        #expect(i.payments.map(\.name) == ["Comida"])
        #expect(i.income.map(\.name) == ["Nomina"])
        #expect(i.banks.first?.changeCents == 88_000)
        // Una importación del futuro no cuenta todavía.
        #expect(input(state, since: nov(20, 6), now: nov(20, 7)).payments.isEmpty)
    }

    // MARK: J14 — el historial importado no inunda el resumen

    @Test func unaImportacionDeUnAnioSoloAnadeLoDeLosUltimosSieteDias() {
        var state = LedgerState()
        let morning = nov(20, 7)
        // Un extracto de 12 meses importado esta mañana: una fila por semana, más una de hace 30 días y otra de 2 días antes del «desde».
        state.movements = (0..<52).map { week in
            imported(.rev, -1_000 - week, "Hist\(week)", date: nov(20, 7).addingTimeInterval(-Double(week + 5) * 7 * 86_400), at: morning)
        }
        state.movements.append(imported(.rev, 77_700, "Nomina vieja", date: nov(20, 7).addingTimeInterval(-30 * 86_400), at: morning))
        state.movements.append(imported(.rev, -2_222, "Hace dos dias", date: nov(17, 20), at: morning))
        // since = 19 nov 22:10; límite = 12 nov 22:10.
        let i = input(state)
        #expect(i.payments.map(\.name) == ["Hace dos dias"])
        #expect(i.income.isEmpty)
        #expect(i.banks.first?.changeCents == -2_222)
        #expect(render(makeBriefing(i, calendar: cal).headline, .plain) == "Desde ayer a las 22:10 gastaste 22,22\u{00A0}€ en 1 pago.")
        // Justo dentro del límite entra; justo en él, no.
        var edge = LedgerState()
        let limit = nov(19, 22, 10).addingTimeInterval(-7 * 86_400)
        edge.movements = [imported(.rev, -500, "Dentro", date: limit.addingTimeInterval(1), at: morning),
                          imported(.rev, -600, "Limite", date: limit, at: morning)]
        #expect(input(edge).payments.map(\.name) == ["Dentro"])
    }

    // MARK: J4 — el total solo suma bancos con saldo conocido

    @Test func elCambioTotalNoCuentaBancosSinSaldo() {
        let i = input(busyState())
        #expect(i.totalChangeCents == 13_755)
        #expect(i.totalLeftOut == [.ima])
        let text = lines(makeBriefing(i, calendar: cal), .money).first
        #expect(text?.hasSuffix(", sin contar imagin") == true)
    }

    private func lines(_ b: Briefing, _ kind: BriefingSectionKind) -> [String] {
        b.sections.first { $0.kind == kind }?.lines.map { render($0.parts, .plain) } ?? []
    }

    // MARK: J5 — un capturado y su gemelo del banco cuentan una vez

    @Test func capturadoYGemeloDelBancoCuentanUnaVez() {
        var state = LedgerState()
        state.balances[.rev] = ManualBalance(cents: 100_000, setAt: nov(19), origin: .bank)
        let capture = Movement(bank: .rev, amountCents: -5_000, merchant: "Bar", kind: .payment, source: .notification,
                               date: nov(20, 7), isShop: true)
        let row = Movement(bank: .rev, amountCents: -5_200, merchant: "Bar", kind: .payment, source: .bank, date: nov(20, 7, 30),
                           isShop: true, bankRef: "r1", bankStatus: .booked)
        state.movements = [capture, row]
        let i = input(state, since: nov(20, 6), now: nov(20, 9))
        #expect(i.payments.map(\.cents) == [5_200])
        #expect(i.banks.first?.changeCents == -5_200)
        #expect(i.totalChangeCents == -5_200)
        #expect(render(makeBriefing(i, calendar: cal).headline, .plain).contains("en 1 pago"))
    }

    @Test func unIngresoCapturadoSinConfirmarNoEntraDosVeces() {
        var state = LedgerState()
        state.links[.rev] = link(validUntil: date(12, 31), lastSuccess: nov(20, 8))
        // La fila más antigua del banco marca desde cuándo se ve el banco; el aviso de ingreso nunca se confirmó.
        let old = Movement(bank: .rev, amountCents: -100, merchant: "Antiguo", kind: .payment, source: .bank, date: nov(2),
                           bankRef: "old", bankStatus: .booked)
        let capture = mv(.rev, 10_000, "Bizum de un amigo", at: nov(10))
        state.movements = [old, capture]
        #expect(unconfirmedCaptureIDs(in: state, now: nov(20, 8, 30)) == [capture.id])
        let i = input(state, since: nov(8), now: nov(20, 8, 30))
        #expect(i.income.isEmpty)
        #expect(i.banks.first { $0.bank == .rev }?.changeCents == 0)
    }

    // MARK: J12 — un cobro retrasado cuenta hoy

    @Test func unCobroRetrasadoSaleEnLoQueVieneYSeResta() throws {
        var state = LedgerState()
        // Debía cobrarse el 18 y no llegó.
        state.movements = subscription(.rev, "Spotify", 1099, date(9, 18), date(10, 18))
        state.balances[.rev] = ManualBalance(cents: 500, setAt: nov(20, 8), origin: .bank)
        state.balances[.ima] = ManualBalance(cents: 128_455, setAt: nov(20, 8), origin: .bank)
        let i = input(state)
        let charge = try #require(i.upcoming.first)
        #expect(charge.overdue)
        #expect(charge.dueDate == nov(18, 12))
        #expect(charge.date == nov(20, 0))
        // Falta saldo para él (500 < 1099), y el dinero libre ya lo descuenta.
        #expect(i.shortfalls.first?.charge == charge)
        var bare = LedgerState()
        bare.balances = state.balances
        let without = input(bare).freeMoney
        #expect((without?.cents ?? 0) - (i.freeMoney?.cents ?? 0) == 1099)
        let text = lines(makeBriefing(i, calendar: cal), .upcoming)
        #expect(text.first == "Hoy: Spotify, 10,99\u{00A0}€ en Revolut (con retraso, debía cobrarse el 18)")
    }

    // MARK: J13 — detalles del resumen

    @Test func unPagoDeCeroEurosNoCuentaComoPago() {
        var state = LedgerState()
        state.movements = [mv(.rev, 0, "Verificación", at: nov(20, 7), shop: true), mv(.rev, -500, "Café", at: nov(20, 7, 30), shop: true)]
        // mv() pone «ingreso» a lo que no es negativo: se fuerza el tipo de pago.
        state.movements[0] = Movement(bank: .rev, amountCents: 0, merchant: "Verificación", kind: .payment, source: .notification,
                                      date: nov(20, 7), isShop: true)
        #expect(input(state).payments.map(\.name) == ["Café"])
    }

    @Test func unaConexionCaducadaConConsentimientoFuturoEsUnaLinea() {
        var state = LedgerState()
        state.links[.rev] = link(validUntil: nov(25, 10), problem: .consentExpired)
        #expect(input(state).attention == [.bankProblem(.rev, .consentExpired)])
        state.links[.rev] = link(validUntil: nov(25, 10), problem: .keyRejected)
        #expect(input(state).attention == [.bankProblem(.rev, .keyRejected)])
        // Sin problema, sigue avisando de que caduca.
        state.links[.rev] = link(validUntil: nov(25, 10))
        #expect(input(state).attention == [.consentExpiring(.rev, nov(25, 10))])
    }

    // MARK: J17 — un pago no sale en dos resúmenes

    private func capture(_ cents: Int, _ name: String, at when: Date) -> Movement {
        Movement(bank: .rev, amountCents: cents, merchant: name, kind: cents < 0 ? .payment : .income, source: .notification,
                 date: when, isShop: true)
    }

    @Test func unCapturadoYSuFilaDelBancoNoSalenEnDosResumenes() {
        var state = LedgerState()
        let zara = capture(-4_995, "Zara", at: nov(19, 19))
        state.movements = [zara]
        // Resumen A: el día 19 por la noche.
        let a = input(state, since: nov(18, 22), now: nov(19, 20))
        #expect(a.payments.map(\.name) == ["Zara"])
        // El día 20 llega la fila del banco (sin enlazar): pareja probable del capturado que ya se contó.
        let row = Movement(bank: .rev, amountCents: -5_000, merchant: "ZARA ONLINE", kind: .payment, source: .bank,
                           date: nov(19, 19, 30), isShop: true, bankRef: "r1", bankStatus: .booked, importedAt: nov(20, 7))
        state.movements.append(row)
        let b = input(state, since: nov(19, 20), now: nov(20, 8))
        #expect(b.payments.isEmpty)
        #expect(b.income.isEmpty)
        #expect(b.banks.isEmpty)
        #expect(render(makeBriefing(b, calendar: cal).headline, .plain).hasPrefix("Nada nuevo"))
        // Lo mismo si la fila se enlazó al capturado (el banco ya no tiene fila propia).
        var linked = zara
        linked.bankRef = "r1"
        linked.bankStatus = .booked
        linked.linkedAt = nov(20, 7)
        var folded = LedgerState()
        folded.movements = [linked]
        let c = input(folded, since: nov(19, 20), now: nov(20, 8))
        #expect(c.payments.isEmpty && c.income.isEmpty && c.banks.isEmpty)
        // Una fila del banco sin capturado sí es nueva.
        var alone = LedgerState()
        alone.movements = [row]
        #expect(input(alone, since: nov(19, 20), now: nov(20, 8)).payments.map(\.cents) == [5_000])
    }

    // MARK: J18 — reabrir a mano

    @Test func reabrirAManoNoRepiteAlDiaSiguiente() {
        let first = BriefingRecord(shownAt: nov(20, 9), since: nov(19, 9))
        let reopened = BriefingSchedule.manual(previous: first, now: nov(20, 15), calendar: cal)
        #expect(reopened == BriefingRecord(shownAt: nov(20, 15), since: nov(19, 9)))
        var state = LedgerState()
        state.movements = [capture(-1_200, "Comida", at: nov(20, 12))]
        // El pago de las 12:00 sale al reabrir...
        #expect(input(state, since: reopened.since, now: nov(20, 15)).payments.map(\.name) == ["Comida"])
        // ...y no al día siguiente.
        let next = BriefingSchedule.due(previous: reopened, now: nov(21, 8), calendar: cal)
        #expect(next?.since == nov(20, 15))
        #expect(input(state, since: nov(20, 15), now: nov(21, 8)).payments.isEmpty)
    }

    // MARK: J19 — menores

    @Test func elTotalNombraAlBancoConectadoSinSaldoAunqueNoTengaMovimientos() {
        var state = LedgerState()
        state.links[.rev] = link(validUntil: date(12, 31))
        state.links[.ima] = link(validUntil: date(12, 31))
        state.balances[.rev] = ManualBalance(cents: 10_000, setAt: nov(20, 8), origin: .bank)
        let i = input(state)
        #expect(i.totalLeftOut == [.ima])
        #expect(lines(makeBriefing(i, calendar: cal), .money).first?.contains("sin contar imagin") == true)
        // Sin conexión no se nombra.
        state.links[.ima] = nil
        #expect(input(state).totalLeftOut.isEmpty)
    }

    // MARK: J6 — un registro del futuro no vale

    @Test func unRegistroDelFuturoSeIgnora() {
        let future = BriefingRecord(shownAt: nov(25, 9), since: nov(24, 9))
        let expected = BriefingRecord(shownAt: nov(20, 8, 30), since: nov(19, 8, 30))
        #expect(BriefingSchedule.due(previous: future, now: nov(20, 8, 30), calendar: cal) == expected)
        #expect(BriefingSchedule.manual(previous: future, now: nov(20, 8, 30), calendar: cal) == expected)
        // Justo ahora no es futuro: sigue mandando el de hoy.
        let same = BriefingRecord(shownAt: nov(20, 8, 30), since: nov(19, 8, 30))
        #expect(BriefingSchedule.due(previous: same, now: nov(20, 8, 30), calendar: cal) == nil)
    }

    @Test func conSaldoExactoNoEsEstimado() {
        var state = busyState()
        state.balances[.ima] = ManualBalance(cents: 128_455, setAt: nov(20, 8, 25), origin: .bank)
        let ima = input(state).banks.first { $0.bank == .ima }
        #expect(ima == BankLine(bank: .ima, cents: 128_455, estimated: false, changeCents: 165_000))
    }

    @Test func traspasoYValoresNoSonGastoNiIngreso() {
        var state = LedgerState()
        var sale = mv(.tr, 50_000, "Venta de ETF", at: nov(20, 7))
        sale.excludedFromSpending = true
        var purchase = mv(.tr, -30_000, "Compra de fondo", at: nov(20, 7, 5))
        purchase.excludedFromSpending = true
        state.movements = [sale, purchase]
        let i = input(state)
        #expect(i.income.isEmpty)
        #expect(i.payments.isEmpty)
        #expect(i.banks == [BankLine(bank: .tr, cents: nil, estimated: false, changeCents: 20_000)])
    }

    // MARK: Atención

    @Test func atencion() {
        var state = LedgerState()
        state.links[.rev] = link(validUntil: nov(30, 10))
        state.links[.ima] = link(validUntil: date(12, 31), problem: .bankUnavailable)
        #expect(input(state).attention == [.bankProblem(.ima, .bankUnavailable), .consentExpiring(.rev, nov(30, 10))])
        // A 11 días no se avisa.
        state.links[.rev] = link(validUntil: date(12, 1, 10))
        #expect(input(state).attention == [.bankProblem(.ima, .bankUnavailable)])
        // Caducada o rechazada: se dice.
        state.links[.rev] = link(validUntil: nov(18), problem: nil)
        #expect(input(state).attention.first == .bankProblem(.rev, .consentExpired))
        state.links[.rev] = link(validUntil: date(12, 31), problem: .keyRejected)
        #expect(input(state).attention.first == .bankProblem(.rev, .keyRejected))
    }

    @Test func datosViejosSeMencionan() {
        var state = LedgerState()
        state.links[.rev] = link(validUntil: date(12, 31), lastSuccess: nov(17, 8))
        #expect(input(state).attention == [.warning(title: "Los datos de Revolut llevan días sin actualizarse", detail: nil)])
        state.links[.rev] = link(validUntil: date(12, 31), lastSuccess: nov(19, 8))
        #expect(input(state).attention.isEmpty)
    }

    @Test func presupuestoSuperado() {
        var state = LedgerState()
        state.budgets.byCategory[.comerFuera] = 12_000
        state.movements = [mv(.rev, -6_000, "Restaurante uno", at: nov(3, 14), category: .comerFuera),
                           mv(.rev, -6_480, "Restaurante dos", at: nov(4, 14), category: .comerFuera)]
        let i = input(state)
        #expect(i.attention == [.budgetExceeded(name: "Comer fuera", spentCents: 12_480, limitCents: 12_000)])
        #expect(i.budgetTip == nil)
        var month = LedgerState()
        month.budgets.monthlyCents = 12_000
        month.movements = state.movements
        #expect(input(month).attention == [.budgetExceeded(name: "tu presupuesto del mes", spentCents: 12_480, limitCents: 12_000)])
    }

    @Test func presupuestoAlOchentaPorCientoDaConsejo() {
        var state = LedgerState()
        state.budgets.byCategory[.comerFuera] = 12_000
        state.movements = [mv(.rev, -4_000, "Restaurante uno", at: nov(3, 14), category: .comerFuera),
                           mv(.rev, -5_620, "Restaurante dos", at: nov(4, 14), category: .comerFuera)]
        let i = input(state)
        #expect(i.attention.isEmpty)
        #expect(i.budgetTip == BudgetTip(name: "Comer fuera", remainingCents: 2_380))
        // Al 50 % no hay consejo.
        state.movements = [mv(.rev, -6_000, "Restaurante uno", at: nov(3, 14), category: .comerFuera)]
        #expect(input(state).budgetTip == nil)
    }

    @Test func saldoBajoEsUnAvisoDelPeriodo() {
        var state = LedgerState()
        state.balances[.rev] = ManualBalance(cents: 500, setAt: nov(20, 8), origin: .bank)
        let warnings = input(state).attention.compactMap { item -> String? in
            if case .warning(let title, _) = item { return title }
            return nil
        }
        #expect(warnings == ["Saldo bajo en Revolut"])
    }

    // MARK: Nómina prevista

    private func salary(_ dates: [Date], cents: Int = 185_000, bank: BankID = .ima) -> LedgerState {
        var state = LedgerState()
        state.movements = dates.map { mv(bank, cents, "Nómina ACME", at: $0) }
        return state
    }

    @Test func nominaPrevista() {
        let state = salary([date(9, 27), date(10, 28)])
        #expect(expectedIncome(in: state, now: nov(20, 8, 30), calendar: cal)
            == ExpectedIncome(name: "Nómina ACME", bank: .ima, cents: 185_000, date: nov(28, 12)))
        let third = salary([date(9, 27), date(10, 28), nov(27)])
        #expect(expectedIncome(in: third, now: nov(28, 9), calendar: cal)
            == ExpectedIncome(name: "Nómina ACME", bank: .ima, cents: 185_000, date: date(12, 27, 12)))
        #expect(expectedIncome(in: salary([date(9, 27), date(10, 28)], cents: 29_999), now: nov(20, 8, 30), calendar: cal) == nil)
        #expect(expectedIncome(in: salary([date(9, 27), date(10, 28)], cents: 30_000), now: nov(20, 8, 30), calendar: cal)?.cents == 30_000)
        #expect(expectedIncome(in: salary([date(10, 28)]), now: nov(20, 8, 30), calendar: cal) == nil)
        #expect(expectedIncome(in: salary([date(9, 5), date(10, 20)]), now: nov(20, 8, 30), calendar: cal) == nil)
        // Dentro de ±3 días, sí; a 4, no.
        #expect(expectedIncome(in: salary([date(9, 25), date(10, 28)]), now: nov(20, 8, 30), calendar: cal) != nil)
        #expect(expectedIncome(in: salary([date(9, 24), date(10, 28)]), now: nov(20, 8, 30), calendar: cal) == nil)
        // La nómina de hace dos meses sin la del mes pasado no se espera.
        #expect(expectedIncome(in: salary([date(8, 27), date(9, 27)]), now: nov(20, 8, 30), calendar: cal) == nil)
        // Se retrasa: la fecha esperada ya pasó.
        #expect(expectedIncome(in: salary([date(9, 27), date(10, 28)]), now: nov(29, 8), calendar: cal) == nil)
    }

    @Test func nominaDelDia31AjustaAlMes() {
        let state = salary([date(8, 31), date(9, 30)])
        // U22: 31 ago + 30 sep (último día del mes corto) recupera el ancla 31 en octubre.
        #expect(expectedIncome(in: state, now: date(10, 5, 9), calendar: cal)?.date == date(10, 31, 12))
        let jan = salary([date(11, 30), date(12, 31)])
        #expect(expectedIncome(in: jan, now: date(1, 5, 9, year: 2027), calendar: cal)?.date == date(1, 31, 12, year: 2027))
        let feb = salary([date(12, 31), date(1, 31, year: 2027)])
        #expect(expectedIncome(in: feb, now: date(2, 5, 9, year: 2027), calendar: cal)?.date == date(2, 28, 12, year: 2027))
    }

    @Test func nominaNoCuentaTraspasosNiOtroNombre() {
        var state = salary([date(9, 27), date(10, 28)])
        state.movements[0].flaggedNotMine = true
        #expect(expectedIncome(in: state, now: nov(20, 8, 30), calendar: cal) == nil)
        var other = salary([date(9, 27)])
        other.movements.append(mv(.ima, 185_000, "Otro ingreso", at: date(10, 28)))
        #expect(expectedIncome(in: other, now: nov(20, 8, 30), calendar: cal) == nil)
    }

    @Test func nominaEnElResumenSoloSiEstaCerca() {
        let state = salary([date(9, 27), date(10, 28)])
        #expect(input(state, now: nov(20, 8, 30)).expected == nil)
        #expect(input(state, now: nov(24, 8, 30)).expected?.date == nov(28, 12))
        #expect(input(state, now: nov(22, 8, 30)).expected?.date == nov(28, 12))
    }

    // MARK: Lo que viene, faltas y dinero libre

    @Test func loQueVieneEnSieteDias() {
        var state = LedgerState()
        state.movements = subscription(.rev, "Netflix", 1399, date(9, 25), date(10, 25))
            + subscription(.rev, "Spotify", 1099, date(9, 22), date(10, 22))
            + subscription(.ima, "Gimnasio", 3000, date(10, 1), date(10, 31, 12))
            + subscription(.rev, "Lejos", 500, date(9, 28), date(10, 28))
        let i = input(state)
        #expect(i.upcoming.map(\.name) == ["Spotify", "Netflix"])
        #expect(i.upcoming.map(\.date) == [nov(22, 12), nov(25, 12)])
    }

    @Test func unaSuscripcionYaCobradaHoyNoSeCuentaDosVeces() {
        var state = LedgerState()
        state.movements = subscription(.rev, "Spotify", 1099, date(10, 20, 8), nov(20, 8))
        let i = input(state, now: nov(20, 9))
        #expect(i.upcoming.isEmpty)
        #expect(subscriptionCharges(in: state, now: nov(20, 9), calendar: cal).map(\.date) == [date(12, 20, 8)])
    }

    @Test func faltaDeSaldoYDineroLibre() {
        var state = LedgerState()
        state.movements = subscription(.rev, "Netflix", 1399, date(9, 21), date(10, 21))
        state.balances[.rev] = ManualBalance(cents: 920, setAt: nov(20, 8), origin: .manual)
        state.balances[.ima] = ManualBalance(cents: 128_455, setAt: nov(20, 8), origin: .manual)
        let netflix = UpcomingCharge(name: "Netflix", bank: .rev, cents: 1399, date: nov(21, 12))
        let i = input(state)
        #expect(i.shortfalls == [Shortfall(bank: .rev, charge: netflix, balanceCents: 920, missingCents: 479, suggestedFrom: .ima,
                                           suggestedCents: 1000, isEstimated: true, suggestedIsEstimated: true)])
        #expect(i.freeMoney == FreeMoney(cents: 920 + 128_455 - 1399, daysLeft: 11))
        // Con un mínimo apartado en imagin y sin saldo de Trade Republic.
        var book = AccountBook()
        book.floors[.ima] = 5000
        #expect(input(state, book: book).freeMoney == FreeMoney(cents: 920 + 128_455 - 5000 - 1399, daysLeft: 11))
    }

    @Test func dineroLibreDiceLosBancosQueFaltan() {
        var state = LedgerState()
        state.balances[.rev] = ManualBalance(cents: 50_000, setAt: nov(20, 8), origin: .bank)
        #expect(input(state).freeMoney == FreeMoney(cents: 50_000, daysLeft: 11, missingBanks: [.ima]))
    }

    @Test func elMesYElMesAnterior() {
        var state = LedgerState()
        state.movements = [mv(.rev, -10_000, "Tienda", at: date(10, 5), shop: true),
                           mv(.rev, -20_000, "Tienda", at: date(10, 29), shop: true),
                           mv(.rev, -6_000, "Tienda", at: nov(3), shop: true)]
        let month = input(state).month
        #expect(month?.spentCents == 6_000)
        #expect(month?.previousMonthName == "octubre")
        #expect(month?.paceDifferenceCents == 6_000 - 10_000)
        #expect(month?.projectedCents != nil)
        // Sin gasto este mes ni mes anterior, no hay sección.
        #expect(input(LedgerState()).month == nil)
        // Enero mira a diciembre.
        var january = LedgerState()
        january.movements = [mv(.rev, -1_000, "Tienda", at: date(12, 3), shop: true)]
        #expect(input(january, since: date(1, 4, 9, year: 2027), now: date(1, 5, 9, year: 2027)).month?.previousMonthName == "diciembre")
    }

    @Test func carteraParcialYSinDatos() throws {
        #expect(input(LedgerState()).investments == nil)
        var p = Portfolio()
        p.transactions = [InvestmentTransaction(id: "b", date: date(3, 1, 10), instrument: "AA", name: "A", assetClass: nil,
                                                shares: 1, cashCents: -10_000, priceEUR: nil)]
        let s = try #require(input(LedgerState(), portfolio: p).investments)
        #expect(s.valueCents == nil)
        #expect(s.missingPrices == 1)
    }

    @Test func sinDatosPersonalesEnLaSalida() {
        let text = String(describing: input(busyState()))
        #expect(!text.contains("ES91"))
    }

    // MARK: U7 — El filtro de `BriefingInput.swift:142-143` («cobrado hoy» no se cuenta dos veces)

    @Test func cobradoHoyNoSeCuentaDosVeces() {
        // Caso 1: suscripción con cobro previsto hoy (20 nov) y fila del banco `dayOnly` de hoy (fechada a las 12:00),
        // consultada a las 08:30 -> `movementCounts` la reconoce como cobrada hoy y NO sale en `upcoming` (sin duplicar).
        var state = LedgerState()
        state.movements = [
            Movement(bank: .rev, amountCents: -1_399, merchant: "Netflix", kind: .payment, source: .bank,
                     date: date(9, 20, 12), isShop: true, bankRef: "n1", bankStatus: .booked, dayOnly: true),
            Movement(bank: .rev, amountCents: -1_399, merchant: "Netflix", kind: .payment, source: .bank,
                     date: date(10, 20, 12), isShop: true, bankRef: "n2", bankStatus: .booked, dayOnly: true),
            // Fila de hoy `dayOnly` (importe distinto para que `sub.nextDate` siga en 20 nov): `chargedToday` la retira de `upcoming`.
            Movement(bank: .rev, amountCents: -1_999, merchant: "Netflix", kind: .payment, source: .bank,
                     date: nov(20, 12), isShop: true, bankRef: "n3", bankStatus: .booked, dayOnly: true),
        ]
        let morning = input(state, since: nov(19, 10), now: nov(20, 8, 30))
        #expect(!morning.upcoming.contains { $0.name == "Netflix" })
        // A las 12:30 el resumen ya lista el cobro en `payments` una sola vez y sigue sin repetirlo en `upcoming`.
        let noon = input(state, since: nov(19, 10), now: nov(20, 12, 30))
        #expect(!noon.upcoming.contains { $0.name == "Netflix" })
        #expect(noon.payments.filter { $0.name == "Netflix" }.count == 1)

        // Caso 2: si la fila de hoy está marcada `excludedFromSpending`, NO oculta el cobro pendiente de la suscripción.
        var withExcluded = LedgerState()
        withExcluded.movements = [
            Movement(bank: .rev, amountCents: -1_399, merchant: "Netflix", kind: .payment, source: .bank,
                     date: date(9, 20, 12), isShop: true, bankRef: "e1", bankStatus: .booked, dayOnly: true),
            Movement(bank: .rev, amountCents: -1_399, merchant: "Netflix", kind: .payment, source: .bank,
                     date: date(10, 20, 12), isShop: true, bankRef: "e2", bankStatus: .booked, dayOnly: true),
            Movement(bank: .rev, amountCents: -1_399, merchant: "Netflix", kind: .payment, source: .statement,
                     date: nov(20, 12), isShop: false, dayOnly: true, excludedFromSpending: true),
        ]
        let excludedMorning = input(withExcluded, since: nov(19, 10), now: nov(20, 8, 30))
        #expect(excludedMorning.upcoming.filter { $0.name == "Netflix" }.count == 1)
        #expect(excludedMorning.payments.filter { $0.name == "Netflix" }.isEmpty)
    }
}
