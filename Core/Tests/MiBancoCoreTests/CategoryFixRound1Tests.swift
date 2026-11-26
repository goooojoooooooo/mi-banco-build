import Foundation
import Testing
@testable import MiBancoCore

// Ronda de arreglos 1 de «comercios y señal de pago a persona» (revisión categorias-revision.md).

private let madrid: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Madrid")!
    return c
}()

private func at(_ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    madrid.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}

private func category(_ m: Movement) -> SpendingCategory? {
    spendingCategory(of: m, overrides: [:], subscriptionKeys: [])
}

private func pay(_ merchant: String?, isShop: Bool = false, personPayment: Bool? = nil,
                 source: Movement.Source = .notification) -> Movement {
    Movement(bank: .ima, amountCents: -1_500, merchant: merchant, kind: .payment, source: source, date: at(11, 18),
             isShop: isShop, personPayment: personPayment)
}

private func stored(_ outcome: IngestOutcome) -> Movement? {
    switch outcome {
    case .stored(let m), .merged(let m): m
    default: nil
    }
}

private func notice(_ body: String, title: String? = nil) -> ParsedMovement? {
    if case .movement(let m) = parseNotification(bank: .ima, title: title, subtitle: nil, body: body) { return m }
    return nil
}

private func debit(_ amount: String, creditor: String? = nil, mcc: String? = nil, remittance: [String]? = nil,
                   code: EBBankTransactionCode? = nil, entry: String) -> EBTransaction {
    EBTransaction(transactionAmount: EBAmount(currency: "EUR", amount: amount), creditDebitIndicator: "DBIT", status: .book,
                  entryReference: entry, transactionDate: "2026-11-18", remittanceInformation: remittance,
                  creditor: creditor.map { EBParty(name: $0) }, merchantCategoryCode: mcc, bankTransactionCode: code)
}

private func records(_ list: [EBTransaction]) -> [BankRecord] {
    bankRecords(from: list, bank: .ima, calendar: madrid)
}

private func record(_ ref: String, _ cents: Int, status: BankStatus, merchant: String? = nil,
                    personPayment: Bool = false) -> BankRecord {
    BankRecord(ref: ref, bank: .ima, amountCents: cents, timing: .transactionDay(at(11, 18)), status: status,
               merchant: merchant, personPayment: personPayment)
}

private func captured(_ cents: Int, _ merchant: String, _ date: Date) -> Movement {
    Movement(bank: .ima, amountCents: cents, merchant: merchant, kind: .payment, source: .notification, date: date,
             fingerprint: "fp\(cents)\(date.timeIntervalSince1970)")
}

private func run(_ l: inout Ledger, _ list: [BankRecord], coverage: DateInterval? = nil, now: Date = at(11, 20)) {
    _ = l.reconcile(list, bank: .ima, channel: .bank, coverage: coverage, now: now, calendar: madrid)
}

private let revolutHeader = "Type,Product,Started Date,Completed Date,Description,Amount,Fee,Currency,State,Balance"

@Suite struct CategoryFixRound1Tests {
    // MARK: I-1: pagar CON Bizum EN un comercio no es pagar a una persona

