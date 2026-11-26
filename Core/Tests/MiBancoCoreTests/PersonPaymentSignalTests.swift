import Foundation
import Testing
@testable import MiBancoCore

// La señal de pago a persona (`Movement.personPayment`): la dejan el aviso, la sincronización y los extractos cuando
// saben que es un envío, se conserva al enlazar y manda sobre las palabras clave del local.

private let madrid: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Madrid")!
    return c
}()

private func at(_ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    madrid.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}

private func category(_ m: Movement, in state: LedgerState = LedgerState()) -> SpendingCategory? {
    spendingCategory(of: m, overrides: state.categoryOverrides, subscriptionKeys: [])
}

private func stored(_ outcome: IngestOutcome) -> Movement? {
    switch outcome {
    case .stored(let m), .merged(let m): m
    default: nil
    }
}

private func debit(_ amount: String, creditor: String? = nil, mcc: String? = nil, remittance: [String]? = nil,
                   entry: String) -> EBTransaction {
    EBTransaction(transactionAmount: EBAmount(currency: "EUR", amount: amount), creditDebitIndicator: "DBIT", status: .book,
                  entryReference: entry, transactionDate: "2026-11-18", remittanceInformation: remittance,
                  creditor: creditor.map { EBParty(name: $0) }, merchantCategoryCode: mcc)
}

private let revolutHeader = "Type,Product,Started Date,Completed Date,Description,Amount,Fee,Currency,State,Balance"

@Suite struct PersonPaymentSignalTests {
    // MARK: Aviso

