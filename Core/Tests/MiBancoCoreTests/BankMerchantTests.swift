import Foundation
import Testing
@testable import MiBancoCore

@Suite struct BankMerchantTests {
    @Test func cleanBankMerchantRules() {
        #expect(cleanBankMerchant("COMPRA TARJ. 5402XXXXXXXX1234 MERCADONA VALENCIA") == "Mercadona Valencia")
        #expect(cleanBankMerchant("  PAGO   BIZUM A LAURA  ") == "Pago Bizum a Laura")
        #expect(cleanBankMerchant("Amazon.es") == "Amazon.es")
        #expect(cleanBankMerchant("COMPRA TARJETA *1234 ZARA") == "Zara")
        #expect(cleanBankMerchant("PAGO TARJETA CAFE DE LA PLAZA") == "Cafe de la Plaza")
        #expect(cleanBankMerchant("COMPRA EN DE LA CRUZ") == "De la Cruz")
        #expect(cleanBankMerchant("compra en Tienda") == "Tienda")
        #expect(cleanBankMerchant("") == "")
        #expect(cleanBankMerchant("COMPRA TARJ.") == "")
    }

    @Test func richerMerchantRules() {
        #expect(richerMerchant(captured: "Mercadona", bank: "Mercadona Valencia") == "Mercadona")
        #expect(richerMerchant(captured: nil, bank: "Zara") == "Zara")
        #expect(richerMerchant(captured: "", bank: "Zara") == "Zara")
        #expect(richerMerchant(captured: "Pago con tarjeta", bank: "Zara") == "Zara")
        #expect(richerMerchant(captured: "Card payment", bank: "Zara") == "Zara")
        #expect(richerMerchant(captured: "Tienda Rara", bank: "Zara") == "Zara")
        #expect(richerMerchant(captured: "Tienda Rara", bank: "Otra Rara") == "Tienda Rara")
        #expect(richerMerchant(captured: "Mercadona", bank: nil) == "Mercadona")
        #expect(richerMerchant(captured: nil, bank: nil) == nil)
        #expect(richerMerchant(captured: "  ", bank: "") == nil)
    }

    @Test func oldLedgerWithoutBankMerchantDecodes() throws {
        let m = Movement(bank: .rev, amountCents: -100, merchant: nil, kind: .payment, source: .notification,
                         date: Date(timeIntervalSince1970: 1_800_000_000), bankMerchant: "Zara")
        let back = try JSONDecoder().decode(Movement.self, from: JSONEncoder().encode(m))
        #expect(back == m)
        #expect(back.displayMerchant == "Zara")
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(m)) as? [String: Any])
        object.removeValue(forKey: "bankMerchant")
        let old = try JSONDecoder().decode(Movement.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.bankMerchant == nil)
    }

    @Test func mergeOnIngestKeepsBankNameApart() {
        let noon = ISO8601DateFormatter().date(from: "2026-11-20T11:00:00Z")!
        let row = Movement(bank: .rev, amountCents: -1250, merchant: "Mercadona Valencia", kind: .payment, source: .bank,
                           date: noon, bankRef: "t1", bankStatus: .booked, importedAt: noon, dayOnly: true)
        var l = Ledger(state: LedgerState(movements: [row]))
        let outcome = l.ingest(.notification(bank: .rev, title: nil, subtitle: nil, body: "Has pagado 12,50 € en Mercadona"),
                               now: noon.addingTimeInterval(6 * 3600))
        guard case .merged(let m) = outcome else { Issue.record("esperaba .merged"); return }
        #expect(m.merchant == "Mercadona")
        #expect(m.bankMerchant == "Mercadona Valencia")
    }
}
