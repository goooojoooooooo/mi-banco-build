import Foundation
import Testing
@testable import MiBancoCore

// Reglas de la integración de los planes 2 (datos del banco) y 3 (gasto y presupuestos): I1–I7.

private let madrid: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Madrid")!
    c.locale = Locale(identifier: "es_ES")
    return c
}()

/// Fecha de 2026 en hora de Madrid.
private func at(_ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    madrid.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}

/// Capturado por aviso (pago si `cents < 0`).
private func captured(_ bank: BankID, _ cents: Int, _ merchant: String?, _ date: Date, isShop: Bool = true) -> Movement {
    Movement(bank: bank, amountCents: cents, merchant: merchant, kind: cents < 0 ? .payment : .income,
             source: .notification, date: date, fingerprint: "fp\(cents)\(date.timeIntervalSince1970)", isShop: isShop)
}

/// Fila creada desde la API del banco (por defecto de solo día, guardada a mediodía).
private func bankRow(_ bank: BankID, _ cents: Int, _ merchant: String?, _ date: Date, ref: String,
                     importedAt: Date, dayOnly: Bool = true, isShop: Bool = false) -> Movement {
    Movement(bank: bank, amountCents: cents, merchant: merchant, kind: cents < 0 ? .payment : .income, source: .bank,
             date: date, isShop: isShop, bankRef: ref, bankStatus: .booked, importedAt: importedAt, dayOnly: dayOnly)
}

private func link(lastSuccessAt: Date) -> BankLinkInfo {
    var info = BankLinkInfo(connectedAt: at(10, 1), consentValidUntil: at(12, 31))
    info.lastSuccessAt = lastSuccessAt
    return info
}

// MARK: Extracto de Trade Republic con compras de un fondo (dos meses seguidos, el mismo importe)

private let trHeaders = ["datetime", "date", "account_type", "category", "type", "asset_class", "name", "symbol", "shares",
                         "price", "amount", "fee", "tax", "currency", "transaction_id", "mcc_code"]

private func trLine(_ values: [String: String]) -> String {
    trHeaders.map { values[$0] ?? "" }.joined(separator: ",")
}

private func fundBuy(_ datetime: String, _ date: String, id: String) -> [String: String] {
    ["datetime": datetime, "date": date, "account_type": "DEFAULT", "category": "TRADING", "type": "BUY",
     "asset_class": "FUND", "name": "Test World Fund", "symbol": "IE00TEST0001", "shares": "1.5", "price": "100.00",
     "amount": "-150.00", "fee": "-1.00", "currency": "EUR", "transaction_id": id]
}

private let trCSV = ([trHeaders.joined(separator: ",")] + [
    fundBuy("2026-10-19T08:30:00Z", "2026-10-19", id: "buy-1"),
    fundBuy("2026-11-19T08:30:00Z", "2026-11-19", id: "buy-2"),
].map(trLine)).joined(separator: "\n") + "\n"

@Suite struct IntegrationTests {
    // MARK: I1 — las operaciones de valores no son gasto

    @Test func i1CompraDeFondoDelExtractoMueveElSaldoPeroNoEsGasto() throws {
        var l = Ledger()
        l.setBalance(.tr, cents: 100_000, now: at(10, 1))
        l.setMonthlyBudget(10_000)
        let parsed = try parseStatement(Data(trCSV.utf8), expected: .tr, now: at(11, 20), calendar: madrid)
        l.importStatement(parsed, now: at(11, 20), calendar: madrid)
        let buys = l.state.movements.filter { $0.amountCents == -15_100 }
        #expect(buys.count == 2)
        #expect(buys.allSatisfy { $0.excludedFromSpending })
        // En el saldo, sí.
        #expect(l.balance(.tr)?.cents == 100_000 - 2 * 15_100)
        // En ningún gasto, presupuesto, previsión, media ni suscripción.
        let now = at(11, 20, 18)
        #expect(spendingMovements(in: l.state.movements).isEmpty)
        #expect(monthSpending(in: l.state, month: now, now: now, calendar: madrid).totalCents == 0)
        #expect(budgetStatuses(in: l.state, month: now, now: now, calendar: madrid).first?.spentCents == 0)
        #expect(monthForecast(in: l.state, now: now, calendar: madrid)?.spentCents == 0)
        #expect(averageMonthlySpending(in: l.state, category: nil, before: at(12, 1), months: 2, calendar: madrid) == 0)
        #expect(detectSubscriptions(in: l.state.movements, now: now, calendar: madrid).isEmpty)
        #expect(activeSubscriptions(in: l.state, now: now, calendar: madrid).isEmpty)
        #expect(spendingPace(movements: l.state.movements, now: now, calendar: madrid)?.thisMonthCents ?? 0 == 0)
        // Tampoco se empareja como traspaso con un ingreso del mismo importe en otro banco.
        var withIncome = l.state.movements
        withIncome.append(captured(.ima, 15_100, "Traspaso desde Trade Republic", at(11, 19, 11), isShop: false))
        #expect(ownTransferPairs(in: withIncome).isEmpty)
    }

    @Test func i1ControlUnPagoNormalSiEsGasto() {
        let pay = captured(.tr, -15_100, "Mercadona", at(11, 19, 10))
        var trade = pay
        trade.id = UUID()
        trade.excludedFromSpending = true
        #expect(spendingMovements(in: [pay, trade]).map(\.id) == [pay.id])
    }

    // MARK: I2 — un capturado sin confirmar y su fila del banco no suman dos veces

