import Foundation
import Testing
@testable import MiBancoCore

private let fetched = Date(timeIntervalSince1970: 1_800_000_000)

private func bal(_ type: String, _ amount: String, _ currency: String = "EUR", ref: String? = nil) -> EBBalance {
    EBBalance(balanceAmount: EBAmount(currency: currency, amount: amount), balanceType: type, lastChangeDateTime: ref)
}

@Suite struct BalanceReadingTests {
    @Test func availableBeatsBooked() {
        let r = chooseBalanceReading([bal("CLBD", "100.00"), bal("ITAV", "90.50")], fetchedAt: fetched)
        #expect(r == BalanceReading(cents: 9050, at: fetched, kind: .available))
    }

    @Test func nonEuroIsIgnored() {
        let r = chooseBalanceReading([bal("ITAV", "500.00", "USD"), bal("CLBD", "100.00")], fetchedAt: fetched)
        #expect(r == BalanceReading(cents: 10000, at: fetched, kind: .booked))
    }

    @Test func lowerCaseEuroCodeIsAccepted() {
        let r = chooseBalanceReading([bal("ITAV", "12.50", "eur")], fetchedAt: fetched)
        #expect(r == BalanceReading(cents: 1250, at: fetched, kind: .available))
        #expect(EBAmount(currency: "eur", amount: "1.00").euroCents == 100)
        #expect(EBAmount(currency: "EURO", amount: "1.00").euroCents == nil)
    }

    @Test func noEuroGivesNil() {
        #expect(chooseBalanceReading([bal("ITAV", "5.00", "USD")], fetchedAt: fetched) == nil)
        #expect(chooseBalanceReading([], fetchedAt: fetched) == nil)
    }

    @Test func latestReferenceWinsAmongEqualTypes() {
        let r = chooseBalanceReading([
            bal("CLAV", "10.00", ref: "2026-11-20T08:00:00Z"),
            bal("CLAV", "20.00", ref: "2026-11-20T09:00:00Z"),
        ], fetchedAt: fetched)
        #expect(r?.cents == 2000)
        #expect(r?.at == parseEnableBankingDate("2026-11-20T09:00:00Z"))
        #expect(r?.kind == .available)
    }

    @Test func futureReferenceUsesFetchTime() {
        let r = chooseBalanceReading([bal("ITAV", "1.00", ref: "2999-01-01T00:00:00Z")], fetchedAt: fetched)
        #expect(r?.at == fetched)
    }

    @Test func unparseableAmountIsSkipped() {
        let r = chooseBalanceReading([bal("ITAV", "abc"), bal("CLBD", "7.00")], fetchedAt: fetched)
        #expect(r == BalanceReading(cents: 700, at: fetched, kind: .booked))
    }

    @Test func bookedOrderAndOtherLast() {
        let r = chooseBalanceReading([bal("OTHR", "1.00"), bal("OPBD", "2.00"), bal("CLBD", "3.00")], fetchedAt: fetched)
        #expect(r?.cents == 300)
        #expect(chooseBalanceReading([bal("OTHR", "1.00")], fetchedAt: fetched)?.kind == .booked)
    }
}
