import Foundation
import Testing
@testable import MiBancoCore

private func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
private let fetched = iso("2026-11-20T13:00:00Z")
private let cal = bankingCalendar

private func link(until: String = "2027-02-01T10:00:00Z") -> BankLinkInfo {
    BankLinkInfo(connectedAt: iso("2026-11-01T10:00:00Z"), consentValidUntil: iso(until))
}

private func record(_ ref: String, cents: Int = -1250, status: BankStatus = .booked, day: String = "2026-11-20T12:00:00Z") -> BankRecord {
    BankRecord(ref: ref, bank: .rev, amountCents: cents, timing: .bookingDay(iso(day)), status: status, merchant: "Mercadona")
}

@Suite struct BankSyncStepTests {
    // MARK: fecha

    @Test func dateParameterIsMadridDay() {
        // 2026-11-19T23:30Z ya es 20 de noviembre en Madrid.
        #expect(bankDateParameter(iso("2026-11-19T23:30:00Z"), calendar: cal) == "2026-11-20")
        #expect(bankDateParameter(iso("2026-03-05T10:00:00Z"), calendar: cal) == "2026-03-05")
    }

    // MARK: saldo de varias cuentas

    @Test func combinesAccountsAndUsesOldestTime() {
        let a = BalanceReading(cents: 1000, at: iso("2026-11-20T12:00:00Z"), kind: .available)
        let b = BalanceReading(cents: 250, at: iso("2026-11-20T11:00:00Z"), kind: .available)
        #expect(combineBalanceReadings([a, b]) == BalanceReading(cents: 1250, at: b.at, kind: .available))
    }

    @Test func mixedKindsAreMixed() {
        let a = BalanceReading(cents: 1000, at: fetched, kind: .available)
        let b = BalanceReading(cents: 5, at: fetched, kind: .booked)
        #expect(combineBalanceReadings([a, b])?.kind == .mixed)
        #expect(combineBalanceReadings([b, b])?.kind == .booked)
    }

    @Test func missingAccountOrNoAccountsAdoptsNothing() {
        let a = BalanceReading(cents: 1000, at: fetched, kind: .available)
        #expect(combineBalanceReadings([a, nil]) == nil)
        #expect(combineBalanceReadings([nil]) == nil)
        #expect(combineBalanceReadings([]) == nil)
    }

    // MARK: aplicar una consulta

    @Test func appliesRecordsBalanceAndSuccessTogether() {
        var ledger = Ledger(state: LedgerState(links: [.rev: link()]))
        let reading = BalanceReading(cents: 10_000, at: iso("2026-11-20T12:59:00Z"), kind: .available)
        let applied = ledger.applyBankFetch(
            bank: .rev, records: [record("a")], balance: reading, dateFrom: iso("2026-11-13T00:00:00Z"), complete: true,
            fetchedAt: fetched, calendar: cal)
        #expect(applied?.report.added == 1)
        #expect(applied?.balanceAdopted == true)
        #expect(ledger.state.links[.rev]?.lastSuccessAt == fetched)
        #expect(ledger.state.links[.rev]?.historyLoaded == true)
        let balance = ledger.state.balances[.rev]
        #expect(balance?.cents == 10_000)
        #expect(balance?.fetchedAt == fetched)
        #expect(balance?.origin == .bank)
        #expect(balance?.countsPending == false)
        #expect(ledger.balance(.rev)?.estimated == false)
    }

    @Test func disconnectedDuringFetchWritesNothing() {
        var ledger = Ledger()
        let applied = ledger.applyBankFetch(
            bank: .rev, records: [record("a")], balance: BalanceReading(cents: 1, at: fetched, kind: .available),
            dateFrom: iso("2026-11-13T00:00:00Z"), complete: true, fetchedAt: fetched, calendar: cal)
        #expect(applied == nil)
        #expect(ledger.state.movements.isEmpty)
        #expect(ledger.state.balances.isEmpty)
    }