    @Test func i2PropinaCuentaUnaSolaVezLaFilaDelBanco() {
        let tip = captured(.rev, -5000, "Restaurante Lua", at(11, 10, 22))
        let row = bankRow(.rev, -5500, "RESTAURANTE LUA", at(11, 10), ref: "b-1", importedAt: at(11, 11, 8))
        let state = LedgerState(movements: [tip, row], budgets: Budgets(monthlyCents: 100_000),
                                links: [.rev: link(lastSuccessAt: at(11, 20, 8))])
        let now = at(11, 20, 18)
        #expect(unconfirmedCaptureIDs(in: state, now: now) == [tip.id])
        #expect(spendingExclusions(in: state, now: now).contains(tip.id))
        #expect(monthSpending(in: state, month: now, now: now, calendar: madrid).totalCents == 5500)
        #expect(budgetStatuses(in: state, month: now, now: now, calendar: madrid).first?.spentCents == 5500)
        #expect(monthForecast(in: state, now: now, calendar: madrid)?.spentCents == 5500)
        #expect(spendingMovements(in: state.movements, notSpending: spendingExclusions(in: state, now: now)).map(\.id) == [row.id])
    }

    @Test func i2SinDatosDelBancoDeEseDiaElCapturadoCuentaComoAntes() {
        let tip = captured(.rev, -5000, "Restaurante Lua", at(11, 10, 22))
        let now = at(11, 20, 18)
        // Sin banco conectado.
        let alone = LedgerState(movements: [tip])
        #expect(unconfirmedCaptureIDs(in: alone, now: now).isEmpty)
        #expect(monthSpending(in: alone, month: now, now: now, calendar: madrid).totalCents == 5000)
        // Banco conectado, pero lo que se ve de él empieza después de ese día.
        let later = bankRow(.rev, -1000, "Bolt", at(11, 12), ref: "b-2", importedAt: at(11, 13, 8))
        let connected = LedgerState(movements: [tip, later], links: [.rev: link(lastSuccessAt: at(11, 20, 8))])
        #expect(unconfirmedCaptureIDs(in: connected, now: now).isEmpty)
        #expect(monthSpending(in: connected, month: now, now: now, calendar: madrid).totalCents == 6000)
    }

    // MARK: I3 — traspasos vistos solo por el banco (fechas de solo día)

    @Test func i3TraspasoVistoSoloPorDosImportacionesSeEmpareja() {
        let out = bankRow(.rev, -100_000, "Envio", at(11, 10), ref: "r-1", importedAt: at(11, 10, 8))
        let inc = bankRow(.ima, 100_000, "Abono", at(11, 11), ref: "i-1", importedAt: at(11, 11, 8))
        let state = LedgerState(movements: [out, inc])
        #expect(ownTransferPairs(in: state.movements) == [OwnTransferPair(paymentID: out.id, incomeID: inc.id)])
        let now = at(11, 12, 9)
        #expect(spendingMovements(in: state.movements).isEmpty)
        #expect(monthSpending(in: state, month: now, now: now, calendar: madrid).totalCents == 0)
        let feed = insights(for: state, now: now, calendar: madrid)
        #expect(!feed.contains { $0.kind == .largeIncome || $0.kind == .largePayment })
    }

    @Test func i3ControlSinParejaElIngresoSiAvisa() {
        // Dos días de Madrid sin palabras de traspaso: no es pareja.
        let out = bankRow(.rev, -100_000, "Envio", at(11, 9), ref: "r-1", importedAt: at(11, 9, 8))
        let inc = bankRow(.ima, 100_000, "Abono", at(11, 11), ref: "i-1", importedAt: at(11, 11, 8))
        let state = LedgerState(movements: [out, inc])
        #expect(ownTransferPairs(in: state.movements).isEmpty)
        let feed = insights(for: state, now: at(11, 12, 9), calendar: madrid)
        #expect(feed.contains { $0.kind == .largeIncome })
    }

    @Test func i3DiasDeMadridConPalabrasHastaTresDias() {
        // Solo día el 10; el ingreso exacto el 13 a las 20:00 (80 horas): por días de Madrid son 3, con palabras empareja.
        let out = bankRow(.rev, -20_000, "Transferencia a imagin", at(11, 10), ref: "r-1", importedAt: at(11, 14))
        let inc = captured(.ima, 20_000, "Bizum", at(11, 13, 20), isShop: false)
        #expect(ownTransferPairs(in: [out, inc]).count == 1)
        // Cuatro días: no.
        let late = captured(.ima, 20_000, "Bizum", at(11, 14, 9), isShop: false)
        #expect(ownTransferPairs(in: [out, late]).isEmpty)
    }

    @Test func i3FilaHistoricaDelBancoNoAvisaAlInstante() {
        var state = LedgerState(movements: [], budgets: Budgets(monthlyCents: 10_000))
        state.balances[.rev] = ManualBalance(cents: 12_000, setAt: at(11, 1), origin: .manual)
        let old = bankRow(.rev, -50_000, "Mediamarkt", at(11, 2), ref: "r-9", importedAt: at(11, 20), isShop: true)
        state.movements.append(old)
        #expect(old.isHistorical)
        #expect(immediateAlerts(afterStoring: old, in: state, now: at(11, 20, 9), calendar: madrid).isEmpty)
    }

    // MARK: I4 — CSV sin hora falsa

    @Test func i4CsvDejaLaHoraVaciaEnFilasDeSoloDia() {
        let row = bankRow(.ima, -2345, "Mercadona", at(11, 18), ref: "c-1", importedAt: at(11, 19))
        let exact = captured(.rev, -1250, "Bolt", at(11, 18, 13, 5))
        let csv = movementsCSV(LedgerState(movements: [row, exact]), now: at(11, 20), calendar: madrid)
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        #expect(lines.count == 3)
        let byMerchant = Dictionary(uniqueKeysWithValues: lines.dropFirst().map { line -> (String, [String]) in
            let fields = line.components(separatedBy: ";")
            return (fields[4], fields)
        })
        #expect(byMerchant["Mercadona"]?[0] == "2026-11-18")
        #expect(byMerchant["Mercadona"]?[1] == "")
        #expect(byMerchant["Bolt"]?[1] == "13:05")
    }

    // MARK: I5 — copia de seguridad y conexiones del banco

