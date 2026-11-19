import Testing
@testable import MiBancoCore

@Suite struct MerchantDirectoryTests {
    @Test(arguments: [
        ("MERCADONA TORREJÓN, S.A.", "mercadona torrejon"),
        ("El Corte Inglés", "el corte ingles"),
        ("McDonald's", "mcdonalds"),
        ("AMZN Mktp ES*2K4", "amzn mktp es 2k4"),
        ("Pull&Bear", "pull bear"),
        ("Comercial Pérez S.L.U.", "comercial perez"),
        ("Acme Inc", "acme"),
        ("  ", ""),
    ])
    func normaliza(_ raw: String, _ expected: String) {
        #expect(normalizeMerchant(raw) == expected)
    }

    @Test(arguments: [
        ("MERCADONA TORREJON 123", "mercadona.es"),
        ("Mercadona", "mercadona.es"),
        ("Lidl", "lidl.es"),
        ("LIDL DICE GRACIAS", "lidl.es"),
        ("AMZN Mktp ES*2K4", "amazon.es"),
        ("Amazon.es", "amazon.es"),
        ("Spotify P1A2B3", "spotify.com"),
        ("UBER *EATS", "ubereats.com"),
        ("Uber *Trip HELP.UBER.COM", "uber.com"),
        ("PAYPAL *NETFLIX", "netflix.com"),
        ("PayPal", "paypal.com"),
        ("El Corte Inglés Castellana", "elcorteingles.es"),
        ("McDonald's Gran Vía", "mcdonalds.es"),
        ("H&M", "hm.com"),
        ("Pull&Bear 0345", "pullandbear.com"),
        ("Disney+", "disneyplus.com"),
        ("MásMóvil", "masmovil.es"),
        ("Glovo", "glovoapp.com"),
        ("Renfe Viajeros S.A.", "renfe.com"),
        ("Zara", "zara.com"),
        ("Bizum", "bizum.es"),
    ])
    func casa(_ merchant: String, _ domain: String) {
        #expect(merchantDomain(for: merchant) == domain)
    }

    @Test(arguments: ["Bar Pepe", "", "   ", "Nómina", "Bizum de Laura", "Intereses", "Farmacia Lda. Ruiz"])
    func noCasa(_ merchant: String) {
        #expect(merchantDomain(for: merchant) == nil)
    }

    @Test func tablaGrande() {
        #expect(merchantDirectoryDomains.count >= 80)
        #expect(merchantDirectoryDomains.allSatisfy { $0.contains(".") && !$0.contains(" ") })
    }

    @Test(arguments: [
        ("Bershka", "bershka"),
        ("Casa Lola", nil),
        ("Bar Pepe", nil),
        ("Cafetería Sol", nil),
        ("Nómina", nil),
        ("Bizum de Laura", nil),
        ("Taxi", nil),
        ("Tienda de la esquina", nil),
        ("Hawkers Co", "hawkersco"),
        ("Carlos", nil),
        ("Laura", nil),
        ("Pepe García", nil),
        ("Gasolina", nil),
        ("Regalo", nil),
        ("Cena", nil),
        ("Ikea", "ikea"),
        ("Bar", nil),
        ("12", nil),
        ("", nil),
    ] as [(String, String?)])
    func adivinaSlug(_ merchant: String, _ slug: String?) {
        #expect(guessedLogoSlug(for: merchant) == slug)
    }

    // Alias cortos o ambiguos: solo en una compra en tienda y sin otro negocio detrás.
    @Test func aliasAmbiguos() {
        #expect(merchantDomain(for: "HM Hospitales", isShop: false) == nil)
        #expect(merchantDomain(for: "HM Hospitales", isShop: true) == nil)
        #expect(merchantDomain(for: "ZARA ES 1234 MADRID", isShop: true) == "zara.com")
        #expect(merchantDomain(for: "Zara", isShop: false) == nil)
        #expect(merchantDomain(for: "Mango Bar", isShop: true) == nil)
        #expect(merchantDomain(for: "BP Consulting", isShop: true) == nil)
        #expect(merchantDomain(for: "Orange Garden", isShop: true) == nil)
        #expect(merchantDomain(for: "Mercadona Madrid", isShop: false) == "mercadona.es")
    }

    @Test func logoDeUnIngresoSoloDeServiciosDePago() {
        #expect(logoDomain(merchant: "Zara", isShop: false, isIncome: true) == nil)
        #expect(logoDomain(merchant: "Mercadona", isShop: false, isIncome: true) == nil)
        #expect(logoDomain(merchant: "Bizum", isShop: false, isIncome: true) == "bizum.es")
        #expect(logoDomain(merchant: "PayPal", isShop: false, isIncome: true) == "paypal.com")
        #expect(logoDomain(merchant: "Mercadona", isShop: true, isIncome: false) == "mercadona.es")
        #expect(logoDomain(merchant: nil, isShop: true, isIncome: false) == nil)
    }
}
