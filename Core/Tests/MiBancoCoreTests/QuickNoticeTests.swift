import Foundation
import Testing
@testable import MiBancoCore

@Suite struct QuickNoticeTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_800_000_000)

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    // MARK: Saneado y topes SEC-11

    @Test func saneaControlesBidiYConservaEspaciosDurosYZWJ() {
        let dirty = "Revolut\r\nCafé \u{1F9D1}\u{200D}\u{1F373}\u{0000}\u{202E}\u{FEFF}\r🍽️\tPaid 12,50\u{00A0}€\u{200B}\nSaldo disponible: 300,00\u{202F}€\u{0007}\u{2066}"
        let clean = sanitizeQuickNoticeText(dirty)
        #expect(clean == "Revolut\nCafé \u{1F9D1}\u{200D}\u{1F373}\n🍽️\tPaid 12,50\u{00A0}€\nSaldo disponible: 300,00\u{202F}€")
        #expect(!clean.contains("\u{0000}"))
        #expect(!clean.contains("\u{202E}"))
        #expect(!clean.contains("\u{FEFF}"))
        #expect(!clean.contains("\u{200B}"))
        #expect(!clean.contains("\u{0007}"))
        #expect(!clean.contains("\u{2066}"))
    }

    @Test func recortaEntradaCompletaYCamposTrasRepartir() {
        let huge = String(repeating: "a", count: QuickNoticeLimits.rawMaxLength + 500)
        #expect(sanitizeQuickNoticeText(huge).unicodeScalars.count == QuickNoticeLimits.rawMaxLength)

        // Título y cuerpo demasiado largos tras repartir se acotan cada uno a fieldMaxLength (2 000).
        let longTitle = "Tienda " + String(repeating: "T", count: QuickNoticeLimits.fieldMaxLength + 300)
        let longBody = "Paid €5.50 at Shop " + String(repeating: "B", count: QuickNoticeLimits.fieldMaxLength + 300)
        let raw = "Revolut\n\(longTitle)\n\(longBody)"
        guard case let .notification(bank, title, subtitle, body)? = parseQuickNotice(raw) else {
            Issue.record("Se esperaba un IngestInput.notification")
            return
        }
        #expect(bank == .rev)
        #expect(subtitle == nil)
        #expect((title?.unicodeScalars.count ?? 0) <= QuickNoticeLimits.fieldMaxLength)
        #expect((body?.unicodeScalars.count ?? 0) <= QuickNoticeLimits.fieldMaxLength)
    }

    @Test func entradaVaciaOSoloControlesDevuelveNil() {
        for empty in ["", "   \n\t  ", "\u{0000}\u{202E}\u{200B}\u{FEFF}", "\u{200D}  ", "Revolut\n   \n", "Trade Republic"] {
            #expect(parseQuickNotice(empty) == nil, "\(empty.debugDescription)")
        }
    }

    // MARK: Deducción del banco

    @Test func deduceBancoPorCabeceraOPrefijoDeApp() {
        #expect(detectQuickNoticeBank("Revolut\nPophams Bakery\n🍽️ Paid €5.50 at Pophams Bakery") == .rev)
        #expect(detectQuickNoticeBank("Trade Republic\nZara\nHas pagado 49,95 € en Zara") == .tr)
        #expect(detectQuickNoticeBank("imagin\nMercadona\nHas pagado 12,50 € en Mercadona") == .ima)
        #expect(detectQuickNoticeBank("imaginBank\nHas pagado 12,50 € en Mercadona") == .ima)
        #expect(detectQuickNoticeBank("Revolut: Paid €5.50 at Pophams Bakery") == .rev)
        #expect(detectQuickNoticeBank("Trade Republic · Has pagado 12,50 € en Lidl") == .tr)
        #expect(detectQuickNoticeBank("App: Revolut\nMercadona\nHas pagado 12,50 €") == .rev)
        #expect(detectQuickNoticeBank("Pophams Bakery\nHas pagado 5,50 €\nRevolut") == .rev)
    }

    @Test func deduceBancoPorContenidoSinNombreDeApp() {
        #expect(detectQuickNoticeBank("Pophams Bakery\n🍽️ Paid €5.50 at Pophams Bakery\nAvailable balance: €120.40") == .rev)
        #expect(detectQuickNoticeBank("Pophams Bakery\n🍽️ Paid €5.50 at Pophams Bakery\nSaldo disponible: 120,40 €") == .rev)
        #expect(detectQuickNoticeBank("Pophams Bakery\nPaid €5.50 at Pophams Bakery\nSpent today: €14.50") == .rev)
        #expect(detectQuickNoticeBank("Mercadona\nHas pagado 12,50 € en Mercadona\nSpent today: €20.00") == .rev)
        #expect(detectQuickNoticeBank("🍽️ Paid €5.50 at Pophams Bakery") == .rev)

        #expect(detectQuickNoticeBank("Zara\nCard payment of €49.95 at Zara") == .tr)
        #expect(detectQuickNoticeBank("Mercadona\nHas pagado 12,50 € en Mercadona\nSaveback: 0,13 €") == .tr)
        #expect(detectQuickNoticeBank("Lidl\nHas pagado 9,20 € en Lidl\nRound up: 0,80 €") == .tr)
    }

    @Test func noAdivinaBancoConTextoGenericoContraparteOConflicto() {
        // Sin nombre de app ni patrón propio del banco.
        #expect(detectQuickNoticeBank("Has pagado 12,50 € en Mercadona") == nil)
        // El aviso sin banco no se tira: se guarda aparte (ronda 1, I-1).
        if case let .unattributedNotice(text)? = parseQuickNotice("Has pagado 12,50 € en Mercadona") {
            #expect(text == "Has pagado 12,50 € en Mercadona")
        } else {
            Issue.record("Se esperaba un aviso sin banco")
        }

        // La contraparte de un traspaso no identifica el banco emisor.
        #expect(detectQuickNoticeBank("Transferencia a imagin\nHas enviado 50,00 € a imagin") == nil)
        #expect(detectQuickNoticeBank("Transferencia de Revolut\nHas recibido 50,00 € de Revolut") == nil)
        #expect(detectQuickNoticeBank("Has pagado 12,50 € en Imaginarium") == nil)

        // Con cabecera explícita de la app, manda la cabecera sobre la contraparte.
        #expect(detectQuickNoticeBank("Revolut\nTransferencia a imagin\nHas enviado 50,00 € a imagin") == .rev)
        // Una línea de saldo disponible sola NO decide Revolut (ronda 1, I-1): ni en español ni en inglés.
        #expect(detectQuickNoticeBank("Transferencia a imagin\nHas enviado 50,00 € a imagin\nSaldo disponible: 200,00 €") == nil)
        #expect(detectQuickNoticeBank("Mercadona\nHas pagado 12,50 € en Mercadona\nGastado hoy: 20,00 €") == nil)
        #expect(detectQuickNoticeBank("Zara\nHas pagado 49,95 € en Zara\nAvailable balance: €300.00") == nil)

        // Señales enfrentadas de dos bancos sin cabecera explícita -> nil.
        #expect(detectQuickNoticeBank("Saveback: 0,10 €\nSpent today: €14.50") == nil)
    }

    // MARK: Reparto en título y cuerpo e integración con Ledger

    @Test func reparteTituloYCuerpoEnFormatoMultilineaYUnaLinea() {
        let multi = "Revolut\nPophams Bakery\n🍽️ Paid €5.50 at Pophams Bakery\nSaldo disponible: 120,40 €"
        guard case let .notification(bank, title, subtitle, body)? = parseQuickNotice(multi) else {
            Issue.record("No se obtuvo IngestInput para el aviso multilínea")
            return
        }
        #expect(bank == .rev)
        #expect(title == "Pophams Bakery")
        #expect(subtitle == nil)
        #expect(body == "🍽️ Paid €5.50 at Pophams Bakery\nSaldo disponible: 120,40 €")

        let single = "Revolut: 🍽️ Paid €5.50 at Pophams Bakery"
        guard case let .notification(sBank, sTitle, sSubtitle, sBody)? = parseQuickNotice(single) else {
            Issue.record("No se obtuvo IngestInput para el aviso de una línea")
            return
        }
        #expect(sBank == .rev)
        #expect(sTitle == nil)
        #expect(sSubtitle == nil)
        #expect(sBody == "🍽️ Paid €5.50 at Pophams Bakery")
    }

    @Test func primeraLineaConImportePasaAlCuerpoYConservaPagoAPersona() {
        let raw = "Revolut\nHas enviado 20,00 € a Ana\nSaldo disponible: 100,00 €"
        guard let input = parseQuickNotice(raw) else {
            Issue.record("No se obtuvo IngestInput")
            return
        }
        var ledger = Ledger()
        guard case .stored(let m) = ledger.ingest(input, now: t0) else {
            Issue.record("El envío no se guardó")
            return
        }
        #expect(m.bank == .rev)
        #expect(m.amountCents == -2000)
        #expect(m.merchant == "Ana")
        #expect(m.isShop == false)
        #expect(m.personPayment == true)
        #expect(ledger.balance(.rev)?.cents == 10000)
        #expect(ledger.balance(.rev)?.estimated == false)
    }

    @Test func integracionConLedgerActualizaSaldoYMarcaGuia() {
        var ledger = Ledger()
        ledger.setBalance(.rev, cents: 20_000, now: t0 - 60)

        let revolutRaw = """
        Revolut
        Pophams Bakery
        🍽️ Paid €5.50 at Pophams Bakery
        💳 Saldo disponible: 120,40 €
        """
        guard let revInput = parseQuickNotice(revolutRaw) else {
            Issue.record("No se pudo preparar el aviso rápido de Revolut")
            return
        }
        guard case .stored(let revMove) = ledger.ingest(revInput, now: t0) else {
            Issue.record("No se guardó el pago de Revolut")
            return
        }
        #expect(revMove.bank == .rev)
        #expect(revMove.amountCents == -550)
        #expect(revMove.merchant == "Pophams Bakery")
        #expect(revMove.isShop == true)
        #expect(ledger.balance(.rev)?.cents == 12_040)
        #expect(ledger.balance(.rev)?.estimated == false)
        #expect(guideStatus(.revolut, in: ledger.state, now: t0, calendar: utc) == .working(since: t0, last: t0))
        #expect(guideStatus(.tradeRepublic, in: ledger.state, now: t0, calendar: utc) == .notYet)

        // Mismo aviso entrando por el intent clásico dentro de 60 s: se reconoce como duplicado.
        let classic = IngestInput.notification(
            bank: .rev,
            title: "Pophams Bakery",
            subtitle: nil,
            body: "🍽️ Paid €5.50 at Pophams Bakery\n💳 Saldo disponible: 120,40 €"
        )
        #expect(ledger.ingest(classic, now: t0 + 10) == .duplicate)

        // Aviso de Trade Republic sin cabecera explícita (deducido por contenido) marca su guía.
        let trRaw = "Zara\nCard payment of €49.95 at Zara\nSaveback: €0.50"
        guard let trInput = parseQuickNotice(trRaw) else {
            Issue.record("No se pudo preparar el aviso rápido de Trade Republic")
            return
        }
        guard case .stored(let trMove) = ledger.ingest(trInput, now: t0 + 30) else {
            Issue.record("No se guardó el pago de Trade Republic")
            return
        }
        #expect(trMove.bank == .tr)
        #expect(trMove.amountCents == -4_995)
        #expect(trMove.merchant == "Zara")
        #expect(guideStatus(.tradeRepublic, in: ledger.state, now: t0 + 30, calendar: utc) == .working(since: t0 + 30, last: t0 + 30))
    }
}

