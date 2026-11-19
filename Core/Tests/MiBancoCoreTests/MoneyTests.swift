import Testing
@testable import MiBancoCore

@Suite struct MoneyTests {
    @Test func formatea() {
        #expect(formatEUR(128455) == "1.284,55\u{00A0}€")
        #expect(formatEUR(-1250) == "-12,50\u{00A0}€")
        #expect(formatEUR(5) == "0,05\u{00A0}€")
    }

    @Test(arguments: [
        ("12,50 €", 1250), ("1.234,56 €", 123456), ("€1,234.56", 123456), ("€5.50", 550),
        ("12 €", 1200), ("12,50 EUR", 1250), ("12,50\u{00A0}€", 1250), ("1.234", 123400),
        ("-12,50 €", 1250),
    ])
    func parsea(_ raw: String, _ cents: Int) {
        #expect(parseAmountToCents(Substring(raw)) == cents)
    }

    @Test(arguments: [
        ("12.5", 1250), ("1,5", 150), ("12,5 €", 1250), ("€0.5", 50), ("1.234,5", 123450),
        ("1.234.567", 123456700), ("1,234", 123400), ("12.50", 1250), ("12", 1200),
    ])
    func parseaUnDecimalYMiles(_ raw: String, _ cents: Int) {
        #expect(parseAmountToCents(Substring(raw)) == cents)
    }

    @Test(arguments: ["1\u{202F}234,56 €", "1\u{00A0}234,56\u{00A0}€", " 1 234,56 € ", "1\u{2009}234,56\tEUR"])
    func quitaCualquierEspacio(_ raw: String) {
        #expect(parseAmountToCents(Substring(raw)) == 123456)
    }

    @Test func primerImporteConUnDecimalJuntoAlEuro() {
        #expect(firstAmount(in: "Has pagado 12,5 € en Bar")?.cents == 1250)
        // Sin € ni dos decimales, un número suelto sigue sin contar.
        #expect(firstAmount(in: "Tienes 12.5 puntos") == nil)
    }

    @Test func parseaBasura() {
        #expect(parseAmountToCents("hola") == nil)
    }

    @Test func primerImporte() {
        #expect(firstAmount(in: "Paid €5.50 at X\nSpent today: €14.50")?.cents == 550)
        #expect(firstAmount(in: "Bizum recibido: 20 €")?.cents == 2000)
        #expect(firstAmount(in: "Gana un 2 % TAE") == nil)
        #expect(firstAmount(in: "Tu código es 123456") == nil)
    }
}
