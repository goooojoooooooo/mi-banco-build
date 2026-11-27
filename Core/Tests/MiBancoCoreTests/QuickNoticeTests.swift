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
        #expect(detectQuickNoticeBank("Mercadona\nHas pagado 12,50 € en Mercadona\nGastado hoy: 20,00 €") == .rev)
        #expect(detectQuickNoticeBank("🍽️ Paid €5.50 at Pophams Bakery") == .rev)

        #expect(detectQuickNoticeBank("Zara\nCard payment of €49.95 at Zara") == .tr)
        #expect(detectQuickNoticeBank("Mercadona\nHas pagado 12,50 € en Mercadona\nSaveback: 0,13 €") == .tr)
        #expect(detectQuickNoticeBank("Lidl\nHas pagado 9,20 € en Lidl\nRound up: 0,80 €") == .tr)
    }

    @Test func noAdivinaBancoConTextoGenericoContraparteOConflicto() {
        // Sin nombre de app ni patrón propio del banco.
        #expect(detectQuickNoticeBank("Has pagado 12,50 € en Mercadona") == nil)
        #expect(parseQuickNotice("Has pagado 12,50 € en Mercadona") == nil)

        // La contraparte de un traspaso no identifica el banco emisor.
        #expect(detectQuickNoticeBank("Transferencia a imagin\nHas enviado 50,00 € a imagin") == nil)
        #expect(detectQuickNoticeBank("Transferencia de Revolut\nHas recibido 50,00 € de Revolut") == nil)
        #expect(detectQuickNoticeBank("Has pagado 12,50 € en Imaginarium") == nil)

        // Con cabecera explícita de la app, manda la cabecera sobre la contraparte.
        #expect(detectQuickNoticeBank("Revolut\nTransferencia a imagin\nHas enviado 50,00 € a imagin") == .rev)
        // Sin cabecera, pero con línea de saldo de Revolut, no se confunde con «a imagin».
        #expect(detectQuickNoticeBank("Transferencia a imagin\nHas enviado 50,00 € a imagin\nSaldo disponible: 200,00 €") == .rev)

        // Señales enfrentadas de dos bancos sin cabecera explícita -> nil.
        #expect(detectQuickNoticeBank("Saveback: 0,10 €\nSpent today: €14.50") == nil)
    }

    // MARK: Reparto en título y cuerpo e integración con Ledge

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