// MARK: Avisos rápidos, ronda 1

@Suite struct QuickNoticeRound1Tests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_800_000_000)

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    // MARK: I-1 · nunca perder un pago en silencio ni atribuirlo a un banco sin pruebas

    @Test func textoEspanolDeTradeRepublicSinNombreDeAppSeGuardaSinLeerYNoTocaRevolut() {
        let raw = "Zara\nHas pagado 49,95 € en Zara\nSaldo disponible: 300,00 €"
        #expect(detectQuickNoticeBank(raw) == nil)
        guard let input = parseQuickNotice(raw) else {
            Issue.record("El aviso sin banco deducible no debe tirarse")
            return
        }
        guard case let .unattributedNotice(text) = input else {
            Issue.record("Se esperaba un aviso sin banco")
            return
        }
        #expect(text.contains("Zara"))

        var ledger = Ledger()
        ledger.setBalance(.rev, cents: 20_000, now: t0 - 60)
        let revBefore = ledger.balance(.rev)
        #expect(ledger.ingest(input, now: t0) == .unread)
        #expect(ledger.state.unread.count == 1)
        #expect(ledger.state.unread[0].bank == nil)
        #expect(ledger.state.unread[0].text.contains("49,95"))
        #expect(ledger.state.movements.isEmpty)
        // El saldo de Revolut sigue exacto y sin tocar; ninguna guía se marca.
        #expect(ledger.balance(.rev)?.cents == 20_000)
        #expect(ledger.balance(.rev)?.estimated == revBefore?.estimated)
        #expect(guideStatus(.revolut, in: ledger.state, now: t0, calendar: utc) == .notYet)
        #expect(guideStatus(.tradeRepublic, in: ledger.state, now: t0, calendar: utc) == .notYet)
    }

    @Test func mismoTextoConNombreDeTradeRepublicEsUnMovimientoDeTradeRepublic() {
        let raw = "Trade Republic\nZara\nHas pagado 49,95 € en Zara\nSaldo disponible: 300,00 €"
        guard let input = parseQuickNotice(raw) else {
            Issue.record("No se obtuvo IngestInput")
            return
        }
        var ledger = Ledger()
        ledger.setBalance(.rev, cents: 20_000, now: t0 - 60)
        let revBefore = ledger.balance(.rev)
        guard case .stored(let m) = ledger.ingest(input, now: t0) else {
            Issue.record("No se guardó el pago de Trade Republic")
            return
        }
        #expect(m.bank == .tr)
        #expect(m.amountCents == -4_995)
        #expect(ledger.balance(.rev)?.cents == 20_000)
        #expect(ledger.balance(.rev)?.estimated == revBefore?.estimated)
        #expect(ledger.state.unread.isEmpty)
        #expect(guideStatus(.tradeRepublic, in: ledger.state, now: t0, calendar: utc) == .working(since: t0, last: t0))
        #expect(guideStatus(.revolut, in: ledger.state, now: t0, calendar: utc) == .notYet)
    }

    @Test func formatoRealDeRevolutConYSinNombreDeAppEsRevolut() {
        let con = "Revolut\nPophams Bakery\n🍽️ Paid €5.50 at Pophams Bakery\nAvailable balance: €120.40"
        let sin = "Pophams Bakery\n🍽️ Paid €5.50 at Pophams Bakery\nAvailable balance: €120.40"
        for raw in [con, sin] {
            #expect(detectQuickNoticeBank(raw) == .rev)
            var ledger = Ledger()
            ledger.setBalance(.rev, cents: 20_000, now: t0 - 60)
            guard let input = parseQuickNotice(raw), case .stored(let m) = ledger.ingest(input, now: t0) else {
                Issue.record("No se guardó el pago de Revolut: \(raw)")
                continue
            }
            #expect(m.bank == .rev)
            #expect(m.amountCents == -550)
            #expect(ledger.balance(.rev)?.cents == 12_040)
            #expect(ledger.state.unread.isEmpty)
        }
    }

    @Test func lineaDeSaldoDisponibleSolaNoDecideRevolut() {
        for raw in [
            "Saldo disponible: 120,40 €",
            "Available balance: €120.40",
            "Has recibido 20,00 € de Ana\nSaldo disponible: 140,40 €",
            "Gastado hoy: 14,50 €",
        ] {
            #expect(detectQuickNoticeBank(raw) == nil, "\(raw.debugDescription)")
        }
        // Revolut sí tiene frases propias.
        #expect(detectQuickNoticeBank("Spent today: €14.50\nHas pagado 5,50 € en Bar") == .rev)
    }

    @Test func avisoSinBancoRepetidoNoSeGuardaDosVecesYCodigosSeIgnoran() {
        let raw = "Has pagado 12,50 € en Mercadona"
        guard let input = parseQuickNotice(raw) else {
            Issue.record("No se obtuvo IngestInput")
            return
        }
        var ledger = Ledger()
        #expect(ledger.ingest(input, now: t0) == .unread)
        #expect(ledger.ingest(input, now: t0 + 20) == .duplicate)
        #expect(ledger.state.unread.count == 1)

        // Sin importe o con un código: nada que enseñar al dueño, nada que guardar.
        #expect(parseQuickNotice("Tu código OTP es 482910") == nil)
        #expect(parseQuickNotice("Abre la app para ver tu extracto") == nil)
    }

    @Test func avisoSinBancoRespetaSaneadoYTopes() {
        let raw = "Has pagado 12,50 € en \u{202E}Mercadona\u{0007}" + String(repeating: "x", count: 3_000)
        guard case let .unattributedNotice(text)? = parseQuickNotice(raw) else {
            Issue.record("Se esperaba un aviso sin banco")
            return
        }
        #expect(!text.contains("\u{202E}"))
        #expect(!text.contains("\u{0007}"))
        #expect(text.unicodeScalars.count <= QuickNoticeLimits.fieldMaxLength)
    }

    @Test func avisoSinLeerSinBancoConviveConLibrosAntiguos() throws {
        // Un libro guardado antes: el aviso sin leer trae banco.
        let old = Data(#"{"id":"11111111-1111-1111-1111-111111111111","bank":"tr","text":"texto","date":800000000}"#.utf8)
        let decoded = try JSONDecoder().decode(UnreadNotice.self, from: old)
        #expect(decoded.bank == .tr)
        // Uno nuevo sin banco: no escribe la clave y vuelve a leerse igual.
        let fresh = UnreadNotice(bank: nil, text: "texto", date: Date(timeIntervalSinceReferenceDate: 800_000_000))
        let data = try JSONEncoder().encode(fresh)
        #expect(try JSONDecoder().decode(UnreadNotice.self, from: data) == fresh)
        let noKey = Data(#"{"id":"22222222-2222-2222-2222-222222222222","text":"texto","date":800000000}"#.utf8)
        #expect(try JSONDecoder().decode(UnreadNotice.self, from: noKey).bank == nil)
    }

    // MARK: Pendiente y luego cargado: cuenta una sola vez

    private func notice(_ body: String) -> IngestInput {
        .notification(bank: .rev, title: nil, subtitle: nil, body: body)
    }

    @Test func pendienteYLuegoCargadoCuentaUnaVez() {
        var ledger = Ledger()
        ledger.setBalance(.rev, cents: 20_000, now: t0 - 60)
        guard case .stored = ledger.ingest(notice("Pago pendiente de 12,50 € en Mercadona"), now: t0) else {
            Issue.record("El pago pendiente debe registrarse")
            return
        }
        #expect(ledger.balance(.rev)?.cents == 18_750)
        // Pasados unos minutos llega el aviso del cargo: es el mismo pago.
        #expect(ledger.ingest(notice("Has pagado 12,50 € en Mercadona"), now: t0 + 300) == .duplicate)
        #expect(ledger.state.movements.count == 1)
        #expect(ledger.balance(.rev)?.cents == 18_750)
        // Y una reentrega del cargo tampoco suma.
        #expect(ledger.ingest(notice("Has pagado 12,50 € en Mercadona"), now: t0 + 330) == .duplicate)
        #expect(ledger.state.movements.count == 1)
    }

    @Test func pendienteEnInglesYLuegoCargadoCuentaUnaVez() {
        var ledger = Ledger()
        _ = ledger.ingest(notice("Pending payment of €5.50 at Pophams Bakery"), now: t0)
        #expect(ledger.ingest(notice("🍽️ Paid €5.50 at Pophams Bakery"), now: t0 + 600) == .duplicate)
        #expect(ledger.state.movements.count == 1)
    }

    @Test func pendienteNoSeFundeConOtroImporteComercioOMuchoDespues() {
        var ledger = Ledger()
        _ = ledger.ingest(notice("Pago pendiente de 12,50 € en Mercadona"), now: t0)
        // Otro importe, otro comercio y otro banco: movimientos distintos.
        guard case .stored = ledger.ingest(notice("Has pagado 12,60 € en Mercadona"), now: t0 + 60) else {
            Issue.record("Otro importe es otro pago")
            return
        }
        guard case .stored = ledger.ingest(notice("Has pagado 12,50 € en Lidl"), now: t0 + 90) else {
            Issue.record("Otro comercio es otro pago")
            return
        }
        guard case .stored = ledger.ingest(.notification(bank: .tr, title: nil, subtitle: nil, body: "Has pagado 12,50 € en Mercadona"),
                                           now: t0 + 120) else {
            Issue.record("Otro banco es otro pago")
            return
        }
        // Horas después ya no es el mismo cargo.
        guard case .stored = ledger.ingest(notice("Has pagado 12,50 € en Mercadona"), now: t0 + 6 * 3600) else {
            Issue.record("Fuera de la ventana es otro pago")
            return
        }
        #expect(ledger.state.movements.count == 5)
    }

    @Test func dosComprasIgualesYaCargadasSeCuentanLasDos() {
        var ledger = Ledger()
        guard case .stored = ledger.ingest(notice("Has pagado 1,50 € en Metro de Madrid"), now: t0) else {
            Issue.record("Primer billete")
            return
        }
        guard case .stored = ledger.ingest(notice("Has pagado 1,50 € en Metro de Madrid"), now: t0 + 400) else {
            Issue.record("Segundo billete: no hay ningún pendiente, son dos compras")
            return
        }
        #expect(ledger.state.movements.count == 2)
    }

    @Test func pendienteDespuesDeCargadoNoDuplica() {
        var ledger = Ledger()
        _ = ledger.ingest(notice("Has pagado 12,50 € en Mercadona"), now: t0)
        #expect(ledger.ingest(notice("Pago pendiente de 12,50 € en Mercadona"), now: t0 + 120) == .duplicate)
        #expect(ledger.state.movements.count == 1)
    }

    @Test func movimientoSinMarcaDePendienteNoEscribeLaClave() throws {
        let m = Movement(bank: .rev, amountCents: -1250, merchant: "Mercadona", kind: .payment, source: .notification, date: t0)
        let data = try JSONEncoder().encode(m)
        #expect(try JSONDecoder().decode(Movement.self, from: data) == m)
        #expect(!String(decoding: data, as: UTF8.self).contains("noticePending"))
    }
}