    @Test func bizumEnUnComercioNoEsPersona() throws {
        let parsed = try #require(notice("Has pagado 12,00 € con Bizum en Bar Pepe"))
        #expect(parsed.merchant == "Bar Pepe")
        #expect(!parsed.personPayment)
        var l = Ledger(state: LedgerState())
        let m = try #require(stored(l.ingest(.notification(bank: .ima, title: nil, subtitle: nil,
                                                           body: "Has pagado 12,00 € con Bizum en Bar Pepe"), now: at(11, 18))))
        #expect(m.personPayment == nil)
        #expect(category(m) == .comerFuera)
        #expect(notice("Paid €5.00 via transfer at Pophams Bakery").map(\.personPayment) == false)
        // El envío a alguien sigue dando la señal.
        #expect(notice("Has enviado un Bizum de 15,00 € a Ana")?.personPayment == true)
    }

    // MARK: I-2: la fusión de un pendiente desaparecido conserva el true

    @Test func laFusionDeUnPendienteDesaparecidoConservaElTrue() throws {
        let capture = captured(-1_500, "Ana", at(11, 18, 10, 5))
        var l = Ledger(state: LedgerState(movements: [capture]))
        let coverage = DateInterval(start: at(11, 10, 0), end: at(11, 20, 0))
        let pending = record("p1", -1_500, status: .pending)
        let booked = record("b1", -1_500, status: .booked, merchant: "Ana Lopez", personPayment: true)
        run(&l, [pending, booked], coverage: coverage)
        #expect(l.state.movements.count == 2)
        run(&l, [booked], coverage: coverage)
        #expect(l.state.movements.count == 1)
        let m = try #require(l.state.movements.first)
        #expect(m.id == capture.id)
        #expect(m.bankRef == "b1")
        #expect(m.personPayment == true)
        #expect(category(m) == .personas)
    }

    // MARK: M-7: el true entra también por los pasos 1 y 2 de la reconciliación

    @Test func elPaso1AnadeElTrue() throws {
        let capture = captured(-1_500, "Ana", at(11, 18, 10, 5))
        var l = Ledger(state: LedgerState(movements: [capture]))
        run(&l, [record("x1", -1_500, status: .booked)])
        #expect(l.state.movements.first?.personPayment == nil)
        run(&l, [record("x1", -1_500, status: .booked, personPayment: true)])
        let m = try #require(l.state.movements.first)
        #expect(m.bankRef == "x1")
        #expect(m.personPayment == true)
    }

    @Test func elPaso2AnadeElTrue() throws {
        let capture = captured(-1_500, "Ana", at(11, 18, 10, 5))
        var l = Ledger(state: LedgerState(movements: [capture]))
        run(&l, [record("p1", -1_500, status: .pending)])
        #expect(l.state.movements.first?.bankStatus == .pending)
        run(&l, [record("b2", -1_500, status: .booked, personPayment: true)])
        #expect(l.state.movements.count == 1)
        let m = try #require(l.state.movements.first)
        #expect(m.bankRef == "b2")
        #expect(m.bankStatus == .booked)
        #expect(m.personPayment == true)
    }

    // MARK: I-3: conceptos y facturas antes que la persona; locales después

    @Test func conceptosYFacturasGananALaPersona() {
        #expect(category(pay("TRANSFERENCIA ALQUILER NOVIEMBRE", source: .bank)) == .casa)
        #expect(category(pay("TRANSF COMUNIDAD PROPIETARIOS", source: .bank)) == .casa)
        #expect(category(pay("Transfer Aeropuerto Málaga")) == .viajes)
        #expect(category(pay("Transferencia seguro hogar", source: .bank)) == .casa)
        #expect(category(pay("Bizum farmacia guardia")) == .salud)
        // Con la señal del campo pasa lo mismo.
        #expect(category(pay("Comunidad Propietarios", personPayment: true)) == .casa)
    }

    @Test func losLocalesVanDespuesDeLaPersona() {
        #expect(category(pay("Bizum a Juan Horno")) == .personas)
        #expect(category(pay("Transferencia a Ana Café")) == .personas)
        #expect(category(pay("Juan Horno", personPayment: true)) == .personas)
        #expect(category(pay("Bizum a Pilar Moda")) == .personas)
        // «luz» es también un nombre: en un pago a persona no se lee como la factura.
        #expect(category(pay("Bizum a Mari Luz")) == .personas)
        #expect(category(pay("Luz Martínez", personPayment: true)) == .personas)
    }

    @Test func sinPersonaElOrdenDeLasPalabrasClaveNoCambia() {
        // A igual número de palabras gana la lista que va antes (comer fuera antes que viajes), como antes.
        #expect(category(pay("Bar Aeropuerto")) == .comerFuera)
        #expect(category(pay("Panadería Hospital")) == .supermercado)
        #expect(category(pay("Recibo luz noviembre")) == .casa)
    }

    // MARK: I-4 y M-4: el concepto y el tipo de operación de Enable Banking dan la señal

    @Test func laRemesaDeEnableBankingDaLaSenal() {
        let out = records([
            debit("15.00", creditor: "ANA LOPEZ", remittance: ["BIZUM ENVIADO"], entry: "r1"),
            debit("20.00", creditor: "ANA LOPEZ", remittance: ["TRANSFERENCIA A FAVOR DE ANA LOPEZ"], entry: "r2"),
            debit("9.00", creditor: "BAR PEPE", mcc: "5812", remittance: ["Bizum"], entry: "r3"),
            debit("7.00", creditor: "ANA LOPEZ", remittance: ["Cena viernes"], entry: "r4"),
        ])
        #expect(out.map(\.personPayment) == [true, true, false, false])
        // El comercio sigue siendo el acreedor (la remesa no se guarda).
        #expect(out[0].merchant == cleanBankMerchant("ANA LOPEZ"))
        #expect(out[2].isShop)

        var l = Ledger(state: LedgerState())
        run(&l, out)
        let byRef = Dictionary(uniqueKeysWithValues: l.state.movements.map { ($0.bankRef ?? "", $0) })
        #expect(byRef["r1"].flatMap { category($0) } == .personas)
        #expect(byRef["r2"].flatMap { category($0) } == .personas)
        #expect(byRef["r3"].flatMap { category($0) } == .comerFuera)
        #expect(byRef["r4"].flatMap { category($0) } == .sinCategoria)
    }

    @Test func elTipoDeOperacionDaLaSenal() {
        let out = records([
            debit("15.00", creditor: "ANA LOPEZ", code: EBBankTransactionCode(description: nil, code: "ICDT", subCode: "ESCT"),
                  entry: "c1"),
            debit("15.00", creditor: "ANA LOPEZ", code: EBBankTransactionCode(description: "Bizum enviado", code: nil, subCode: nil),
                  entry: "c2"),
            debit("15.00", creditor: "HORNO SAN JUAN", code: EBBankTransactionCode(description: "Compra tarjeta", code: "CCRD",
                                                                                     subCode: "POSD"), entry: "c3"),
        ])
        #expect(out.map(\.personPayment) == [true, true, false])
    }

    @Test func elTipoDeOperacionSeLeeSiLlega() throws {
        func decode(_ extra: String) throws -> EBTransaction {
            let json = """
            {"transaction_amount":{"currency":"EUR","amount":"15.00"},"credit_debit_indicator":"DBIT","status":"BOOK",
            "transaction_date":"2026-11-18","creditor":{"name":"ANA LOPEZ"}\(extra)}
            """
            return try JSONDecoder().decode(EBTransaction.self, from: Data(json.utf8))
        }
        let object = try decode(#","bank_transaction_code":{"description":"Transferencia","code":"ICDT","sub_code":"ESCT"}"#)
        #expect(object.bankTransactionCode == EBBankTransactionCode(description: "Transferencia", code: "ICDT", subCode: "ESCT"))
        #expect(try decode("").bankTransactionCode == nil)
        #expect(try decode(#","bank_transaction_code":null"#).bankTransactionCode == nil)
        // Un banco que lo mande con otra forma no rompe la descarga.
        #expect(try decode(#","bank_transaction_code":"PMNT-ICDT-ESCT""#).bankTransactionCode?.description == "PMNT-ICDT-ESCT")
        #expect(try decode(#","bank_transaction_code":{"code":7}"#).bankTransactionCode?.code == nil)
    }

    // MARK: M-10: sin código de comercio, una marca en el nombre no tapa la señal

    @Test func unaMarcaEnElNombreNoTapaLaSenal() throws {
        let out = records([
            debit("15.00", creditor: "ZARA LOPEZ", remittance: ["BIZUM ENVIADO"], entry: "z1"),
            debit("15.00", creditor: "ZARA LOPEZ", entry: "z2"),
            debit("15.00", creditor: "ZARA LOPEZ", mcc: "5651", remittance: ["BIZUM ENVIADO"], entry: "z3"),
        ])
        #expect(out[0].isShop == false)
        #expect(out[0].personPayment)
        // Sin señal, como antes: el alias de la marca la hace tienda.
        #expect(out[1].isShop)
        // Con código de comercio de tienda, manda la tienda.
        #expect(out[2].isShop)
        #expect(!out[2].personPayment)

        // Aviso de Bizum «a Zara» y después el registro del banco sin código ni concepto: el aviso no pierde la señal.
        var l = Ledger(state: LedgerState())
        let capture = try #require(stored(l.ingest(.notification(bank: .ima, title: nil, subtitle: nil,
                                                                 body: "Has enviado un Bizum de 15,00 € a Zara"), now: at(11, 18, 10))))
        run(&l, [out[1]], now: at(11, 18, 18))
        let linked = try #require(l.state.movements.first { $0.id == capture.id })
        #expect(linked.bankRef == "z2")
        #expect(linked.isShop == false)
        #expect(category(linked) == .personas)
    }

    // MARK: M-1: traspasos a tus bolsillos, huchas y cuentas no son personas

    @Test func losBolsillosDeRevolutNoSonPersonas() throws {
        let csv = [
            revolutHeader,
            "Transfer,Current,2026-11-16 10:00:00,2026-11-16 10:00:01,To USD,-20.00,0.00,EUR,COMPLETED,240.20",
            "Transfer,Current,2026-11-16 11:00:00,2026-11-16 11:00:01,To EUR Savings,-30.00,0.00,EUR,COMPLETED,210.20",
            "Transfer,Current,2026-11-16 12:00:00,2026-11-16 12:00:01,To pocket EUR Vacaciones,-10.00,0.00,EUR,COMPLETED,200.20",
            "Transfer,Current,2026-11-16 13:00:00,2026-11-16 13:00:01,To Ana,-15.00,0.00,EUR,COMPLETED,185.20",
        ].joined(separator: "\n") + "\n"
        let parsed = try parseStatement(Data(csv.utf8), expected: .rev, now: at(11, 20), calendar: madrid)
        #expect(parsed.records.map(\.personPayment) == [false, false, false, true])
        var l = Ledger(state: LedgerState())
        _ = l.reconcile(parsed.records, bank: .rev, channel: .statement, coverage: nil, now: at(11, 20), calendar: madrid)
        let usd = try #require(l.state.movements.first { $0.amountCents == -2_000 })
        #expect(category(usd) == .sinCategoria)
        let ana = try #require(l.state.movements.first { $0.amountCents == -1_500 })
        #expect(category(ana) == .personas)
    }

    @Test func traspasosAHuchaYAhorroNoSonPersonas() {
        #expect(category(pay("Traspaso a cuenta ahorro")) == .sinCategoria)
        #expect(category(pay("Traspaso a hucha")) == .sinCategoria)
        #expect(category(pay("Transferencia a Ahorros", source: .bank)) == .sinCategoria)
        #expect(category(pay("Hucha", personPayment: true)) == .sinCategoria)
        // A una persona, sigue siendo Personas.
        #expect(category(pay("Transferencia a Laura")) == .personas)
        #expect(category(pay("Traspaso a Juan")) == .personas)
    }

    // MARK: M-5: una sola lista de palabras de envío y una sola normalización

    @Test func avisoYTextoReconocenLasMismasPalabras() throws {
        for word in ["Bizum", "transferencia", "TRANSF", "traspaso", "Enviado", "Transferencias"] {
            let parsed = try #require(notice("Has pagado 10,00 € a Ana " + word), "«\(word)»")
            #expect(parsed.personPayment, "aviso con «\(word)»")
            #expect(category(pay(word + " a Ana")) == .personas, "texto con «\(word)»")
        }
        // Las dos con las mismas tildes y mayúsculas: «ENVÍO A» y «envio a».
        #expect(category(pay("ENVÍO A LUCÍA")) == .personas)
        #expect(notice("Has pagado 10,00 € a Lucía\nEnvío realizado")?.personPayment == true)
    }

    // MARK: M-6 y M-8: reglas quitadas

    @Test func reglasQuitadas() {
        // «restaurante», «wok» y «bazar» solas siguen dando lo mismo.
        #expect(keywordCategory(for: "Restaurante Chino Gran Muralla") == .comerFuera)
        #expect(keywordCategory(for: "Wok Chino Ming") == .comerFuera)
        #expect(keywordCategory(for: "Bazar Chino Hua") == .compras)
        // «pub» ya no es una palabra clave: aparece abreviado en conceptos de la administración.
        #expect(keywordCategory(for: "TASA ADMON PUB") == nil)
        #expect(keywordCategory(for: "SERV PUB EMPLEO") == nil)
        #expect(keywordCategory(for: "Irish Pub") == nil)
    }
}
