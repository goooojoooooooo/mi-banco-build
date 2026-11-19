import Testing
@testable import MiBancoCore

@Suite struct NotificationParserTests {
    private func parse(_ title: String? = nil, _ body: String) -> ParseResult {
        parseNotification(bank: .rev, title: title, subtitle: nil, body: body)
    }

    private func mov(_ kind: MovementKind, _ cents: Int, _ merchant: String?, balance: Int? = nil, shop: Bool = false) -> ParseResult {
        .movement(ParsedMovement(kind: kind, amountCents: cents, merchant: merchant, reportedBalanceCents: balance, merchantIsShop: shop))
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
        "Confirma el pago de 49,95 € en Zara", "Aprueba la compra de 12,00 € en la app",
        "Autoriza el pago de 30,00 €", "Approve your payment of €20.00", "Pago pendiente: 12,50 €",
        "Pending payment €7.00 at Uber",
    ])
    func aprobacionesNoSonMovimientos(_ body: String) {
        #expect(parse(nil, body) == .ignore)
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
