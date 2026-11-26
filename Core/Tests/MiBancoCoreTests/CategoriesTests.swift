import Foundation
import Testing
@testable import MiBancoCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Madrid")!
    c.locale = Locale(identifier: "es_ES")
    return c
}()

private func nov(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

private func pay(_ cents: Int, _ merchant: String?, _ when: Date, isShop: Bool = false,
                 category: SpendingCategory? = nil) -> Movement {
    Movement(bank: .rev, amountCents: -cents, merchant: merchant, kind: .payment, source: .notification, date: when,
             isShop: isShop, category: category)
}

@Suite struct CategoryTests {
    @Test func directorio() {
        #expect(directoryCategory(forDomain: "mercadona.es") == .supermercado)
        #expect(directoryCategory(forDomain: "lidl.es") == .supermercado)
        #expect(directoryCategory(forDomain: "carrefour.com") == .supermercado)
        #expect(directoryCategory(forDomain: "glovoapp.com") == .comerFuera)
        #expect(directoryCategory(forDomain: "starbucks.es") == .comerFuera)
        #expect(directoryCategory(forDomain: "renfe.com") == .transporte)
        #expect(directoryCategory(forDomain: "repsol.es") == .transporte)
        #expect(directoryCategory(forDomain: "zara.com") == .compras)
        #expect(directoryCategory(forDomain: "amazon.es") == .compras)
        #expect(directoryCategory(forDomain: "decathlon.es") == .compras)
        #expect(directoryCategory(forDomain: "spotify.com") == .suscripciones)
        #expect(directoryCategory(forDomain: "netflix.com") == .suscripciones)
        #expect(directoryCategory(forDomain: "bizum.es") == .personas)
        #expect(directoryCategory(forDomain: "paypal.com") == nil)
    }

    @Test func todoElDirectorioTieneCategoria() {
        for d in merchantDirectoryDomains where d != "paypal.com" {
            let c = directoryCategory(forDomain: d)
            #expect(c != nil, "sin categoría: \(d)")
            #expect(c != .sinCategoria, "sinCategoria: \(d)")
        }
    }

    @Test func tablaDeNombresYSimbolos() {
        #expect(SpendingCategory.allCases.count == 12)
        #expect(SpendingCategory.comerFuera.displayName == "Comer fuera")
        #expect(SpendingCategory.casa.displayName == "Casa y facturas")
        #expect(SpendingCategory.sinCategoria.displayName == "Sin categoría")
        #expect(SpendingCategory.suscripciones.symbolName == "repeat")
        #expect(SpendingCategory.sinCategoria.symbolName == "circle.dashed")
    }

    @Test func palabrasClave() {
        #expect(keywordCategory(for: "Bar Manolo") == .comerFuera)
        #expect(keywordCategory(for: "Farmacia Lda. Pérez") == .salud)
        #expect(keywordCategory(for: "Parking Plaza Mayor") == .transporte)
        #expect(keywordCategory(for: "Hotel NH Valencia") == .viajes)
        #expect(keywordCategory(for: "Cajero Calle Alcalá") == .efectivo)
        #expect(keywordCategory(for: "Cine Yelmo") == .ocio)
        #expect(keywordCategory(for: "Iberdrola Clientes") == .casa)
        #expect(keywordCategory(for: "Frutería Paqui") == .supermercado)
    }

    @Test func palabrasEnterasNoSubcadenas() {
        #expect(keywordCategory(for: "Barcelona Shop") == nil)
        #expect(keywordCategory(for: "Parkinson Foundation") == nil)
        #expect(keywordCategory(for: "Cinesa Proyecciones") == nil)
    }

    @Test func prioridad() {
        var m = pay(1250, "Mercadona", nov(19), isShop: true)
        let none: [String: SpendingCategory] = [:]
        #expect(spendingCategory(of: m, overrides: none, subscriptionKeys: []) == .supermercado)
        m.category = .casa
        #expect(spendingCategory(of: m, overrides: none, subscriptionKeys: []) == .casa)
        m.category = nil
        #expect(spendingCategory(of: m, overrides: ["mercadona": .compras], subscriptionKeys: []) == .compras)
        m.category = .casa
        #expect(spendingCategory(of: m, overrides: ["mercadona": .compras], subscriptionKeys: []) == .casa)
    }

    @Test func suscripcionAntesQuePalabraClave() {
        let m = pay(3000, "Gimnasio Fit", nov(19), isShop: true)
        #expect(spendingCategory(of: m, overrides: [:], subscriptionKeys: ["gimnasio fit"]) == .suscripciones)
        #expect(spendingCategory(of: m, overrides: [:], subscriptionKeys: []) == .ocio)
    }

    @Test func personasYSinCategoria() {
        // Un nombre sin más no prueba que el pago fuera a una persona (puede ser el dueño de un bar): sin categoría.
        #expect(spendingCategory(of: pay(500, "Carlos", nov(19), isShop: false), overrides: [:], subscriptionKeys: []) == .sinCategoria)
        #expect(spendingCategory(of: pay(500, "Bizum a Carlos", nov(19), isShop: false), overrides: [:], subscriptionKeys: []) == .personas)
        #expect(spendingCategory(of: pay(500, "Tienda Rara", nov(19), isShop: true), overrides: [:], subscriptionKeys: []) == .sinCategoria)
        #expect(spendingCategory(of: pay(500, nil, nov(19)), overrides: [:], subscriptionKeys: []) == .sinCategoria)
        let inc = Movement(bank: .rev, amountCents: 500, merchant: "Carlos", kind: .income, source: .notification, date: nov(19))
        #expect(spendingCategory(of: inc, overrides: [:], subscriptionKeys: []) == nil)
    }

    @Test func aplicarATodoElComercio() {
        let first = pay(1250, "Mercadona", nov(18), isShop: true)
        let second = pay(900, "Mercadona", nov(19), isShop: true, category: .casa)
        var ledger = Ledger(state: LedgerState(movements: [first, second]))
        ledger.setCategory(.compras, for: first.id, applyToMerchant: true)
        #expect(ledger.state.categoryOverrides["mercadona"] == .compras)
        #expect(ledger.state.movements.allSatisfy { $0.category == nil })

        ledger.setCategory(.ocio, for: first.id, applyToMerchant: false)
        #expect(ledger.state.movements.first { $0.id == first.id }?.category == .ocio)
        #expect(ledger.state.movements.first { $0.id == second.id }?.category == nil)
        #expect(ledger.state.categoryOverrides == ["mercadona": .compras])

        ledger.setCategory(nil, for: first.id, applyToMerchant: true)
        #expect(ledger.state.categoryOverrides["mercadona"] == nil)
    }

    @Test func leeLibrosAntiguos() throws {
        let json = """
        {"balances":[],"movements":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","bank":"rev","amountCents":-500,
        "kind":"payment","source":"notification","date":0}],"unread":[]}
        """
        let state = try JSONDecoder().decode(LedgerState.self, from: Data(json.utf8))
        #expect(state.categoryOverrides == [:])
        #expect(state.movements.first?.category == nil)
    }
}