    private func bankState() -> LedgerState {
        var linked = captured(.rev, -1250, "Mercadona", at(11, 18, 13, 5))
        linked.bankRef = "t-1"
        linked.bankStatus = .booked
        linked.bankMerchant = "MERCADONA VALENCIA"
        let row = bankRow(.ima, -2345, "Farmacia", at(11, 17), ref: "c-1", importedAt: at(11, 19))
        let trade = Movement(bank: .tr, amountCents: -15_100, merchant: "Test World Fund", kind: .payment,
                             source: .statement, date: at(11, 19, 9, 30), statementRef: "tr|buy-2", bankStatus: .booked,
                             importedAt: at(11, 20), excludedFromSpending: true)
        return LedgerState(
            balances: [.tr: ManualBalance(cents: 84_900, setAt: at(11, 20), origin: .statement),
                       .rev: ManualBalance(cents: 32_770, setAt: at(11, 19), origin: .bank)],
            movements: [linked, row, trade],
            categoryOverrides: ["farmacia": .salud],
            links: [.rev: link(lastSuccessAt: at(11, 19))])
    }

    @Test func i5CopiaLlevaLosCamposDelBancoIdaYVuelta() throws {
        let s = bankState()
        let file = try decodeBackup(encodeBackup(s, exportedAt: at(11, 20, 9)))
        #expect(file.ledger == s)
        let trade = file.ledger.movements.first { $0.statementRef == "tr|buy-2" }
        #expect(trade?.excludedFromSpending == true)
        #expect(file.ledger.movements.first { $0.bankRef == "c-1" }?.dayOnly == true)
        #expect(file.ledger.movements.first { $0.bankRef == "t-1" }?.bankMerchant == "MERCADONA VALENCIA")
        #expect(file.ledger.balances[.tr]?.origin == .statement)
    }

    @Test func i5RestaurarNuncaTraeLasConexiones() throws {
        let backup = bankState()
        var info = link(lastSuccessAt: at(11, 20, 7))
        info.historyLoaded = true
        info.problem = .rateLimited
        info.fetchLog = [at(11, 20, 7)]
        info.lastAttemptAt = at(11, 20, 7)
        var device = Ledger(state: LedgerState(links: [.ima: info]))
        device.restore(try decodeBackup(encodeBackup(backup, exportedAt: at(11, 20, 9))).ledger)
        // R36: la conexión se queda con el cursor rebobinado y todo lo demás intacto.
        var expected = info
        expected.lastSuccessAt = nil
        expected.historyLoaded = false
        #expect(device.state.links == [.ima: expected])
        #expect(device.state.links[.ima]?.consentValidUntil == info.consentValidUntil)
        #expect(device.state.links[.ima]?.problem == .rateLimited)
        #expect(device.state.links[.ima]?.fetchLog == [at(11, 20, 7)])
        // La de la copia (.rev) no viene.
        #expect(device.state.links[.rev] == nil)
        // Los movimientos y saldos del banco que trae la copia se restauran como cualquier otro.
        #expect(device.state.movements == backup.movements)
        #expect(device.state.balances == backup.balances)
        // Y un aparato sin conexiones sigue sin ninguna.
        var fresh = Ledger()
        fresh.restore(backup)
        #expect(fresh.state.links.isEmpty)
        #expect(fresh.state.movements == backup.movements)
    }