    @Test func noBalanceStillAppliesRecords() {
        var ledger = Ledger(state: LedgerState(links: [.rev: link()]))
        let applied = ledger.applyBankFetch(
            bank: .rev, records: [record("a")], balance: nil, dateFrom: iso("2026-11-13T00:00:00Z"), complete: true,
            fetchedAt: fetched, calendar: cal)
        #expect(applied?.balanceAdopted == false)
        #expect(ledger.state.balances[.rev] == nil)
        #expect(ledger.state.movements.count == 1)
    }

    @Test func bookedOnlyReadingKeepsPendingAndIsEstimated() {
        var ledger = Ledger(state: LedgerState(links: [.rev: link()]))
        let reading = BalanceReading(cents: 10_000, at: iso("2026-11-20T12:59:00Z"), kind: .booked)
        _ = ledger.applyBankFetch(
            bank: .rev, records: [record("p", cents: -2000, status: .pending), record("b", cents: -500, status: .booked)],
            balance: reading, dateFrom: iso("2026-11-13T00:00:00Z"), complete: true, fetchedAt: fetched, calendar: cal)
        let result = ledger.balance(.rev)
        #expect(result?.cents == 8_000)
        #expect(result?.estimated == true)
    }

    @Test func availableReadingIgnoresPendingRows() {
        var ledger = Ledger(state: LedgerState(links: [.rev: link()]))
        let reading = BalanceReading(cents: 10_000, at: iso("2026-11-20T12:59:00Z"), kind: .available)
        _ = ledger.applyBankFetch(
            bank: .rev, records: [record("p", cents: -2000, status: .pending)], balance: reading,
            dateFrom: iso("2026-11-13T00:00:00Z"), complete: true, fetchedAt: fetched, calendar: cal)
        #expect(ledger.balance(.rev)?.cents == 10_000)
        #expect(ledger.balance(.rev)?.estimated == false)
    }

    @Test func countsPendingSurvivesEncoding() throws {
        let b = ManualBalance(cents: 5, setAt: fetched, origin: .bank, fetchedAt: fetched, countsPending: true)
        let back = try JSONDecoder().decode(ManualBalance.self, from: JSONEncoder().encode(b))
        #expect(back == b)
        let plain = ManualBalance(cents: 5, setAt: fetched, origin: .bank)
        let text = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        #expect(!text.contains("countsPending"))
    }

    @Test func truncatedFetchKeepsRecordsAndDoesNotVanishPending() {
        var ledger = Ledger(state: LedgerState(links: [.rev: link()]))
        let from = iso("2026-11-13T00:00:00Z")
        _ = ledger.applyBankFetch(bank: .rev, records: [record("p", status: .pending)], balance: nil, dateFrom: from,
                                  complete: true, fetchedAt: iso("2026-11-20T09:00:00Z"), calendar: cal)
        #expect(ledger.state.movements.count == 1)
        // Segunda consulta cortada que no trae el pendiente: se queda.
        let cut = ledger.applyBankFetch(bank: .rev, records: [record("other", cents: -100)], balance: nil, dateFrom: from,
                                        complete: false, fetchedAt: fetched, calendar: cal)
        #expect(cut?.report.removed == 0)
        #expect(ledger.state.movements.count == 2)
        #expect(ledger.state.links[.rev]?.lastSuccessAt == fetched)
    }

    @Test func importingHistoryTouchesNoAlertsOrUnread() {
        var ledger = Ledger(state: LedgerState(links: [.rev: link()]))
        let many = (0..<30).map { record("h\($0)", cents: -100 - $0, day: "2026-0\(1 + $0 % 9)-10T12:00:00Z") }
        _ = ledger.applyBankFetch(bank: .rev, records: many, balance: nil, dateFrom: iso("2025-11-20T00:00:00Z"),
                                  complete: true, fetchedAt: fetched, calendar: cal)
        #expect(ledger.state.unread.isEmpty)
    }

    // MARK: avisos de caducidad

