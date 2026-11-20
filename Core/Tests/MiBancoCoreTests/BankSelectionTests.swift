import Foundation
import Testing
@testable import MiBancoCore

@Suite struct BankSelectionTests {
    private let now = Date(timeIntervalSince1970: 1_795_172_400) // 2026-11-20T11:00:00Z

    @Test func matchesBanks() {
        let list = [
            EBASPSP(name: "Revolut", country: "LT"), EBASPSP(name: "Revolut", country: "ES"),
            EBASPSP(name: "imagin", country: "ES"), EBASPSP(name: "CaixaBank", country: "ES"),
        ]
        #expect(matchASPSP(for: .rev, in: list) == EBASPSP(name: "Revolut", country: "ES"))
        #expect(matchASPSP(for: .ima, in: list) == EBASPSP(name: "imagin", country: "ES"))
        #expect(matchASPSP(for: .tr, in: list) == nil)
        let only = [EBASPSP(name: "Revolut Bank UAB", country: "LT")]
        #expect(matchASPSP(for: .rev, in: only) == only[0])
    }

    @Test func matchFoldsCaseAndAccents() {
        let list = [EBASPSP(name: "IMAGÍN", country: "ES")]
        #expect(matchASPSP(for: .ima, in: list) == list[0])
        let tr = [EBASPSP(name: "Trade Republic Bank", country: "DE")]
        #expect(matchASPSP(for: .tr, in: tr) == tr[0])
    }

    @Test func searchKeys() {
        #expect(aspspSearchKey(for: .rev) == "revolut")
        #expect(aspspSearchKey(for: .ima) == "imagin")
        #expect(aspspSearchKey(for: .tr) == "trade republic")
    }

    @Test func consentLength() {
        let day: TimeInterval = 86_400
        func until(_ validity: Int?) -> Date {
            consentValidUntil(for: EBASPSP(name: "X", country: "ES", maximumConsentValidity: validity), now: now)
        }
        #expect(until(15_552_000) == now.addingTimeInterval(180 * day - 3600))
        #expect(until(7_776_000) == now.addingTimeInterval(90 * day - 3600))
        #expect(until(nil) == now.addingTimeInterval(90 * day - 3600))
        #expect(until(31_536_000) == now.addingTimeInterval(180 * day - 3600))
    }

    @Test func consentIsNeverInThePast() {
        let day: TimeInterval = 86_400
        func until(_ validity: Int?) -> Date {
            consentValidUntil(for: EBASPSP(name: "X", country: "ES", maximumConsentValidity: validity), now: now)
        }
        // Un banco que permite menos de un día manda; aun así queda después de `now`.
        #expect(until(3600) == now.addingTimeInterval(3600))
        #expect(until(0) > now)
        #expect(until(-5) > now)
        // Un banco que permite justo algo más de un día: 1 día (el mínimo cabe).
        #expect(until(Int(day) + 1800) == now.addingTimeInterval(day))
        // El mínimo es 1 día cuando el banco permite más.
        #expect(until(Int(day) + 3600) == now.addingTimeInterval(day))
        #expect(until(2 * Int(day)) == now.addingTimeInterval(2 * day - 3600))
    }

    @Test func nonEuroBalancesAreNeverPicked() {
        #expect(pickBalanceCents([balance("ITAV", "5.00", "USD")]) == nil)
        #expect(pickBalanceCents([balance("ITAV", "5.00", "usd"), balance("CLBD", "7.00", "GBP")]) == nil)
        #expect(pickBalanceCents([balance("ITAV", "5.00", "eur")]) == 500)
    }

    @Test func selectsEuroCurrentAccounts() {
        let accounts = [
            EBAccount(uid: "u1", currency: "EUR", cashAccountType: "CACC"),
            EBAccount(uid: "u2", currency: "USD", cashAccountType: "CACC"),
            EBAccount(uid: "u3", currency: "EUR", cashAccountType: "SVGS"),
            EBAccount(uid: "u4", currency: "EUR", cashAccountType: nil),
        ]
        #expect(selectAccounts(accounts).map(\.uid) == ["u1", "u4"])
        #expect(selectAccounts([EBAccount(uid: "x", currency: "USD", cashAccountType: "CACC")]).isEmpty)
    }

    private func balance(_ type: String, _ amount: String, _ currency: String = "EUR") -> EBBalance {
        EBBalance(balanceAmount: EBAmount(currency: currency, amount: amount), balanceType: type)
    }

    @Test func picksBalance() {
        #expect(pickBalanceCents([balance("CLBD", "100.00"), balance("ITAV", "95.50")]) == 9550)
        #expect(pickBalanceCents([balance("ITAV", "5.00", "USD"), balance("OTHR", "3.00")]) == 300)
        #expect(pickBalanceCents([balance("XPCD", "1.00"), balance("CLAV", "2.00")]) == 200)
        #expect(pickBalanceCents([]) == nil)
        #expect(pickBalanceCents([balance("CLBD", "x")]) == nil)
        #expect(pickBalanceCents([balance("CLBD", "-4.20")]) == -420)
    }

    @Test func storedSessionHasNoIBAN() throws {
        let session = StoredSession(
            sessionID: "s", accountUIDs: ["u"], validUntil: now, aspspName: "Revolut", aspspCountry: "ES")
        let data = try JSONEncoder().encode(session)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["accountUIDs", "aspspCountry", "aspspName", "sessionID", "validUntil"])
        #expect(try JSONDecoder().decode(StoredSession.self, from: data) == session)
    }

    @Test func pendingExpires() {
        let started = Date(timeIntervalSince1970: 1_795_168_800) // 10:00:00Z
        let pending = PendingAuth(
            state: "s", bank: .rev, aspspName: "Revolut", aspspCountry: "ES", startedAt: started)
        #expect(!pending.isExpired(now: started.addingTimeInterval(14 * 60 + 59)))
        #expect(pending.isExpired(now: started.addingTimeInterval(15 * 60)))
    }
}