    /// R36: tras restaurar, la siguiente sincronización pide el historial entero y los capturados de la última semana de
    /// la copia no se dan por «sin confirmar» (con el cursor sin tocar, entre la copia y el cursor no se volvería a pedir nada).
    @Test func r36RestaurarRebobinaElCursorYNoDejaCapturadosSinConfirmar() throws {
        let week = captured(.rev, -4000, "Cafeteria", at(11, 12, 9))
        var firstRow = bankRow(.rev, -1500, "Bolt", at(11, 5), ref: "b-1", importedAt: at(11, 6, 8))
        firstRow.dayOnly = true
        var info = link(lastSuccessAt: at(11, 20, 8))
        info.historyLoaded = true
        var device = Ledger(state: LedgerState(links: [.rev: info]))
        let backup = LedgerState(movements: [firstRow, week])
        // Con el cursor sin tocar el capturado se daría por sin confirmar (más de 7 días antes de la última consulta).
        #expect(unconfirmedCaptureIDs(in: LedgerState(movements: backup.movements, links: [.rev: info]), now: at(11, 20, 18)) == [week.id])
        device.restore(backup)
        #expect(unconfirmedCaptureIDs(in: device.state, now: at(11, 20, 18)).isEmpty)
        #expect(spendingMovements(in: device.state.movements,
                                  notSpending: spendingExclusions(in: device.state, now: at(11, 20, 18))).map(\.id).contains(week.id))
        let rewound = try #require(device.state.links[.rev])
        let decision = SyncPolicy.decide(rewound, trigger: .manual, now: at(11, 20, 18), calendar: madrid)
        guard case let .fetch(_, strategy) = decision else { Issue.record("esperaba .fetch: \(decision)"); return }
        #expect(strategy == .longest)
    }

    @Test func i5CopiaDeAntesDeLosCamposDelBancoSeRestaura() throws {
        let json = """
        {"app":"MiBanco","version":1,"exportedAt":800000000,"ledger":{
          "balances":["rev",{"cents":50000,"setAt":790000000,"fromBank":true}],
          "movements":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","bank":"rev","amountCents":-1250,"merchant":"Mercadona",
                        "kind":"payment","source":"notification","date":795000000,"isShop":true,"category":"supermercado"}],
          "unread":[],"mutedMerchants":["glovo"],"categoryOverrides":{"glovo":"comerFuera"},
          "budgets":{"monthlyCents":90000,"byCategory":[]},"dismissedSubscriptions":["rev|netflix"]}}
        """
        let file = try decodeBackup(Data(json.utf8))
        let m = try #require(file.ledger.movements.first)
        #expect(m.category == .supermercado)
        #expect(m.bankRef == nil && m.statementRef == nil && m.bankStatus == nil && m.importedAt == nil)
        #expect(m.dayOnly == false && m.bankMerchant == nil && m.excludedFromSpending == false)
        #expect(file.ledger.balances[.rev]?.origin == .notice)
        #expect(file.ledger.links.isEmpty)
        var device = Ledger(state: LedgerState(links: [.rev: link(lastSuccessAt: at(11, 20))]))
        device.restore(file.ledger)
        #expect(device.state.links[.rev] != nil)
        #expect(device.state.movements == file.ledger.movements)
        #expect(device.state.budgets.monthlyCents == 90_000)
    }

    // MARK: I6 — la clave del comercio no cambia al enlazar con el banco

    @Test func i6CategoriaDelComercioSobreviveAlEnlaceConElBanco() {
        let capture = captured(.rev, -1250, "Mercadona", at(11, 18, 13, 5))
        var l = Ledger(state: LedgerState(movements: [capture]))
        l.setCategory(.ocio, for: capture.id, applyToMerchant: true)
        let key = normalizeMerchant("Mercadona")
        #expect(l.state.categoryOverrides[key] == .ocio)
        let record = BankRecord(ref: "t-1", bank: .rev, amountCents: -1250, timing: .transactionDay(at(11, 18)),
                                status: .booked, merchant: "MERCADONA VALENCIA 4021", isShop: true)
        let report = l.reconcile([record], bank: .rev, channel: .bank, coverage: nil, now: at(11, 20), calendar: madrid)
        #expect(report.linked == 1)
        let linked = l.state.movements[0]
        #expect(linked.bankRef == "t-1")
        #expect(linked.bankMerchant == "MERCADONA VALENCIA 4021")
        #expect(normalizeMerchant(linked.merchant ?? "") == key)
        #expect(categoryOf(linked, in: l.state, subscriptionKeys: []) == .ocio)
    }

    @Test func i6FilaSoloDelBancoUsaSuPropioComercio() {
        var l = Ledger()
        let records = [
            BankRecord(ref: "n-1", bank: .rev, amountCents: -1299, timing: .transactionDay(at(10, 15)), status: .booked,
                       merchant: "Netflix.com"),
            BankRecord(ref: "n-2", bank: .rev, amountCents: -1299, timing: .transactionDay(at(11, 15)), status: .booked,
                       merchant: "Netflix.com"),
        ]
        _ = l.reconcile(records, bank: .rev, channel: .bank, coverage: nil, now: at(11, 20), calendar: madrid)
        #expect(l.state.movements.count == 2)
        let first = l.state.movements.first { $0.bankRef == "n-1" }!
        l.setCategory(.ocio, for: first.id, applyToMerchant: true)
        #expect(l.state.categoryOverrides[normalizeMerchant("Netflix.com")] == .ocio)
        let second = l.state.movements.first { $0.bankRef == "n-2" }!
        #expect(categoryOf(second, in: l.state, subscriptionKeys: []) == .ocio)
    }

    // MARK: I7 — las filas históricas no disparan avisos de Plan 3

    @Test func i7PresupuestoNoAvisaPorFilaHistorica() {
        let earlier = captured(.rev, -7000, "Mercadona", at(11, 5, 10))
        let old = bankRow(.rev, -2000, "Zara", at(11, 10), ref: "z-1", importedAt: at(11, 19), isShop: true)
        let state = LedgerState(movements: [earlier, old], budgets: Budgets(monthlyCents: 10_000))
        #expect(old.isHistorical)
        let alerts = immediateAlerts(afterStoring: old, in: state, now: at(11, 19, 9), calendar: madrid)
        #expect(!alerts.contains { $0.kind == .budgetWarning || $0.kind == .budgetExceeded })
        // Control: el mismo pago llegado al momento sí avisa.
        var fresh = old
        fresh.importedAt = nil
        let control = LedgerState(movements: [earlier, fresh], budgets: Budgets(monthlyCents: 10_000))
        #expect(immediateAlerts(afterStoring: fresh, in: control, now: at(11, 19, 9), calendar: madrid)
            .contains { $0.kind == .budgetWarning })
    }

    @Test func i7PagoEIngresoGrandesHistoricosNoAvisan() {
        let pay = bankRow(.rev, -50_000, "Mediamarkt", at(11, 10), ref: "p-1", importedAt: at(11, 13), isShop: true)
        let inc = bankRow(.ima, 120_000, "Ingreso", at(11, 10), ref: "i-1", importedAt: at(11, 13))
        let state = LedgerState(movements: [pay, inc])
        #expect(pay.isHistorical && inc.isHistorical)
        for m in [pay, inc] {
            #expect(immediateAlerts(afterStoring: m, in: state, now: at(11, 13, 9), calendar: madrid).isEmpty)
        }
        let feed = insights(for: state, now: at(11, 13, 9), calendar: madrid)
        #expect(!feed.contains { $0.kind == .largePayment || $0.kind == .largeIncome })
        // Control: sin `importedAt` (llegados al momento) sí avisan.
        var p = pay, i = inc
        p.importedAt = nil
        i.importedAt = nil
        let live = insights(for: LedgerState(movements: [p, i]), now: at(11, 13, 9), calendar: madrid)
        #expect(live.contains { $0.kind == .largePayment })
        #expect(live.contains { $0.kind == .largeIncome })
    }

    @Test func i7CambioDePrecioDeSuscripcionHistoricaNoAvisa() {
        let sep = bankRow(.rev, -999, "Netflix", at(9, 15), ref: "s-1", importedAt: at(10, 18), isShop: true)
        let oct = bankRow(.rev, -1199, "Netflix", at(10, 15), ref: "s-2", importedAt: at(10, 18), isShop: true)
        let state = LedgerState(movements: [sep, oct])
        #expect(oct.isHistorical)
        let alerts = immediateAlerts(afterStoring: oct, in: state, now: at(10, 18, 9), calendar: madrid)
        #expect(!alerts.contains { $0.kind == .subscriptionPriceChange })
        let feed = insights(for: state, now: at(10, 18, 9), calendar: madrid)
        #expect(!feed.contains { $0.kind == .subscriptionPriceChange })
        // Control: la misma subida llegada al momento sí avisa.
        var liveOct = oct
        liveOct.importedAt = nil
        let live = immediateAlerts(afterStoring: liveOct, in: LedgerState(movements: [sep, liveOct]),
                                   now: at(10, 15, 13), calendar: madrid)
        #expect(live.contains { $0.kind == .subscriptionPriceChange })
    }

    // MARK: R33 — un banco conocido solo por extractos también tiene cobertura

    private func revolutStatement(_ rows: [(String, String)]) -> String {
        let header = "Type,Product,Started Date,Completed Date,Description,Amount,Fee,Currency,State,Balance"
        return ([header] + rows.map { "Card Payment,Current,\($0.0),\($0.0),Restaurante,\($0.1),0.00,EUR,COMPLETED,100.00" })
            .joined(separator: "\n") + "\n"
    }

    @Test func r33CapturadoSinConfirmarDentroDelPeriodoDeUnExtractoNoSumaDosVeces() throws {
        // Capturado 50,00 € el día D (10 nov); el extracto trae 55,00 € ese día y cubre D-10 ... D+10.
        let tip = captured(.rev, -5000, "Restaurante Lua", at(11, 10, 22))
        let csv = revolutStatement([("2026-10-31 10:00:00", "-1.00"), ("2026-11-10 12:00:00", "-55.00"),
                                    ("2026-11-20 10:00:00", "-2.00")])
        var l = Ledger(state: LedgerState(movements: [tip]))
        let report = l.importStatement(try parseStatement(Data(csv.utf8), expected: .rev, now: at(11, 18, 18), calendar: madrid),
                                       now: at(11, 18, 18), calendar: madrid)
        #expect(report.added == 3)
        #expect(report.linked == 0)
        let now = at(11, 18, 18)  // 8 días después
        #expect(l.state.links[.rev] == nil)
        #expect(unconfirmedCaptureIDs(in: l.state, now: now) == [tip.id])
        let counted = spendingMovements(in: l.state.movements, notSpending: spendingExclusions(in: l.state, now: now))
            .filter { madrid.isDate($0.date, inSameDayAs: at(11, 10)) }
        #expect(counted.map(\.amountCents) == [-5500])
        // Con 3 días de margen todavía no (definición de Plan 2: más de 7 días).
        #expect(unconfirmedCaptureIDs(in: l.state, now: at(11, 13, 18)).isEmpty)
        // Fuera del periodo del extracto no se reclama, ni en otro banco.
        let before = captured(.rev, -300, "Cafe", at(10, 20, 10))
        let other = captured(.ima, -5000, "Restaurante Lua", at(11, 10, 22))
        var more = l
        more.state.movements.append(contentsOf: [before, other])
        #expect(unconfirmedCaptureIDs(in: more.state, now: now) == [tip.id])
    }

    // MARK: R38 — la cobertura de un extracto son intervalos por importación

    @Test func r38DosExtractosConUnMesDeHuecoNoCubrenElHueco() throws {
        var l = Ledger()
        // Extracto de septiembre (importado el 1 de octubre) y extracto de noviembre (importado el 16).
        let sep = revolutStatement([("2026-09-01 10:00:00", "-1.00"), ("2026-09-30 10:00:00", "-2.00")])
        let nov = revolutStatement([("2026-11-02 10:00:00", "-3.00"), ("2026-11-14 10:00:00", "-4.00")])
        l.importStatement(try parseStatement(Data(sep.utf8), expected: .rev, now: at(10, 1, 9), calendar: madrid),
                          now: at(10, 1, 9), calendar: madrid)
        l.importStatement(try parseStatement(Data(nov.utf8), expected: .rev, now: at(11, 16, 9), calendar: madrid),
                          now: at(11, 16, 9), calendar: madrid)
        #expect(l.state.statementCoverage[.rev]?.count == 2)
        let now = at(11, 20, 18)
        // A mitad del hueco (15 de octubre): ningún extracto lo cubre, no es «Sin confirmar» y cuenta en el gasto.
        let gap = captured(.rev, -4200, "Cena", at(10, 15, 21))
        // Controles: dentro de cada extracto sí es «Sin confirmar».
        let inSep = captured(.rev, -700, "Cafe", at(9, 10, 9))
        let inNov = captured(.rev, -900, "Menu", at(11, 5, 14))
        l.state.movements.append(contentsOf: [gap, inSep, inNov])
        let unconfirmed = unconfirmedCaptureIDs(in: l.state, now: now)
        #expect(unconfirmed == [inSep.id, inNov.id])
        let counted = spendingMovements(in: l.state.movements, notSpending: spendingExclusions(in: l.state, now: now))
        #expect(counted.contains { $0.id == gap.id })
        #expect(!counted.contains { $0.id == inSep.id || $0.id == inNov.id })
        // Los intervalos se guardan y vuelven de una copia de seguridad; una copia antigua (sin el campo) se lee sin ellos.
        let data = try encodeBackup(l.state, exportedAt: now)
        #expect(try decodeBackup(data).ledger.statementCoverage == l.state.statementCoverage)
        let old = try JSONEncoder().encode(LedgerState())
        var json = try #require(try JSONSerialization.jsonObject(with: old) as? [String: Any])
        json.removeValue(forKey: "statementCoverage")
        let decoded = try JSONDecoder().decode(LedgerState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.statementCoverage.isEmpty)
    }

    @Test func r38ElDiaDeImportacionNoCuentaComoCubierto() throws {
        // Extracto con filas hasta el 18 de noviembre, importado ese mismo día a las 18:00.
        let csv = revolutStatement([("2026-11-01 10:00:00", "-1.00"), ("2026-11-18 10:00:00", "-2.00")])
        var l = Ledger()
        l.importStatement(try parseStatement(Data(csv.utf8), expected: .rev, now: at(11, 18, 18), calendar: madrid),
                          now: at(11, 18, 18), calendar: madrid)
        let importDay = captured(.rev, -5000, "Restaurante", at(11, 18, 22))
        let dayBefore = captured(.rev, -3000, "Bar", at(11, 17, 22))
        l.state.movements.append(contentsOf: [importDay, dayBefore])
        // Pasados más de 7 días: el del día anterior a la importación sí está cubierto, el del día de importación no.
        let now = at(11, 27, 18)
        #expect(unconfirmedCaptureIDs(in: l.state, now: now) == [dayBefore.id])
        let counted = spendingMovements(in: l.state.movements, notSpending: spendingExclusions(in: l.state, now: now))
        #expect(counted.contains { $0.id == importDay.id })
        // Importado un día después, el 18 ya queda cubierto.
        var later = Ledger()
        later.importStatement(try parseStatement(Data(csv.utf8), expected: .rev, now: at(11, 19, 9), calendar: madrid),
                              now: at(11, 19, 9), calendar: madrid)
        later.state.movements.append(importDay)
        #expect(unconfirmedCaptureIDs(in: later.state, now: now) == [importDay.id])
    }

    // MARK: R34 — una operación de valores nunca genera avisos de pago

    private func insightKinds(_ m: Movement, others: [Movement], now: Date) -> Set<InsightKind> {
        let state = LedgerState(movements: others + [m])
        let kinds = immediateAlerts(afterStoring: m, in: state, now: now, calendar: madrid).map(\.kind)
            + insights(for: state, now: now, calendar: madrid).map(\.kind)
        return Set(kinds).intersection([.largePayment, .unusualPayment, .duplicateCharge, .subscriptionPriceChange,
                                        .subscriptionUpcoming])
    }

    @Test func r34CompraDeFondoDeHoyNoGeneraAvisosDePago() {
        let now = at(11, 20, 18)
        var buy = captured(.tr, -150_000, "Test World Fund", at(11, 20, 17), isShop: false)
        // Control: el mismo cargo sin la marca sí es un pago grande.
        #expect(insightKinds(buy, others: [], now: now).contains(.largePayment))
        buy.excludedFromSpending = true
        #expect(insightKinds(buy, others: [], now: now).isEmpty)

        // Poco habitual: tres pagos normales de 40 € al mismo comercio y uno de 130 € (por debajo del umbral de pago grande).
        let usual = [at(10, 1, 10), at(10, 8, 10), at(10, 15, 10)].map { captured(.tr, -4000, "Fondo X", $0, isShop: false) }
        var unusual = captured(.tr, -13_000, "Fondo X", at(11, 20, 17), isShop: false)
        #expect(insightKinds(unusual, others: usual, now: now).contains(.unusualPayment))
        unusual.excludedFromSpending = true
        #expect(insightKinds(unusual, others: usual, now: now).isEmpty)

        // Cobro duplicado: dos cargos iguales con minutos de diferencia.
        let first = captured(.tr, -13_000, "Fondo Y", at(11, 20, 16, 55), isShop: false)
        var second = captured(.tr, -13_000, "Fondo Y", at(11, 20, 17, 0), isShop: false)
        #expect(insightKinds(second, others: [first], now: now).contains(.duplicateCharge))
        second.excludedFromSpending = true
        #expect(insightKinds(second, others: [first], now: now).isEmpty)

        // Suscripción: una compra mensual del mismo fondo, con cambio de importe, no es una suscripción.
        var oct = captured(.tr, -15_100, "Fondo Z", at(10, 20, 10), isShop: false)
        var nov = captured(.tr, -17_100, "Fondo Z", at(11, 20, 10), isShop: false)
        #expect(insightKinds(nov, others: [oct], now: now).contains(.subscriptionPriceChange))
        oct.excludedFromSpending = true
        nov.excludedFromSpending = true
        #expect(insightKinds(nov, others: [oct], now: now).isEmpty)
    }

    // MARK: R40 — ventas de valores, veto de pareja, cubos por día y `linkedAt`

    @Test func r40UnaVentaDeValoresNuncaEsIngresoGrande() {
        let now = at(11, 20, 18)
        var sale = Movement(bank: .tr, amountCents: 150_000, merchant: "Test World Fund", kind: .income,
                            source: .statement, date: at(11, 20, 17), statementRef: "tr|sell-1", bankStatus: .booked)
        func kinds(_ m: Movement) -> Set<InsightKind> {
            let state = LedgerState(movements: [m])
            return Set(immediateAlerts(afterStoring: m, in: state, now: now, calendar: madrid).map(\.kind)
                + insights(for: state, now: now, calendar: madrid).map(\.kind))
        }
        // Control: el mismo ingreso sin la marca sí es un ingreso grande.
        #expect(kinds(sale).contains(.largeIncome))
        sale.excludedFromSpending = true
        #expect(!kinds(sale).contains(.largeIncome))
    }

    @Test func r40FilaConTextoDeOperacionQueNoEsDeTarjetaNoEsPareja() {
        func isTwin(_ text: String?, notMine: Bool = false) -> Bool {
            let cap = captured(.rev, -5000, "Restaurante Lua", at(11, 20, 14))
            var row = bankRow(.rev, -5200, text, at(11, 20), ref: "b-1", importedAt: at(11, 20, 17))
            row.flaggedNotMine = notMine
            return probableTwinCaptureIDs(in: [cap, row]) == [cap.id]
        }
        #expect(isTwin("Restaurante Lua"))
        #expect(isTwin(nil))
        for text in ["Recibo luz", "RECIBO DE GAS", "Domiciliación seguro", "domiciliacion agua", "Adeudo cuota",
                     "Transferencia de Ana", "Traspaso a ahorro", "Bizum de Luis", "Cajero Gran Via", "Comisión de mantenimiento",
                     "comision tarjeta"] {
            #expect(!isTwin(text), "\(text)")
        }
        // Palabra entera: «Recibos» o «Bizumeria» no son las palabras de la lista.
        #expect(isTwin("Bar Los Recibos"))
        #expect(isTwin("Bizumeria Lua"))
        // Una fila marcada «no es mío» tampoco.
        #expect(!isTwin("Restaurante Lua", notMine: true))
    }

    @Test func r40LaBusquedaDeParejaPorCubosDaElMismoResultado() {
        // Tres bancos y varios días: cada capturado solo se empareja con filas de su banco y a un día de Madrid o menos.
        let a = captured(.rev, -5000, "A", at(11, 10, 23, 50))
        let b = captured(.rev, -2000, "B", at(11, 14, 0, 10))
        let c = captured(.ima, -3000, "C", at(11, 14, 12))
        let d = captured(.rev, -4000, "D", at(11, 18, 12))
        let rowA = bankRow(.rev, -5100, "A", at(11, 11), ref: "ra", importedAt: at(11, 19))   // un día después de A
        let rowB = bankRow(.rev, -2100, "B", at(11, 13), ref: "rb", importedAt: at(11, 19))   // un día antes de B
        let rowC = bankRow(.rev, -3000, "C", at(11, 14), ref: "rc", importedAt: at(11, 19))   // otro banco que C
        let rowD = bankRow(.rev, -4000, "D", at(11, 20), ref: "rd", importedAt: at(11, 21))   // dos días después de D
        #expect(probableTwinCaptureIDs(in: [a, b, c, d, rowA, rowB, rowC, rowD]) == [a.id, b.id])
    }

    @Test func r40CapturadoEnlazadoPorLaMismaConsultaQueLaLecturaNoSeSumaDeNuevo() throws {
        let capture = captured(.rev, -1250, "Cafe", at(11, 20, 13, 3))
        let record = BankRecord(ref: "t-1", bank: .rev, amountCents: -1250, timing: .transactionDay(at(11, 20)),
                                status: .booked, merchant: "CAFE")
        // La consulta de las 13:10 trae la fila (enlaza el capturado) y una lectura de 100,00 € de las 13:00.
        var same = Ledger(state: LedgerState(movements: [capture]))
        _ = same.reconcile([record], bank: .rev, channel: .bank, coverage: nil, now: at(11, 20, 13, 10), calendar: madrid)
        #expect(same.state.movements[0].linkedAt == at(11, 20, 13, 10))
        #expect(same.state.movements[0].importedAt == nil)
        #expect(!same.state.movements[0].isHistorical)
        same.adoptBalance(.rev, cents: 10_000, at: at(11, 20, 13, 0), origin: .bank, fetchedAt: at(11, 20, 13, 10))
        let exact = try #require(same.balance(.rev))
        #expect(exact.cents == 10_000 && !exact.estimated)
        // Enlazado por una consulta POSTERIOR a la lectura: la lectura no lo incluía, sigue contando (estimado).
        var later = Ledger(state: LedgerState(movements: [capture]))
        _ = later.reconcile([record], bank: .rev, channel: .bank, coverage: nil, now: at(11, 20, 13, 20), calendar: madrid)
        later.adoptBalance(.rev, cents: 10_000, at: at(11, 20, 13, 0), origin: .bank, fetchedAt: at(11, 20, 13, 10))
        let estimated = try #require(later.balance(.rev))
        #expect(estimated.cents == 8750 && estimated.estimated)
        // Sin `linkedAt` (libros anteriores) rige `importedAt`, que un capturado no tiene: cuenta como antes.
        var old = same
        old.state.movements[0].linkedAt = nil
        #expect(old.balance(.rev)?.cents == 8750)
        // El campo viaja en la copia de seguridad y los libros sin él se leen.
        let back = try decodeBackup(try encodeBackup(same.state, exportedAt: at(11, 21))).ledger
        #expect(back.movements[0].linkedAt == at(11, 20, 13, 10))
        let plain = try JSONEncoder().encode(old.state.movements[0])
        #expect(try JSONDecoder().decode(Movement.self, from: plain).linkedAt == nil)
    }

    // MARK: R35 — un capturado con pareja probable en una fila del banco no suma desde el primer día

    private func countedCents(_ state: LedgerState, now: Date) -> [Int] {
        spendingMovements(in: state.movements, notSpending: spendingExclusions(in: state, now: now)).map(\.amountCents).sorted()
    }

    @Test func r35PropinaCuentaLaFilaDelBancoYaElMismoDia() {
        let now = at(11, 20, 18)
        let tip = captured(.rev, -5000, "Restaurante Lua", at(11, 20, 14))
        let row = bankRow(.rev, -5500, "RESTAURANTE LUA", at(11, 20), ref: "b-1", importedAt: at(11, 20, 17))
        let state = LedgerState(movements: [tip, row])
        // Sin conexión ni extracto: la definición de 7 días no aplica, pero para el gasto ya es pareja.
        #expect(unconfirmedCaptureIDs(in: state, now: now).isEmpty)
        #expect(probableTwinCaptureIDs(in: state.movements) == [tip.id])
        #expect(countedCents(state, now: now) == [-5500])
        #expect(monthSpending(in: state, month: now, now: now, calendar: madrid).totalCents == 5500)
        // Un día de diferencia (Madrid) sigue valiendo; dos, no.
        let nextDay = bankRow(.rev, -5500, "RESTAURANTE LUA", at(11, 21), ref: "b-2", importedAt: at(11, 21, 9))
        #expect(probableTwinCaptureIDs(in: LedgerState(movements: [tip, nextDay]).movements) == [tip.id])
        let twoDays = bankRow(.rev, -5500, "RESTAURANTE LUA", at(11, 22), ref: "b-3", importedAt: at(11, 22, 9))
        #expect(probableTwinCaptureIDs(in: [tip, twoDays]).isEmpty)
        // Otro banco: nunca.
        let otherBank = bankRow(.ima, -5500, "RESTAURANTE LUA", at(11, 20), ref: "b-4", importedAt: at(11, 20, 17))
        #expect(probableTwinCaptureIDs(in: [tip, otherBank]).isEmpty)
    }

    @Test func r35DosPagosSinRelacionCuentanLosDos() {
        let now = at(11, 20, 18)
        let cap = captured(.rev, -5000, "Gasolinera", at(11, 20, 9))
        let row = bankRow(.rev, -8000, "Zara", at(11, 20), ref: "b-1", importedAt: at(11, 20, 17), isShop: true)
        #expect(countedCents(LedgerState(movements: [cap, row]), now: now) == [-8000, -5000])
    }

    @Test func r35LimitesDelImporteYRegla7Dias() {
        let cap = captured(.rev, -15_000, "Hotel", at(11, 10, 20))
        let row = bankRow(.rev, -4300, "Bolt", at(11, 10), ref: "b-1", importedAt: at(11, 11, 8))
        // Los límites: -5 % y +30 % del importe del capturado.
        func twin(_ cents: Int, of capture: Int = -10_000) -> Bool {
            let c = captured(.rev, capture, "X", at(11, 10, 20))
            let r = bankRow(.rev, cents, "Y", at(11, 10), ref: "b-9", importedAt: at(11, 11, 8))
            return probableTwinCaptureIDs(in: [c, r]) == [c.id]
        }
        #expect(twin(-9500) && twin(-13_000) && twin(-10_000))
        #expect(!twin(-9499) && !twin(-13_001))
        // 150,00 € frente a 43,00 €: no son pareja; ambos cuentan el primer día...
        let day0 = at(11, 10, 22)
        var info = BankLinkInfo(connectedAt: at(10, 1), consentValidUntil: at(12, 31))
        info.lastSuccessAt = at(11, 10, 21)
        let early = LedgerState(movements: [cap, row], links: [.rev: info])
        #expect(countedCents(early, now: day0) == [-15_000, -4300])
        // ...hasta que la regla de 7 días saca al capturado.
        info.lastSuccessAt = at(11, 20, 8)
        let later = LedgerState(movements: [cap, row], links: [.rev: info])
        #expect(unconfirmedCaptureIDs(in: later, now: at(11, 20, 18)) == [cap.id])
        #expect(countedCents(later, now: at(11, 20, 18)) == [-4300])
    }

    @Test func r35UnoAUnoYElImporteMasCercanoPrimero() {
        let now = at(11, 20, 18)
        let a = captured(.rev, -5000, "Bar A", at(11, 20, 10))
        let b = captured(.rev, -5200, "Bar B", at(11, 20, 11))
        let row = bankRow(.rev, -5300, "BAR", at(11, 20), ref: "b-1", importedAt: at(11, 20, 17))
        // Una sola fila: solo se lleva uno, el de importe más cercano (52,00 €).
        #expect(probableTwinCaptureIDs(in: [a, b, row]) == [b.id])
        #expect(countedCents(LedgerState(movements: [a, b, row]), now: now) == [-5300, -5000])
        // Dos filas, dos capturados: cada uno con la suya.
        let row2 = bankRow(.rev, -5100, "BAR", at(11, 20), ref: "b-2", importedAt: at(11, 20, 17))
        #expect(probableTwinCaptureIDs(in: [a, b, row, row2]) == [a.id, b.id])
        #expect(countedCents(LedgerState(movements: [a, b, row, row2]), now: now) == [-5300, -5100])
    }

    @Test func r35UnTraspasoOUnaOperacionDeValoresNuncaEsPareja() {
        let now = at(11, 20, 18)
        let cap = captured(.rev, -5000, "Restaurante Lua", at(11, 20, 14))
        var transferLeg = bankRow(.rev, -5500, "Envio", at(11, 20), ref: "b-1", importedAt: at(11, 20, 17))
        transferLeg.ownTransfer = true
        #expect(probableTwinCaptureIDs(in: [cap, transferLeg], skipping: ownTransferIDs(in: [cap, transferLeg])).isEmpty)
        #expect(countedCents(LedgerState(movements: [cap, transferLeg]), now: now) == [-5000])
        var trade = bankRow(.rev, -5500, "Fondo", at(11, 20), ref: "b-2", importedAt: at(11, 20, 17))
        trade.excludedFromSpending = true
        #expect(probableTwinCaptureIDs(in: [cap, trade]).isEmpty)
        #expect(countedCents(LedgerState(movements: [cap, trade]), now: now) == [-5000])
    }

    @Test func r35UnCapturadoYaEnlazadoNuncaSeEmpareja() {
        var linked = captured(.rev, -5000, "Restaurante Lua", at(11, 20, 14))
        linked.bankRef = "b-0"
        let row = bankRow(.rev, -5500, "RESTAURANTE LUA", at(11, 20), ref: "b-1", importedAt: at(11, 20, 17))
        #expect(probableTwinCaptureIDs(in: [linked, row]).isEmpty)
    }

    // MARK: Ronda de la revisión de la integración

    @Test func traspasoPrefiereLaContraparteConHoraAUnaFilaDeSoloDia() {
        // Pago con hora a las 12:30; ingreso de otro banco a las 12:32 y fila de solo día (mediodía) de un tercer banco.
        let pay = captured(.rev, -30_000, "Envio", at(11, 10, 12, 30), isShop: false)
        let precise = captured(.ima, 30_000, "Abono", at(11, 10, 12, 32), isShop: false)
        let dayOnly = bankRow(.tr, 30_000, "Abono", at(11, 10), ref: "t-1", importedAt: at(11, 11, 8))
        let pairs = ownTransferPairs(in: [pay, precise, dayOnly])
        #expect(pairs == [OwnTransferPair(paymentID: pay.id, incomeID: precise.id)])
    }

    @Test func categoriaDelComercioNoSePierdeSiCambiaLaClaveAlFusionarUnAvisoTardio() {
        let bankName = "Zxq Shop Centro"
        let row = Movement(bank: .rev, amountCents: -1250, merchant: bankName, kind: .payment, source: .bank,
                           date: at(11, 20), bankRef: "b-1", bankStatus: .booked, importedAt: at(11, 20, 9), dayOnly: true)
        var l = Ledger(state: LedgerState(movements: [row], categoryOverrides: [normalizeMerchant(bankName): .ocio]))
        let outcome = l.ingest(.wallet(bank: .rev, amount: "12,50", merchant: "Zxq"), now: at(11, 20, 14))
        guard case .merged(let merged) = outcome else { Issue.record("esperaba .merged: \(outcome)"); return }
        #expect(normalizeMerchant(merged.merchant ?? "") != normalizeMerchant(bankName))
        #expect(merged.category == .ocio)
        #expect(categoryOf(merged, in: l.state, subscriptionKeys: []) == .ocio)
    }
}