    @Test func reminderTextsAndIDs() {
        let now = iso("2026-11-20T12:00:00Z")
        let until = iso("2027-05-19T10:00:00Z")
        let list = bankReminders(links: [.rev: link(until: "2027-05-19T10:00:00Z")], now: now, calendar: cal)
        #expect(list.count == 2)
        #expect(list[0].id == "bank-consent-rev")
        #expect(list[0].title == "Renueva la conexión con Revolut")
        #expect(list[0].body == "Caduca el 19 may. Tócalo y apruébalo en tu banco: es un minuto.")
        #expect(list[0].fireAt == consentReminderDate(validUntil: until, now: now, calendar: cal))
        #expect(list[1].id == "bank-expired-rev")
        #expect(list[1].title == "La conexión con Revolut ha caducado")
        #expect(list[1].body == "Renuévala para volver a ver sus movimientos y su saldo exacto.")
        #expect(list[1].fireAt == until)
    }

    @Test func noRenewReminderWhenTenDaysAlreadyPassed() {
        let now = iso("2026-11-20T12:00:00Z")
        let list = bankReminders(links: [.ima: link(until: "2026-11-25T10:00:00Z")], now: now, calendar: cal)
        #expect(list.map(\.id) == ["bank-expired-ima"])
    }

    @Test func expiredOrBrokenLinksHaveNoReminders() {
        let now = iso("2026-11-20T12:00:00Z")
        var broken = link()
        broken.problem = .consentExpired
        var keyBad = link()
        keyBad.problem = .keyRejected
        #expect(bankReminders(links: [.rev: broken, .ima: keyBad], now: now, calendar: cal).isEmpty)
        #expect(bankReminders(links: [.rev: link(until: "2026-11-01T10:00:00Z")], now: now, calendar: cal).isEmpty)
        #expect(bankReminders(links: [:], now: now, calendar: cal).isEmpty)
    }

    @Test func renewalMovesTheReminders() {
        let now = iso("2026-11-20T12:00:00Z")
        let old = link(until: "2026-12-01T10:00:00Z")
        let renewed = old.renewed(consentValidUntil: iso("2027-05-19T10:00:00Z"), at: now)
        let list = bankReminders(links: [.rev: renewed], now: now, calendar: cal)
        #expect(list.map(\.id) == ["bank-consent-rev", "bank-expired-rev"])
        #expect(list[1].fireAt == iso("2027-05-19T10:00:00Z"))
    }

    // MARK: R42 (revisión): saldo de solo contabilizado

    private func capture(_ cents: Int, at date: String, importedAt: String, linked: Bool = true, status: BankStatus = .pending) -> Movement {
        Movement(bank: .rev, amountCents: cents, merchant: "Mercadona", kind: .payment, source: .notification,
                 date: iso(date), bankRef: linked ? "r1" : nil, bankStatus: linked ? status : nil, importedAt: linked ? iso(importedAt) : nil)
    }

    private func ledger(reading: ManualBalance, _ movements: [Movement]) -> Ledger {
        Ledger(state: LedgerState(balances: [.rev: reading], movements: movements))
    }

    private let bookedReading = ManualBalance(
        cents: 10_000, setAt: iso("2026-11-20T12:59:00Z"), origin: .bank, fetchedAt: iso("2026-11-20T13:00:00Z"), countsPending: true)
    private let availableReading = ManualBalance(
        cents: 10_000, setAt: iso("2026-11-20T12:59:00Z"), origin: .bank, fetchedAt: iso("2026-11-20T13:00:00Z"))

    @Test func linkedCaptureOfPendingRecordCountsOnBookedOnlyReading() {
        let m = capture(-1250, at: "2026-11-20T12:30:00Z", importedAt: "2026-11-20T12:40:00Z")
        let booked = ledger(reading: bookedReading, [m]).balance(.rev)
        #expect(booked?.cents == 8_750)
        #expect(booked?.estimated == true)
        let available = ledger(reading: availableReading, [m]).balance(.rev)
        #expect(available?.cents == 10_000)
        #expect(available?.estimated == false)
    }

