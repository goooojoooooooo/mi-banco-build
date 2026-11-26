import Foundation
import Testing
@testable import MiBancoCore

@Suite struct LedgerTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func ledgerWithRev() -> Ledger {
        var l = Ledger()
        l.setBalance(.rev, cents: 34020, now: t0)
        return l
    }

    private func notice(_ body: String) -> IngestInput {
        .notification(bank: .rev, title: nil, subtitle: nil, body: body)
    }

    private func isStored(_ o: IngestOutcome) -> Bool {
        if case .stored = o { return true }
        return false
    }

    @Test func pagoRestaDelSaldoManualYEsEstimado() {
        var l = ledgerWithRev()
        let o = l.ingest(notice("Paid €12.50 at Mercadona"), now: t0 + 10)
        #expect(isStored(o))
        #expect(l.balance(.rev)?.cents == 32770)
        #expect(l.balance(.rev)?.estimated == true)
    }

    @Test func saldoDelBancoManda() {
        var l = ledgerWithRev()
        _ = l.ingest(notice("Has pagado 12,50 €\nSaldo: 300,00 €"), now: t0 + 10)
        #expect(l.balance(.rev)?.cents == 30000)
        #expect(l.balance(.rev)?.estimated == false)
        _ = l.ingest(notice("Has pagado 10,00 €"), now: t0 + 600)
        #expect(l.balance(.rev)?.cents == 29000)
        #expect(l.balance(.rev)?.estimated == true)
    }

    @Test func saldoComunicadoSinSaldoManual() {
        var l = Ledger()
        _ = l.ingest(notice("Has pagado 12,50 €\nSaldo: 300,00 €"), now: t0)
        #expect(l.balance(.rev)?.cents == 30000)
        #expect(l.balance(.rev)?.estimated == false)
    }

    @Test func sinSaldoNoHayBalanceNiTotal() {
        var l = Ledger()
        _ = l.ingest(notice("Paid €12.50 at Mercadona"), now: t0)
        #expect(l.balance(.rev) == nil)
        #expect(l.total() == nil)
    }

    @Test func totalSumaLosBancosConSaldo() {
        var l = ledgerWithRev()
        l.setBalance(.ima, cents: 1000, now: t0)
        #expect(l.total() == 35020)
    }

    @Test func duplicadoDeWalletYAvisoDentroDeLaVentana() {
        var l = ledgerWithRev()
        let w = l.ingest(.wallet(bank: .rev, amount: "12,50 €", merchant: "Mercadona"), now: t0 + 10)
        #expect(isStored(w))
        let o = l.ingest(notice("Paid €12.50 at Mercadona"), now: t0 + 100)
        #expect(o == .duplicate)
        #expect(l.balance(.rev)?.cents == 32770)
        #expect(l.state.movements.count == 1)
    }

    @Test func fueraDeLaVentanaSeGuarda() {
        var l = ledgerWithRev()
        _ = l.ingest(.wallet(bank: .rev, amount: "12,50 €", merchant: nil), now: t0 + 10)
        let o = l.ingest(notice("Paid €12.50 at Mercadona"), now: t0 + 250)
        #expect(isStored(o))
    }

    @Test func duplicadoConSaldoActualizaElSaldo() {
        var l = ledgerWithRev()
        _ = l.ingest(.wallet(bank: .rev, amount: "12,50 €", merchant: nil), now: t0 + 10)
        let o = l.ingest(notice("Has pagado 12,50 €\nSaldo: 300,00 €"), now: t0 + 60)
        #expect(o == .duplicate)
        #expect(l.balance(.rev)?.cents == 30000)
        #expect(l.balance(.rev)?.estimated == false)
    }

    @Test func walletNoLegibleVaASinLeer() {
        var l = ledgerWithRev()
        let o = l.ingest(.wallet(bank: .rev, amount: "abc", merchant: nil), now: t0 + 1)
        #expect(o == .unread)
        #expect(l.state.unread.first?.text == "abc")
    }

    @Test func rechazadoSeIgnoraSinRastro() {
        var l = ledgerWithRev()
        let o = l.ingest(notice("Pago rechazado de 12,50 €"), now: t0 + 1)
        #expect(o == .ignored)
        #expect(l.state.movements.isEmpty)
        #expect(l.state.unread.isEmpty)
    }

    // I5: antes "Gana un 2 % TAE" iba a "sin leer"; ahora un aviso sin importe se ignora en silencio.
    @Test func sinImporteSeIgnoraSinRastro() {
        var l = ledgerWithRev()
        let o = l.ingest(notice("Gana un 2 % TAE"), now: t0 + 1)
        #expect(o == .ignored)
        #expect(l.state.unread.isEmpty)
        #expect(l.balance(.rev)?.cents == 34020)
    }

    @Test func importeSinSignoVaASinLeerYNoTocaElSaldo() {
        var l = ledgerWithRev()
        let o = l.ingest(notice("Movimiento en tu cuenta: 12,50 €"), now: t0 + 1)
        #expect(o == .unread)
        #expect(l.state.unread.count == 1)
        #expect(l.balance(.rev)?.cents == 34020)
    }

    @Test func otraMonedaVaASinLeer() {
        var l = ledgerWithRev()
        #expect(l.ingest(notice("Paid $5.00 at Starbucks"), now: t0 + 1) == .unread)
        #expect(l.state.movements.isEmpty)
        #expect(l.balance(.rev)?.cents == 34020)
    }

    @Test func textoSinLeerSeRecortaA500() {
        var l = ledgerWithRev()
        let long = "Movimiento de 12,50 € " + String(repeating: "x", count: 900)
        #expect(l.ingest(notice(long), now: t0 + 1) == .unread)
        #expect(l.state.unread.first?.text.count == 500)
    }

    @Test func mismoAvisoSinLeerRepetidoSeGuardaUnaVez() {
        var l = ledgerWithRev()
        _ = l.ingest(notice("Movimiento en tu cuenta: 12,50 €"), now: t0 + 1)
        #expect(l.ingest(notice("Movimiento en tu cuenta: 12,50 €"), now: t0 + 20) == .duplicate)
        #expect(l.state.unread.count == 1)
    }

    @Test func borrarAvisoSinLeer() throws {
        var l = ledgerWithRev()
        _ = l.ingest(notice("Movimiento en tu cuenta: 12,50 €"), now: t0 + 1)
        let id = try #require(l.state.unread.first?.id)
        l.removeUnread(id: id)
        #expect(l.state.unread.isEmpty)
    }

    // I1: duplicado solo entre fuentes distintas, o el mismo texto repetido en 60 s.
    @Test func carteraYAvisoA90sSonUnMovimiento() {
        var l = ledgerWithRev()
        #expect(isStored(l.ingest(.wallet(bank: .rev, amount: "15,00 €", merchant: "Metro"), now: t0)))
        #expect(l.ingest(notice("Has pagado 15,00 € en Metro"), now: t0 + 90) == .duplicate)
        #expect(l.state.movements.count == 1)
        #expect(l.state.movements.first?.pairedAcrossSources == true)
    }

    @Test func avisoYDespuesCarteraSonUnMovimiento() {
        var l = ledgerWithRev()
        #expect(isStored(l.ingest(notice("Has pagado 15,00 € en Metro"), now: t0)))
        #expect(l.ingest(.wallet(bank: .rev, amount: "15,00 €", merchant: "Metro"), now: t0 + 90) == .duplicate)
        #expect(l.state.movements.count == 1)
    }

    @Test func dosPagosRealesVistosDosVecesSonDos() {
        var l = ledgerWithRev()
        _ = l.ingest(.wallet(bank: .rev, amount: "15,00 €", merchant: "Metro"), now: t0 + 10)
        _ = l.ingest(notice("Has pagado 15,00 € en Metro"), now: t0 + 100)
        _ = l.ingest(.wallet(bank: .rev, amount: "15,00 €", merchant: "Metro"), now: t0 + 110)
        _ = l.ingest(notice("Has pagado 15,00 € en Metro"), now: t0 + 200)
        #expect(l.state.movements.count == 2)
        #expect(l.balance(.rev)?.cents == 34020 - 3000)
    }

    @Test func dosAvisosMismoImporteDistintoTextoSonDos() {
        var l = ledgerWithRev()
        _ = l.ingest(notice("Has pagado 15,00 € en Metro\nSaldo: 325,20 €"), now: t0)
        _ = l.ingest(notice("Has pagado 15,00 € en Metro\nSaldo: 310,20 €"), now: t0 + 30)
        #expect(l.state.movements.count == 2)
    }

    @Test func mismoTextoEn30sEsUnaReentrega() {
        var l = ledgerWithRev()
        _ = l.ingest(notice("Has pagado 15,00 € en Metro"), now: t0)
        #expect(l.ingest(notice("Has  pagado 15,00 €\nen METRO"), now: t0 + 30) == .duplicate)
        #expect(l.state.movements.count == 1)
    }

    @Test func mismoTextoTras120sSonDos() {
        var l = ledgerWithRev()
        _ = l.ingest(notice("Has pagado 15,00 € en Metro"), now: t0)
        #expect(isStored(l.ingest(notice("Has pagado 15,00 € en Metro"), now: t0 + 120)))
        #expect(l.state.movements.count == 2)
    }

    @Test func dosCarterasIgualesSeparadasSonDos() {
        var l = ledgerWithRev()
        _ = l.ingest(.wallet(bank: .rev, amount: "2,55 €", merchant: "Metro"), now: t0)
        #expect(isStored(l.ingest(.wallet(bank: .rev, amount: "2,55 €", merchant: "Metro"), now: t0 + 61)))
        #expect(l.state.movements.count == 2)
    }

    @Test func reentregaDelAvisoYaEmparejadoNoCuenta() {
        var l = ledgerWithRev()
        _ = l.ingest(.wallet(bank: .rev, amount: "15,00 €", merchant: "Metro"), now: t0)
        _ = l.ingest(notice("Has pagado 15,00 € en Metro"), now: t0 + 90)
        #expect(l.ingest(notice("Has pagado 15,00 € en Metro"), now: t0 + 100) == .duplicate)
        #expect(l.state.movements.count == 1)
    }

    @Test func laHuellaNoGuardaElTexto() throws {
        var l = ledgerWithRev()
        _ = l.ingest(notice("Has pagado 15,00 € en Metro"), now: t0)
        let fp = try #require(l.state.movements.first?.fingerprint)
        #expect(!fp.lowercased().contains("metro"))
    }

    @Test func movimientoAntiguoSeLeeSinCamposNuevos() throws {
        let json = """
        {"balances":["rev",{"cents":34020,"setAt":1000000,"fromBank":false}],
         "movements":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","bank":"rev","amountCents":-1250,
                       "merchant":"Mercadona","kind":"payment","source":"wallet","date":1000010}],
         "unread":[]}
        """
        let state = try JSONDecoder().decode(LedgerState.self, from: Data(json.utf8))
        let m = try #require(state.movements.first)
        #expect(m.pairedAcrossSources == false)
        #expect(m.fingerprint == nil)
        #expect(m.amountCents == -1250)
        #expect(Ledger(state: state).balance(.rev)?.cents == 32770)
        let again = try JSONDecoder().decode(LedgerState.self, from: JSONEncoder().encode(state))
        #expect(again == state)
    }

    private func movement(_ cents: Int, _ merchant: String?, _ kind: MovementKind, _ bank: BankID) -> Movement {
        Movement(bank: bank, amountCents: cents, merchant: merchant, kind: kind, source: .notification, date: t0)
    }

    @Test func textoDeAlertaPagoSinSaldo() {
        let a = alertText(for: movement(-1250, "Mercadona", .payment, .rev), balance: nil, estimated: false)
        #expect(a.title == "Has pagado 12,50\u{00A0}€ en Mercadona")
        #expect(a.body == "Saldo de Revolut sin configurar")
    }

    @Test func textoDeAlertaConSaldo() {
        let a = alertText(for: movement(-1250, "Mercadona", .payment, .rev), balance: 32770, estimated: false)
        #expect(a.body == "Te quedan 327,70\u{00A0}€ en Revolut")
    }

    @Test func textoDeAlertaConSaldoEstimado() {
        let a = alertText(for: movement(-1250, "Mercadona", .payment, .rev), balance: 32770, estimated: true)
        #expect(a.body == "Te quedan unos 327,70\u{00A0}€ en Revolut")
    }

    @Test func textoDeAlertaIngreso() {
        let a = alertText(for: movement(3500, "Bizum de Carlos", .income, .ima), balance: nil, estimated: false)
        #expect(a.title == "Has recibido 35,00\u{00A0}€: Bizum de Carlos")
    }

    @Test func textoDeAlertaSinComercio() {
        #expect(alertText(for: movement(-1250, nil, .payment, .rev), balance: nil, estimated: false).title == "Has pagado 12,50\u{00A0}€")
        #expect(alertText(for: movement(3500, nil, .income, .rev), balance: nil, estimated: false).title == "Has recibido 35,00\u{00A0}€")
    }

    @Test func almacenGuardaYCarga() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mibanco-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileStore(directory: dir)
        #expect(try store.load() == LedgerState())
        let outcome = try store.update { l -> IngestOutcome in
            l.setBalance(.rev, cents: 34020, now: Date(timeIntervalSinceReferenceDate: 1_000_000))
            return l.ingest(.wallet(bank: .rev, amount: "12,50 €", merchant: "Mercadona"),
                            now: Date(timeIntervalSinceReferenceDate: 1_000_010))
        }
        #expect(isStored(outcome))
        let loaded = try store.load()
        #expect(loaded.movements.count == 1)
        #expect(Ledger(state: loaded).balance(.rev)?.cents == 32770)
        #expect(try store.update { $0.state } == loaded)
    }

    @Test func carteraConComercioEsTienda() {
        var l = Ledger()
        guard case .stored(let m) = l.ingest(.wallet(bank: .rev, amount: "12,50 €", merchant: "Mercadona"), now: t0) else {
            Issue.record("no se guardó"); return
        }
        #expect(m.isShop)
        guard case .stored(let sinComercio) = l.ingest(.wallet(bank: .ima, amount: "3,00 €", merchant: nil), now: t0 + 500) else {
            Issue.record("no se guardó"); return
        }
        #expect(!sinComercio.isShop)
    }

    @Test func avisoDeEnvioNoEsTienda() {
        var l = Ledger()
        guard case .stored(let m) = l.ingest(.notification(bank: .rev, title: nil, subtitle: nil, body: "Has enviado 20,00 € a Laura"), now: t0) else {
            Issue.record("no se guardó"); return
        }
        #expect(!m.isShop)
        guard case .stored(let p) = l.ingest(.notification(bank: .rev, title: nil, subtitle: nil, body: "Has pagado 9,99 € en Netflix"), now: t0 + 500) else {
            Issue.record("no se guardó"); return
        }
        #expect(p.isShop)
    }

    @Test func jsonAntiguoSinIsShopEsFalse() throws {
        let json = #"{"id":"7C9E6679-7425-40DE-944B-E07FC1F90AE7","bank":"rev","amountCents":-1250,"merchant":"Mercadona","kind":"payment","source":"wallet","date":1000010}"#
        let m = try JSONDecoder().decode(Movement.self, from: Data(json.utf8))
        #expect(m.isShop == false)
    }

    // MARK: Ronda U0–U68 (U56)

    @Test func bienvenidaSoloConLibroVacioDeVerdad() {
        struct ReadFail: Error {}
        let failed = onboardingDecision(load: .failure(ReadFail()), onboardingDone: false)
        #expect(failed.startSession == false)
        #expect(failed.markDone == false)

        let empty = onboardingDecision(load: .success(LedgerState()), onboardingDone: false)
        #expect(empty.startSession == true)
        #expect(empty.markDone == false)

        var withData = LedgerState()
        withData.balances[.rev] = ManualBalance(cents: 10_000, setAt: t0, origin: .manual)
        let populated = onboardingDecision(load: .success(withData), onboardingDone: false)
        #expect(populated.startSession == false)
        #expect(populated.markDone == true)

        let alreadyDone = onboardingDecision(load: .success(LedgerState()), onboardingDone: true)
        #expect(alreadyDone.startSession == false)
        #expect(alreadyDone.markDone == false)
    }
}