    @Test func avisoDeBizumGuardadoComoAnaEsPersonas() throws {
        if case .movement(let parsed) = parseNotification(bank: .ima, title: nil, subtitle: nil,
                                                         body: "Has enviado un Bizum de 15,00 € a Ana") {
            #expect(parsed.personPayment)
            #expect(parsed.merchant == "Ana")
        } else {
            Issue.record("no es un movimiento")
        }
        var l = Ledger(state: LedgerState())
        let m = try #require(stored(l.ingest(.notification(bank: .ima, title: nil, subtitle: nil,
                                                           body: "Has enviado un Bizum de 15,00 € a Ana"), now: at(11, 18))))
        #expect(m.merchant == "Ana")
        #expect(m.personPayment == true)
        #expect(category(m) == .personas)
    }

    @Test func avisoDeTransferenciaYTituloConNombre() throws {
        var l = Ledger(state: LedgerState())
        let a = try #require(stored(l.ingest(.notification(bank: .rev, title: "Laura", subtitle: nil, body: "Has enviado 20,00 €"),
                                             now: at(11, 18))))
        #expect(a.personPayment == true)
        #expect(category(a) == .personas)
    }

    @Test func compraEnTiendaNoLlevaLaSenal() throws {
        var l = Ledger(state: LedgerState())
        let shop = try #require(stored(l.ingest(.notification(bank: .rev, title: nil, subtitle: nil,
                                                              body: "Has pagado 12,50 € en Horno San Juan"), now: at(11, 18))))
        #expect(shop.personPayment == nil)
        #expect(category(shop) == .supermercado)
        // Título de un pago con tarjeta que el directorio no conoce: tampoco es un envío.
        let titled = try #require(stored(l.ingest(.notification(bank: .rev, title: "Horno San Juan", subtitle: nil,
                                                                body: "Has pagado 4,20 €"), now: at(11, 18, 13))))
        #expect(titled.personPayment == nil)
        #expect(category(titled) == .supermercado)
        // Cartera (Apple Pay).
        let wallet = try #require(stored(l.ingest(.wallet(bank: .rev, amount: "3,10", merchant: "Horno San Juan"),
                                                  now: at(11, 18, 15))))
        #expect(wallet.personPayment == nil)
        #expect(category(wallet) == .supermercado)
    }

    @Test func unIngresoNoLlevaLaSenal() {
        if case .movement(let parsed) = parseNotification(bank: .ima, title: nil, subtitle: nil, body: "Bizum de Laura: 20 €") {
            #expect(parsed.kind == .income)
            #expect(!parsed.personPayment)
        } else {
            Issue.record("«Bizum de Laura: 20 €» debería leerse como ingreso")
        }
    }

    // MARK: Sincronización (Enable Banking)

    @Test func mccDeTransferenciaEsPersonas() {
        let records = bankRecords(from: [
            debit("15.00", creditor: "ANA LOPEZ", mcc: "4829", entry: "e1"),
            debit("9.00", creditor: "PEPE SANCHEZ", mcc: "6540", entry: "e2"),
            debit("4.20", creditor: "HORNO SAN JUAN", mcc: "5462", entry: "e3"),
            debit("7.00", creditor: "MANUEL GARCIA", entry: "e4"),
        ], bank: .ima, calendar: madrid)
        #expect(records.map(\.personPayment) == [true, true, false, false])

        var l = Ledger(state: LedgerState())
        _ = l.reconcile(records, bank: .ima, channel: .bank, coverage: nil, now: at(11, 20), calendar: madrid)
        let byRef = Dictionary(uniqueKeysWithValues: l.state.movements.map { ($0.bankRef ?? "", $0) })
        #expect(byRef["e1"]?.personPayment == true)
        #expect(byRef["e1"].flatMap { category($0) } == .personas)
        #expect(byRef["e2"].flatMap { category($0) } == .personas)
        #expect(byRef["e3"]?.personPayment == nil)
        #expect(byRef["e3"].flatMap { category($0) } == .supermercado)
        // Sin código ni palabra: un nombre a secas no prueba nada.
        #expect(byRef["e4"]?.personPayment == nil)
        #expect(byRef["e4"].flatMap { category($0) } == .sinCategoria)
    }

    @Test func unIngresoDelBancoNoLlevaLaSenal() {
        let income = EBTransaction(transactionAmount: EBAmount(currency: "EUR", amount: "15.00"), creditDebitIndicator: "CRDT",
                                   status: .book, entryReference: "c1", transactionDate: "2026-11-18",
                                   debtor: EBParty(name: "ANA LOPEZ"), merchantCategoryCode: "4829")
        #expect(bankRecords(from: [income], bank: .ima, calendar: madrid).map(\.personPayment) == [false])
    }

    // MARK: Extracto de Revolut

    @Test func toAnaDelExtractoDeRevolutEsPersonas() throws {
        let csv = [
            revolutHeader,
            "Transfer,Current,2026-11-16 10:00:00,2026-11-16 10:00:01,To Ana,-15.00,0.00,EUR,COMPLETED,240.20",
            "Card Payment,Current,2026-11-18 13:05:11,2026-11-19 09:00:00,Horno San Juan,-4.20,0.00,EUR,COMPLETED,236.00",
            "Transfer,Current,2026-11-17 08:00:00,2026-11-17 08:00:01,Payment from Ana,30.00,0.00,EUR,COMPLETED,266.00",
        ].joined(separator: "\n") + "\n"
        let parsed = try parseStatement(Data(csv.utf8), expected: .rev, now: at(11, 20), calendar: madrid)
        #expect(parsed.records.map(\.personPayment) == [true, false, false])

        var l = Ledger(state: LedgerState())
        _ = l.reconcile(parsed.records, bank: .rev, channel: .statement, coverage: nil, now: at(11, 20), calendar: madrid)
        let toAna = try #require(l.state.movements.first { $0.amountCents == -1_500 })
        #expect(toAna.personPayment == true)
        #expect(category(toAna) == .personas)
        let horno = try #require(l.state.movements.first { $0.amountCents == -420 })
        #expect(category(horno) == .supermercado)
    }

    // MARK: Conservar la señal al enlazar

    @Test func laReconciliacionConservaElTrue() throws {
        // Aviso de Bizum (señal) + registro del banco sin código: el true se queda.
        var l = Ledger(state: LedgerState())
        let captured = try #require(stored(l.ingest(.notification(bank: .ima, title: nil, subtitle: nil,
                                                                  body: "Has enviado un Bizum de 15,00 € a Ana"), now: at(11, 18, 10))))
        let plain = bankRecords(from: [debit("15.00", creditor: "ANA LOPEZ", entry: "x1")], bank: .ima, calendar: madrid)
        #expect(plain.map(\.personPayment) == [false])
        _ = l.reconcile(plain, bank: .ima, channel: .bank, coverage: nil, now: at(11, 18, 18), calendar: madrid)
        let linked = try #require(l.state.movements.first { $0.id == captured.id })
        #expect(linked.bankRef == "x1")
        #expect(linked.personPayment == true)
        #expect(category(linked) == .personas)

        // Aviso sin señal (solo un nombre en el título) + registro con MCC 4829: el true del banco entra.
        var k = Ledger(state: LedgerState())
        let titled = try #require(stored(k.ingest(.notification(bank: .ima, title: "Ana", subtitle: nil, body: "Has pagado 9,00 €"),
                                                  now: at(11, 18, 10))))
        #expect(titled.personPayment == nil)
        let coded = bankRecords(from: [debit("9.00", creditor: "ANA LOPEZ", mcc: "4829", entry: "x2")], bank: .ima, calendar: madrid)
        _ = k.reconcile(coded, bank: .ima, channel: .bank, coverage: nil, now: at(11, 18, 18), calendar: madrid)
        let joined = try #require(k.state.movements.first { $0.id == titled.id })
        #expect(joined.personPayment == true)

        // Vuelve a llegar el mismo registro sin código: el true no se pierde.
        _ = k.reconcile(bankRecords(from: [debit("9.00", creditor: "ANA LOPEZ", entry: "x2")], bank: .ima, calendar: madrid),
                        bank: .ima, channel: .bank, coverage: nil, now: at(11, 19), calendar: madrid)
        #expect(k.state.movements.first { $0.id == titled.id }?.personPayment == true)
    }

    @Test func elAvisoQueCompletaUnRegistroDelBancoConservaElTrue() throws {
        // Primero llega el registro del banco (MCC 4829) y después el aviso, que lo completa.
        var l = Ledger(state: LedgerState())
        let coded = bankRecords(from: [debit("15.00", creditor: "ANA LOPEZ", mcc: "4829", entry: "y1")], bank: .ima, calendar: madrid)
        _ = l.reconcile(coded, bank: .ima, channel: .bank, coverage: nil, now: at(11, 18, 9), calendar: madrid)
        let merged = try #require(stored(l.ingest(.notification(bank: .ima, title: "Ana", subtitle: nil, body: "Has pagado 15,00 €"),
                                                  now: at(11, 18, 10))))
        #expect(merged.personPayment == true)

        // Al revés: registro sin código y aviso de Bizum.
        var k = Ledger(state: LedgerState())
        _ = k.reconcile(bankRecords(from: [debit("15.00", creditor: "ANA LOPEZ", entry: "y2")], bank: .ima, calendar: madrid),
                        bank: .ima, channel: .bank, coverage: nil, now: at(11, 18, 9), calendar: madrid)
        let fromNotice = try #require(stored(k.ingest(.notification(bank: .ima, title: nil, subtitle: nil,
                                                                    body: "Has enviado un Bizum de 15,00 € a Ana"), now: at(11, 18, 10))))
        #expect(fromNotice.personPayment == true)
        #expect(category(fromNotice) == .personas)
    }

    // MARK: Orden: la señal antes que las palabras del local

    @Test func bizumAJuanHornoEsPersonas() {
        let bizum = Movement(bank: .ima, amountCents: -1_500, merchant: "Bizum a Juan Horno", kind: .payment,
                             source: .notification, date: at(11, 18))
        #expect(category(bizum) == .personas)
        let signalled = Movement(bank: .ima, amountCents: -1_500, merchant: "Juan Horno", kind: .payment,
                                 source: .notification, date: at(11, 18), personPayment: true)
        #expect(category(signalled) == .personas)
    }

    @Test func hornoSanJuanConTarjetaSigueEnSupermercado() {
        let card = Movement(bank: .ima, amountCents: -420, merchant: "Horno San Juan", kind: .payment, source: .bank,
                            date: at(11, 18), isShop: true)
        #expect(category(card) == .supermercado)
        let notShop = Movement(bank: .ima, amountCents: -420, merchant: "Horno San Juan", kind: .payment, source: .bank,
                               date: at(11, 18))
        #expect(category(notShop) == .supermercado)
    }

    @Test func laTiendaMandaSobreLaSenal() {
        // Una señal de tienda (código de comercio de tienda) pesa más que la de envío.
        let m = Movement(bank: .ima, amountCents: -420, merchant: "Horno San Juan", kind: .payment, source: .bank,
                         date: at(11, 18), isShop: true, personPayment: true)
        #expect(category(m) == .supermercado)
    }

    @Test func elDuenoYElDirectorioSiguenGanando() {
        let m = Movement(bank: .ima, amountCents: -1_500, merchant: "Ana", kind: .payment, source: .notification,
                         date: at(11, 18), personPayment: true)
        #expect(spendingCategory(of: m, overrides: ["ana": .ocio], subscriptionKeys: []) == .ocio)
        var own = m
        own.category = .casa
        #expect(category(own) == .casa)
        #expect(spendingCategory(of: m, overrides: [:], subscriptionKeys: ["ana"]) == .suscripciones)
    }

    // MARK: Datos guardados

    @Test func unMovimientoViejoSinElCampoSeLeeBien() throws {
        let json = """
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","bank":"ima","amountCents":-1500,"merchant":"Ana","kind":"payment",
        "source":"notification","date":0,"isShop":false}
        """
        let m = try JSONDecoder().decode(Movement.self, from: Data(json.utf8))
        #expect(m.personPayment == nil)
        #expect(m.merchant == "Ana")
        #expect(category(m) == .sinCategoria)
    }

    @Test func elCampoSeGuardaYSeLee() throws {
        var m = Movement(bank: .ima, amountCents: -1_500, merchant: "Ana", kind: .payment, source: .notification,
                         date: Date(timeIntervalSince1970: 0), personPayment: true)
        let back = try JSONDecoder().decode(Movement.self, from: JSONEncoder().encode(m))
        #expect(back == m)
        #expect(back.personPayment == true)
        // Sin señal, el campo ni se escribe: un libro nuevo sin envíos se guarda igual que antes.
        m.personPayment = nil
        let text = String(decoding: try JSONEncoder().encode(m), as: UTF8.self)
        #expect(!text.contains("personPayment"))
    }

    @Test func unLedgerJsonSinElCampoCargaSinError() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("personPayment-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let json = """
        {"balances":[],"movements":[
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","bank":"ima","amountCents":-1500,"merchant":"Ana","kind":"payment",
        "source":"notification","date":0,"isShop":false,"fingerprint":"f1"},
        {"id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","bank":"rev","amountCents":-1250,"merchant":"Mercadona","kind":"payment",
        "source":"bank","date":60,"isShop":true,"bankRef":"r1","bankStatus":"booked"}
        ],"unread":[]}
        """
        try Data(json.utf8).write(to: dir.appendingPathComponent("ledger.json"))
        let state = try FileStore(directory: dir).load()
        #expect(state.movements.count == 2)
        #expect(state.movements.allSatisfy { $0.personPayment == nil })
        #expect(category(state.movements[1], in: state) == .supermercado)
    }
}