    @Test func rowIsNeverCountedTwiceOnBookedOnlyReading() {
        // Posterior a la lectura y desconocida al consultar: ya la suma `countsTowardBalance`; el pendiente no la repite.
        let m = capture(-1250, at: "2026-11-20T13:30:00Z", importedAt: "2026-11-20T13:30:00Z")
        #expect(ledger(reading: bookedReading, [m]).balance(.rev)?.cents == 8_750)
    }

    @Test func bookedRowsAndUnlinkedOldCapturesDoNotCountOnBookedOnlyReading() {
        let booked = capture(-1250, at: "2026-11-20T12:30:00Z", importedAt: "2026-11-20T12:40:00Z", status: .booked)
        let oldUnlinked = capture(-300, at: "2026-11-20T12:00:00Z", importedAt: "", linked: false)
        #expect(ledger(reading: bookedReading, [booked, oldUnlinked]).balance(.rev)?.cents == 10_000)
    }

    @Test func balanceAndTeQuedabanAgreeOnBookedOnlyReading() {
        let p1 = capture(-2000, at: "2026-11-20T12:00:00Z", importedAt: "2026-11-20T12:10:00Z")
        let p2 = capture(-1250, at: "2026-11-20T12:30:00Z", importedAt: "2026-11-20T12:40:00Z")
        let c = capture(-500, at: "2026-11-20T13:30:00Z", importedAt: "", linked: false)
        let l = ledger(reading: bookedReading, [p1, p2, c])
        let balance = l.balance(.rev)
        #expect(balance?.cents == 6_250)
        let after = Ledger.balancesAfter(bank: .rev, current: balance?.cents ?? 0, reading: bookedReading,
                                         movements: [c, p2, p1])
        #expect(after[c.id] == balance?.cents)
        #expect(after[p2.id] == 6_750)
        #expect(after[p1.id] == 8_000)
    }

    @Test func teQuedabanStopsBeforeAPlainReadingAsBefore() {
        let older = capture(-2000, at: "2026-11-20T12:00:00Z", importedAt: "2026-11-20T12:10:00Z")
        let newer = capture(-500, at: "2026-11-20T13:30:00Z", importedAt: "", linked: false)
        let after = Ledger.balancesAfter(bank: .rev, current: 9_500, reading: availableReading, movements: [newer, older])
        #expect(after[newer.id] == 9_500)
        #expect(after[older.id] == nil)
    }

    @Test func mixedReadingIsSummedEstimatedAndAddsNoPending() {
        var l = Ledger(state: LedgerState(links: [.rev: link()]))
        let reading = combineBalanceReadings([
            BalanceReading(cents: 6_000, at: iso("2026-11-20T12:59:00Z"), kind: .available),
            BalanceReading(cents: 4_000, at: iso("2026-11-20T12:59:00Z"), kind: .booked)])
        _ = l.applyBankFetch(bank: .rev, records: [record("p", cents: -2000, status: .pending)], balance: reading,
                             dateFrom: iso("2026-11-13T00:00:00Z"), complete: true, fetchedAt: fetched, calendar: cal)
        let b = l.state.balances[.rev]
        #expect(b?.countsPending == false)
        #expect(b?.forcedEstimate == true)
        #expect(l.balance(.rev)?.cents == 10_000)
        #expect(l.balance(.rev)?.estimated == true)
    }

    @Test func forcedEstimateSurvivesEncoding() throws {
        let b = ManualBalance(cents: 5, setAt: fetched, origin: .bank, forcedEstimate: true)
        #expect(try JSONDecoder().decode(ManualBalance.self, from: JSONEncoder().encode(b)) == b)
    }

    // MARK: fallos locales

    @Test func onlyBankFailuresAreRecorded() {
        #expect(isBankFailure(BankingClientError.offline))
        #expect(isBankFailure(BankingClientError.api(.rateLimited, code: nil)))
        #expect(isBankFailure(URLError(.notConnectedToInternet)))
        struct LocalError: Error {}
        #expect(!isBankFailure(LocalError()))
        #expect(!isBankFailure(CancellationError()))
    }
}
