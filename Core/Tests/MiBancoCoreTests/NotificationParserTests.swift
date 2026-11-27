import Foundation
import Testing
@testable import MiBancoCore

@Suite struct NotificationParserTests {
    private func parse(_ title: String? = nil, _ body: String) -> ParseResult {
        parseNotification(bank: .rev, title: title, subtitle: nil, body: body)
    }

    private func mov(_ kind: MovementKind, _ cents: Int, _ merchant: String?, balance: Int? = nil, shop: Bool = false,
                     pending: Bool = false) -> ParseResult {
        .movement(ParsedMovement(kind: kind, amountCents: cents, merchant: merchant, reportedBalanceCents: balance,
                                 merchantIsShop: shop, isPending: pending))
    }

    private func isShop(_ r: ParseResult) -> Bool? {
        if case .movement(let m) = r { return m.merchantIsShop }
        return nil
    }

    private func kind(_ r: ParseResult) -> MovementKind? {
        if case .movement(let m) = r { return m.kind }
        return nil
    }

    @Test func pagoEnIngles() {
        #expect(parse("Pophams Bakery", "Paid €5.50 at Pophams Bakery\nSpent today: €14.50")
            == mov(.payment, 550, "Pophams Bakery", shop: true))
    }

    @Test func pagoEnEspanolSinSaldo() {
        #expect(parse(nil, "Has pagado 5,50 € en Pophams Bakery\nGastado hoy: 14,50 €")
            == mov(.payment, 550, "Pophams Bakery", shop: true))
    }

    @Test(arguments: ["Saldo: 327,70 €", "Balance: €327.70", "Disponible: 327,70 €", "Te quedan 327,70 €"])
    func saldoComunicado(_ line: String) {
        #expect(parse("Mercadona", "Has pagado 12,50 €\n" + line) == mov(.payment, 1250, "Mercadona", balance: 32770, shop: true))
    }

    @Test func ingresos() {
        #expect(parse(nil, "Has recibido 35,00 € de Carlos") == mov(.income, 3500, "Carlos"))
        #expect(parse(nil, "Bizum recibido: 20 €") == mov(.income, 2000, nil))
    }

    @Test(arguments: [
        "Pago rechazado: 49,95 € en Zara", "Transacción denegada 10 €",
        "Card payment declined €3.00", "Tu código de verificación es 123456", "Your code is 123456",
    ])
    func seIgnora(_ body: String) {
        #expect(parse(nil, body) == .ignore)
    }

    @Test func comercioConCodeNoSeIgnora() {
        #expect(parse("Barcode Café", "Has pagado 4,20 €") == mov(.payment, 420, "Barcode Café", shop: false))
    }

    // I5: sin importe no es un movimiento ni un aviso sin leer.
    @Test(arguments: ["Gana un 2 % TAE en tu cuenta", "Tu tarjeta ya está activada", "Saldo: 300,00 €"])
    func sinImporteSeIgnora(_ body: String) {
        #expect(parse(nil, body) == .ignore)
    }

    @Test func importeSinSignoEsIlegible() {
        #expect(parse(nil, "Movimiento en tu cuenta: 12,50 €") == .unreadable)
    }

    @Test(arguments: ["Paid $5.00 at Starbucks", "Has pagado £12.50 en Pret", "Has pagado 5,00 USD en Amazon"])
    func otraMonedaEsIlegible(_ body: String) {
        #expect(parse(nil, body) == .unreadable)
    }

    @Test func otraMonedaConEurosExplicitosUsaLosEuros() {
        #expect(parse(nil, "Has pagado 5,40 € (6,00 USD) en Amazon") == mov(.payment, 540, "Amazon", shop: true))
    }

    // I2: el signo sale primero de la línea del importe.
    @Test func comercioAbonoTransporteEsPago() {
        #expect(parse("Abono Transporte", "Paid €12.50 at Abono Transporte") == mov(.payment, 1250, "Abono Transporte", shop: true))
    }

    @Test func reciboCargadoEsPago() {
        #expect(kind(parse(nil, "Recibo de Endesa cargado 45,00 €")) == .payment)
    }

    @Test func devolucionDeUnPagoEsIngreso() {
        #expect(kind(parse(nil, "Te han devuelto 5 € de tu pago")) == .income)
    }

    @Test func signoDeLaLineaDelImporteManda() {
        // La otra línea dice "pago", pero la del importe dice "recibido".
        #expect(kind(parse(nil, "Pago de nómina\nHas recibido 1.200,00 €")) == .income)
    }

    @Test func signoDeOtraLineaSiLaDelImporteNoLoDice() {
        #expect(kind(parse(nil, "Has pagado con tu tarjeta\n12,50 € en Lidl")) == .payment)
    }

    @Test func elTituloSinImporteNoDaElSigno() {
        #expect(parse("Pago con tarjeta", "12,50 € en Lidl") == .unreadable)
    }

    @Test func bizumEnviadoEsPago() {
        #expect(kind(parse(nil, "Has enviado un Bizum de 15,00 € a Ana")) == .payment)
    }

    // Menores: cualquier salto de línea y avisos de aprobación.
    @Test func separaPorCualquierSaltoDeLinea() {
        #expect(parse("Mercadona", "Has pagado 12,50 €\r\nSaldo: 300,00 €") == mov(.payment, 1250, "Mercadona", balance: 30000, shop: true))
        #expect(parse("Mercadona", "Has pagado 12,50 €\u{2028}Saldo: 300,00 €") == mov(.payment, 1250, "Mercadona", balance: 30000, shop: true))
    }

    @Test(arguments: [
        "Confirma el pago de 49,95 € en Zara",
        "Aprueba la compra de 12,00 € en la app",
        "Autoriza el pago de 30,00 €",
        "Approve your payment of €20.00",
        "Pago pendiente de aprobar: 12,50 € en Mercadona",
        "Pendiente de confirmar: 49,95 € en Zara",
        "Pendiente de autorizar: 8,40 € en Café Central",
        "Pending approval: €20.00 at Uber",
        "Pending confirmation of €12.50",
        "Tienes una operación pendiente",
        "Pending verification",
        "Tu código OTP es 482910",
        "Pago fallido: 12,50 € en Zara",
        "Card payment failed €5.00 at Café",
        "Saldo insuficiente para pagar 20,00 €",
        "Insufficient funds for €20.00 payment",
        "Autorización caducada: 15,00 € en Amazon",
    ])
    func aprobacionesYRechazosNoSonMovimientos(_ body: String) {
        #expect(parse(nil, body) == .ignore)
    }

    // L2: un pago pendiente CON importe es un movimiento normal, no algo que descartar sin rastro.
    @Test func pagosPendientesConImporteSeRegistran() {
        #expect(parse(nil, "Pago pendiente de 12,50 € en Mercadona") == mov(.payment, 1250, "Mercadona", shop: true, pending: true))
        #expect(parse(nil, "Pago pendiente: 12,50 €") == mov(.payment, 1250, nil, shop: false, pending: true))
        #expect(parse(nil, "Pending payment of €5.50 at Pophams Bakery") == mov(.payment, 550, "Pophams Bakery", shop: true, pending: true))
        #expect(parse(nil, "Pending payment €7.00 at Uber") == mov(.payment, 700, "Uber", shop: true, pending: true))
        #expect(parse(nil, "Autorización pendiente: 8,40 € en Café Central") == mov(.payment, 840, "Café Central", shop: true, pending: true))
    }

    // Ronda 1 (m-5): «pago de nómina» y similares son ingresos, nunca un pago saliente.
    @Test(arguments: [
        "Pago de nómina 1.500 €",
        "Pago de nómina: 1.500,00 €",
        "Pago de nómina de 1.500,00 € en tu cuenta",
        "Pago de salario 1.200,00 €",
        "Salary payment €1,500.00",
        "Payroll payment: €1,500.00",
    ])
    func pagoDeNominaNoEsUnPagoSaliente(_ body: String) {
        #expect(kind(parse(nil, body)) == .income, "\(body)")
    }

    // Ronda 2 (N-3): las palabras de ingreso valen enteras y fuera del nombre del comercio.
    @Test(arguments: [
        "Compra de 12,00 € en Nominalia",
        "Compra de 12,00 € en Nomina Shop",
        "Paid €9.99 at SalaryFinance",
        "Paid €9.99 at Payroll Cafe",
        "Pago en Vinos Denominación 30,00 €",
    ])
    func palabrasDeIngresoDentroDelComercioSiguenSiendoPago(_ body: String) {
        #expect(kind(parse(nil, body)) == .payment, "\(body)")
    }

    // Ronda 3 (N-3): el comercio delante del importe o en su propia línea tampoco da ingreso; «Pago de nómina» sí.
    @Test(arguments: [
        "Pago en Payroll Cafe 9,99 €",
        "Compra en Nómina Express por 12,00 €",
        "Paid at Salary Bar €9.99",
        "Compra\nPayroll Cafe\n9,99 €",
        "Compra con tarjeta\nSalario Bar\n9,99 €",
    ])
    func comercioConPalabraDeIngresoEnOtraPosicionSiguiendoSiendoPago(_ body: String) {
        #expect(kind(parse(nil, body)) == .payment, "\(body)")
    }

    @Test(arguments: [
        "Pago de nómina 1.500,00 €",
        "Nómina ACME 1.500,00 €",
        "Transferencia recibida 1.500,00 € · Nómina",
        "Transferencia recibida 1.500,00 € · Nómina ACME",
        "Transferencia recibida: 1.500,00 € de ACME",
    ])
    func ingresosPorNominaOTransferenciaRecibidaSiguenSiendoIngreso(_ body: String) {
        #expect(kind(parse(nil, body)) == .income, "\(body)")
    }

    // Ronda 1: solo la palabra «pendiente»/«pending» marca el aviso como pendiente.
    @Test func soloLosPendientesLlevanLaMarca() {
        if case .movement(let m) = parse(nil, "Has pagado 12,50 € en Mercadona") { #expect(!m.isPending) } else { Issue.record("movimiento") }
        if case .movement(let m) = parse(nil, "Pago pendiente de 12,50 € en Mercadona") { #expect(m.isPending) } else { Issue.record("movimiento") }
    }

    // L2 añadido: formato real del aviso de Revolut (emoji delante del importe y línea de saldo disponible con o sin emoji).
    @Test(arguments: [
        "Available balance: €120.40",
        "💰 Available balance: €120.40",
        "Remaining balance: €120.40",
        "🏦 Remaining balance: €120.40",
        "Saldo disponible: 120,40 €",
        "Saldo disponible: €120.40",
        "💳 Saldo disponible: 120,40 €",
        "Balance disponible: 120,40 €",
        "💳 Balance disponible: 120,40 €",
        "✨ Te quedan: 120,40 €",
    ])
    func formatoRealRevolutConEmojiYSaldoDisponible(_ balanceLine: String) {
        #expect(parse("Pophams Bakery", "🍽️ Paid €5.50 at Pophams Bakery\n" + balanceLine)
            == mov(.payment, 550, "Pophams Bakery", balance: 12040, shop: true))
    }

    @Test func formatoRealRevolutEnEspanolYSpentTodayConEmoji() {
        #expect(parse("Mercadona", "🛒 Pagaste 12,50 € en Mercadona\n💳 Saldo disponible: 240,00 €")
            == mov(.payment, 1250, "Mercadona", balance: 24000, shop: true))
        #expect(parse("Pophams Bakery", "🍽️ Paid €5.50 at Pophams Bakery\nSpent today: €14.50")
            == mov(.payment, 550, "Pophams Bakery", balance: nil, shop: true))
        #expect(parse("Pophams Bakery", "🍽️ Paid €5.50 at Pophams Bakery\n📊 Spent today: €14.50")
            == mov(.payment, 550, "Pophams Bakery", balance: nil, shop: true))
    }

    @Test func formatoRealRevolutActualizaTeQuedanEnLedger() {
        let t0 = Date(timeIntervalSinceReferenceDate: 1_800_000_000)

        var spanish = Ledger()
        spanish.setBalance(.rev, cents: 20_000, now: t0 - 60)
        guard case .stored(let mEs) = spanish.ingest(
            .notification(bank: .rev, title: "Pophams Bakery", subtitle: nil,
                          body: "🍽️ Paid €5.50 at Pophams Bakery\n💳 Saldo disponible: 120,40 €"),
            now: t0
        ) else {
            Issue.record("No se guardó el aviso real de Revolut en español")
            return
        }
        #expect(spanish.balance(.rev)?.cents == 12_040)
        #expect(spanish.balance(.rev)?.estimated == false)
        #expect(alertText(for: mEs, balance: 12_040, estimated: false).body == "Te quedan 120,40\u{00A0}€ en Revolut")

        var english = Ledger()
        english.setBalance(.rev, cents: 20_000, now: t0 - 60)
        _ = english.ingest(
            .notification(bank: .rev, title: "Pophams Bakery", subtitle: nil,
                          body: "🍽️ Paid €5.50 at Pophams Bakery\n💰 Available balance: €120.40"),
            now: t0
        )
        #expect(english.balance(.rev)?.cents == 12_040)
        #expect(english.balance(.rev)?.estimated == false)

        // Spent today sigue sin pisar el saldo.
        var spentToday = Ledger()
        spentToday.setBalance(.rev, cents: 20_000, now: t0 - 60)
        _ = spentToday.ingest(
            .notification(bank: .rev, title: "Pophams Bakery", subtitle: nil,
                          body: "🍽️ Paid €5.50 at Pophams Bakery\nSpent today: €14.50"),
            now: t0
        )
        #expect(spentToday.balance(.rev)?.cents == 19_450)
        #expect(spentToday.balance(.rev)?.estimated == true)
    }

    // Solo un pago en una tienda permite buscar su logo en internet.
    @Test func tiendaSoloEnPagosConEnOAt() {
        #expect(isShop(parse(nil, "Has pagado 12,50 € en Mercadona")) == true)
        #expect(isShop(parse(nil, "Paid €5.50 at Pophams Bakery")) == true)
        #expect(isShop(parse("Mercadona", "Has pagado 12,50 €\nSaldo: 327,70 €")) == true)
        #expect(isShop(parse(nil, "Has enviado 20,00 € a Laura")) == false)
        #expect(isShop(parse(nil, "Has recibido 35,00 € de Carlos")) == false)
        #expect(isShop(parse(nil, "Bizum de Laura: 20 €")) == false)
        #expect(isShop(parse("Laura", "Has enviado 20,00 €")) == false)
        #expect(isShop(parse(nil, "Has pagado 12,50 €")) == false)
    }

    // Fix round 2: un título solo es tienda si el directorio lo conoce; un envío en cualquier línea nunca lo es.
    @Test func tituloOEnvioNoSonTienda() {
        #expect(isShop(parse("Aitziber Zubizarreta", "Has pagado 15,00 €")) == false)
        #expect(isShop(parse("Mercadona", "Has pagado 12,50 €\nSaldo: 327,70 €")) == true)
        #expect(isShop(parse(nil, "Has enviado 20 € en Aitziber Zubizarreta")) == false)
        #expect(isShop(parse(nil, "Has pagado 15,00 € en Pophams Bakery\nTransferencia enviada")) == false)
        #expect(isShop(parse(nil, "Paid €5.50 at Pophams Bakery\nSpent today: €14.50")) == true)
        #expect(isShop(parse(nil, "Has pagado 12,50 € en Mercadona")) == true)
    }

    @Test func confirmadoNoSeIgnora() {
        #expect(kind(parse(nil, "Pago confirmado: has pagado 9,99 € en Netflix")) == .payment)
    }
}
