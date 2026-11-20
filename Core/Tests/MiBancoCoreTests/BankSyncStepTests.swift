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
        // Lo anterior a la lectura no tiene cifra, sea la lectura de la clase que sea.
        #expect(after[p2.id] == nil)
        #expect(after[p1.id] == nil)
    }

    @Test func olderPendingRowGetsNoTeQuedabanButCountsInBalance() {
        let booked = Movement(bank: .rev, amountCents: -3000, merchant: "Bar", kind: .payment, source: .bank,
                              date: iso("2026-11-20T12:45:00Z"), bankRef: "b", bankStatus: .booked,
                              importedAt: iso("2026-11-20T13:00:00Z"))
        let pending = capture(-2000, at: "2026-11-20T12:00:00Z", importedAt: "2026-11-20T12:10:00Z")
        let l = ledger(reading: bookedReading, [pending, booked])
        #expect(l.balance(.rev)?.cents == 8_000)
        let after = Ledger.balancesAfter(bank: .rev, current: 8_000, reading: bookedReading, movements: [booked, pending])
        #expect(after[pending.id] == nil)
        #expect(after[booked.id] == nil)
    }

    // MARK: autorizaciones viejas

    @Test func holdThatDisappearsFromCompleteFetchStopsCounting() {
        var l = Ledger(state: LedgerState(links: [.rev: link()]))
        let from = iso("2026-11-01T00:00:00Z")
        let first = BalanceReading(cents: 10_000, at: iso("2026-11-20T08:59:00Z"), kind: .booked)
        _ = l.applyBankFetch(bank: .rev, records: [record("hold", cents: -5000, status: .pending, day: "2026-11-10T12:00:00Z")],
                             balance: first, dateFrom: from, complete: true, fetchedAt: iso("2026-11-20T09:00:00Z"), calendar: cal)
        #expect(l.balance(.rev)?.cents == 5_000)
        let second = BalanceReading(cents: 10_000, at: iso("2026-11-20T12:59:00Z"), kind: .booked)
        _ = l.applyBankFetch(bank: .rev, records: [], balance: second, dateFrom: from, complete: true,
                             fetchedAt: fetched, calendar: cal)
        #expect(l.balance(.rev)?.cents == 10_000)
        #expect(l.state.movements.isEmpty)
    }

    @Test func pendingRowOlderThanThirtyDaysNeverCounts() {
        let old = Movement(bank: .rev, amountCents: -5000, merchant: "Hotel", kind: .payment, source: .bank,
                           date: iso("2026-10-05T12:00:00Z"), bankRef: "old", bankStatus: .pending,
                           importedAt: iso("2026-10-05T12:00:00Z"))
        #expect(ledger(reading: bookedReading, [old]).balance(.rev)?.cents == 10_000)
    }

    // MARK: pendiente que se apunta sin lectura nueva

    @Test func flipWithoutAdoptedReadingKeepsThePendingRowCounting() {
        var l = Ledger(state: LedgerState(links: [.rev: link()]))
        let from = iso("2026-11-13T00:00:00Z")
        let first = BalanceReading(cents: 10_000, at: iso("2026-11-20T11:59:00Z"), kind: .booked)
        _ = l.applyBankFetch(bank: .rev, records: [record("p", cents: -1250, status: .pending)], balance: first, dateFrom: from,
                             complete: true, fetchedAt: iso("2026-11-20T12:00:00Z"), calendar: cal)
        #expect(l.balance(.rev)?.cents == 8_750)
        // La consulta apunta el pago pero no trae lectura de saldo.
        _ = l.applyBankFetch(bank: .rev, records: [record("p", cents: -1250, status: .booked)], balance: nil, dateFrom: from,
                             complete: true, fetchedAt: iso("2026-11-20T12:30:00Z"), calendar: cal)
        #expect(l.state.movements.first?.bankStatus == .pending)
        #expect(l.balance(.rev)?.cents == 8_750)
        #expect(l.balance(.rev)?.estimated == true)
        // La siguiente trae lectura contabilizada que ya lo incluye.
        let next = BalanceReading(cents: 8_750, at: iso("2026-11-20T12:59:00Z"), kind: .booked)
        _ = l.applyBankFetch(bank: .rev, records: [record("p", cents: -1250, status: .booked)], balance: next, dateFrom: from,
                             complete: true, fetchedAt: fetched, calendar: cal)
        #expect(l.state.movements.first?.bankStatus == .booked)
        #expect(l.balance(.rev)?.cents == 8_750)
        #expect(l.balance(.rev)?.estimated == true)
    }

    @Test func flipUnderNewKeyWithoutReadingIsHeldToo() {
        var l = Ledger(state: LedgerState(links: [.rev: link()]))
        let from = iso("2026-11-13T00:00:00Z")
        let first = BalanceReading(cents: 10_000, at: iso("2026-11-20T11:59:00Z"), kind: .booked)
        _ = l.applyBankFetch(bank: .rev, records: [record("p", cents: -1250, status: .pending)], balance: first, dateFrom: from,
                             complete: true, fetchedAt: iso("2026-11-20T12:00:00Z"), calendar: cal)
        _ = l.applyBankFetch(bank: .rev, records: [record("b", cents: -1250, status: .booked)], balance: nil, dateFrom: from,
                             complete: true, fetchedAt: iso("2026-11-20T12:30:00Z"), calendar: cal)
        #expect(l.state.movements.count == 1)
        #expect(l.state.movements.first?.bankStatus == .pending)
        #expect(l.balance(.rev)?.cents == 8_750)
    }

    @Test func bookedTwinInSameBatchCountsThePaymentOnce() {
        var l = Ledger(state: LedgerState(links: [.rev: link()]))
        let reading = BalanceReading(cents: 10_000, at: iso("2026-11-20T12:59:00Z"), kind: .booked)
        _ = l.applyBankFetch(
            bank: .rev, records: [record("p", cents: -1250, status: .pending), record("b", cents: -1250, status: .booked)],
            balance: reading, dateFrom: iso("2026-11-13T00:00:00Z"), complete: true, fetchedAt: fetched, calendar: cal)
        // El pago apuntado ya está en la lectura; su gemelo pendiente no suma otra vez.
        #expect(l.balance(.rev)?.cents == 10_000)
        #expect(l.balance(.rev)?.estimated == true)
    }

    // MARK: sesión ilegible

    @Test func onlyALockedKeychainIsSilent() {
        #expect(recordsSessionReadFailure(.deviceLocked) == false)
        #expect(recordsSessionReadFailure(.unreadable) == true)
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

    @Test func sameSessionRecordsAndDeletesOnlyOnExpiry() {
        let l = link()
        let at = iso("2026-11-20T13:00:00Z")
        #expect(syncFailureAction(problem: .consentExpired, startedSessionID: "s1", currentSessionID: "s1", link: l, attemptAt: at)
            == .record(deleteSession: true))
        #expect(syncFailureAction(problem: .offline, startedSessionID: "s1", currentSessionID: "s1", link: l, attemptAt: at)
            == .record(deleteSession: false))
    }

    @Test func reconnectedDuringSyncDropsTheOutcome() {
        let at = iso("2026-11-20T13:00:00Z")
        // Otra sesión en el Llavero: se conserva y no se anota nada.
        #expect(syncFailureAction(problem: .consentExpired, startedSessionID: "old", currentSessionID: "new", link: link(), attemptAt: at)
            == .drop)
        // La conexión se renovó después del intento.
        let renewed = link().renewed(consentValidUntil: iso("2027-06-01T10:00:00Z"), at: iso("2026-11-20T13:00:05Z"))
        #expect(syncFailureAction(problem: .consentExpired, startedSessionID: "s1", currentSessionID: "s1", link: renewed, attemptAt: at)
            == .drop)
        // Desconectada o sin sesión nueva ni vieja.
        #expect(syncFailureAction(problem: .offline, startedSessionID: "s1", currentSessionID: "s1", link: nil, attemptAt: at) == .drop)
        #expect(syncFailureAction(problem: .offline, startedSessionID: "s1", currentSessionID: nil, link: link(), attemptAt: at) == .drop)
    }

    @Test func noSessionAtStartRecordsUnlessOneAppearedMeanwhile() {
        let at = iso("2026-11-20T13:00:00Z")
        #expect(syncFailureAction(problem: .consentExpired, startedSessionID: nil, currentSessionID: nil, link: link(), attemptAt: at)
            == .record(deleteSession: true))
        #expect(syncFailureAction(problem: .consentExpired, startedSessionID: nil, currentSessionID: "new", link: link(), attemptAt: at)
            == .drop)
    }

    @Test func onlyBankFailuresAreRecorded() {
        #expect(isBankFailure(BankingClientError.offline))
        #expect(isBankFailure(BankingClientError.api(.rateLimited, code: nil)))
        #expect(isBankFailure(URLError(.notConnectedToInternet)))
        struct LocalError: Error {}
        #expect(!isBankFailure(LocalError()))
        #expect(!isBankFailure(CancellationError()))
    }

    // MARK: R46 gemelo del pendiente

    private func bankRow(_ cents: Int, _ status: BankStatus, date: String, imported: String, merchant: String? = "Cafe",
                         ref: String) -> Movement {
        Movement(bank: .rev, amountCents: cents, merchant: merchant, kind: .payment, source: .bank, date: iso(date),
                 bankRef: ref, bankStatus: status, importedAt: iso(imported), dayOnly: true)
    }

    @Test func yesterdaysBookedRowIsNotTheTwinOfTodaysPending() {
        let booked = bankRow(-240, .booked, date: "2026-11-19T12:00:00Z", imported: "2026-11-19T18:00:00Z", ref: "b")
        let pending = bankRow(-240, .pending, date: "2026-11-20T12:00:00Z", imported: "2026-11-20T08:00:00Z", ref: "p")
        #expect(ledger(reading: bookedReading, [booked, pending]).balance(.rev)?.cents == 9_760)
    }

    @Test func yesterdaysBookedRowSeenInTheSameFetchIsNotATwinEither() {
        let booked = bankRow(-240, .booked, date: "2026-11-19T12:00:00Z", imported: "2026-11-20T13:00:00Z", ref: "b")
        let pending = bankRow(-240, .pending, date: "2026-11-20T12:00:00Z", imported: "2026-11-20T13:00:00Z", ref: "p")
        #expect(ledger(reading: bookedReading, [booked, pending]).balance(.rev)?.cents == 9_760)
    }

    @Test func bookedRowFirstSeenBeforeThePendingIsNotItsTwin() {
        let booked = bankRow(-240, .booked, date: "2026-11-20T12:00:00Z", imported: "2026-11-20T07:00:00Z", ref: "b")
        let pending = bankRow(-240, .pending, date: "2026-11-20T12:00:00Z", imported: "2026-11-20T08:00:00Z", ref: "p")
        #expect(ledger(reading: bookedReading, [booked, pending]).balance(.rev)?.cents == 9_760)
    }

    @Test func differentMerchantIsNotATwinButAccentsAndCaseFold() {
        let booked = bankRow(-240, .booked, date: "2026-11-20T12:00:00Z", imported: "2026-11-20T13:00:00Z", merchant: "CAFÉ", ref: "b")
        let other = bankRow(-240, .pending, date: "2026-11-20T12:00:00Z", imported: "2026-11-20T08:00:00Z", merchant: "Taxi", ref: "p")
        #expect(ledger(reading: bookedReading, [booked, other]).balance(.rev)?.cents == 9_760)
        let same = bankRow(-240, .pending, date: "2026-11-20T12:00:00Z", imported: "2026-11-20T08:00:00Z", merchant: "cafe", ref: "p2")
        #expect(ledger(reading: bookedReading, [booked, same]).balance(.rev)?.cents == 10_000)
    }

    @Test func twoPendingRowsOneBookedTwinTwinsExactlyOne() {
        let p1 = bankRow(-240, .pending, date: "2026-11-20T12:00:00Z", imported: "2026-11-20T08:00:00Z", ref: "p1")
        let p2 = bankRow(-240, .pending, date: "2026-11-20T12:30:00Z", imported: "2026-11-20T08:00:00Z", ref: "p2")
        let booked = bankRow(-240, .booked, date: "2026-11-20T12:10:00Z", imported: "2026-11-20T12:50:00Z", ref: "b")
        let twinned = Ledger.twinnedPending([p1, p2, booked], bank: .rev, base: bookedReading)
        #expect(twinned == [p1.id])
        #expect(ledger(reading: bookedReading, [p1, p2, booked]).balance(.rev)?.cents == 9_760)
    }

    // MARK: R47 ventana de la consulta

    private func day(_ d: Int, _ time: String = "13:00:00") -> Date {
        iso("2026-11-" + (d < 10 ? "0\(d)" : "\(d)") + "T" + time + "Z")
    }

    @Test func fetchWindowReachesTheOldestPendingRow() {
        var l = link()
        l.lastSuccessAt = iso("2026-11-19T10:00:00Z")
        let now = iso("2026-11-20T12:00:00Z")
        func from(_ pending: Date?) -> Date? {
            if case let .fetch(dateFrom, _) = SyncPolicy.decide(l, trigger: .appOpen, now: now, calendar: cal, oldestPending: pending) {
                return dateFrom
            }
            return nil
        }
        let usual = from(nil)
        #expect(from(iso("2026-11-03T12:00:00Z")) == iso("2026-11-02T23:00:00Z"))
        // Un pendiente más reciente que la ventana habitual no la cambia.
        #expect(from(iso("2026-11-18T12:00:00Z")) == usual)
        // Nunca más atrás del máximo de la política.
        let floor: Date? = {
            if case let .fetch(dateFrom, _) = SyncPolicy.decide(l, trigger: .afterConnect, now: now, calendar: cal) { return dateFrom }
            return nil
        }()
        #expect(from(iso("2024-01-01T12:00:00Z")) == floor)
        #expect(banksToFetch(links: [.rev: l], trigger: .appOpen, now: now, calendar: cal,
                             oldestPending: [.rev: iso("2026-11-03T12:00:00Z")]).first?.dateFrom == iso("2026-11-02T23:00:00Z"))
    }

    @Test func heldFlipSurvivesNineDaysWithoutAReading() {
        let capture = Movement(bank: .rev, amountCents: -1250, merchant: "Mercadona", kind: .payment, source: .notification,
                               date: iso("2026-11-01T11:30:00Z"))
        var l = Ledger(state: LedgerState(movements: [capture], links: [.rev: link()]))
        func pendingRecord(_ status: BankStatus) -> BankRecord {
            record("p", cents: -1250, status: status, day: "2026-11-01T12:00:00Z")
        }
        // Día 1: el pago está pendiente y la lectura es de solo contabilizado.
        _ = l.applyBankFetch(
            bank: .rev, records: [pendingRecord(.pending)],
            balance: BalanceReading(cents: 10_000, at: day(1, "12:59:00"), kind: .booked),
            dateFrom: iso("2026-10-01T00:00:00Z"), complete: true, fetchedAt: day(1), calendar: cal)
        #expect(l.balance(.rev)?.cents == 8_750)
        // Días 2 a 9: el banco ya lo da apuntado pero no hay lectura adoptable: se sostiene.
        for d in 2...9 {
            _ = l.applyBankFetch(bank: .rev, records: [pendingRecord(.booked)], balance: nil,
                                 dateFrom: iso("2026-10-01T00:00:00Z"), complete: true, fetchedAt: day(d), calendar: cal)
        }
        #expect(l.state.movements.first?.bankStatus == .pending)
        #expect(l.balance(.rev)?.cents == 8_750)
        // Día 10: la ventana llega hasta el pendiente más antiguo, así que su registro apuntado vuelve en el lote.
        let now = day(10)
        guard case let .fetch(dateFrom, _) = SyncPolicy.decide(
            l.state.links[.rev], trigger: .appOpen, now: now, calendar: cal, oldestPending: l.oldestPendingBankRow(.rev))
        else { Issue.record("debía consultar"); return }
        let batch = [pendingRecord(.booked)].filter { $0.timing.date >= dateFrom }
        _ = l.applyBankFetch(bank: .rev, records: batch,
                             balance: BalanceReading(cents: 8_750, at: day(10, "12:59:00"), kind: .booked),
                             dateFrom: dateFrom, complete: true, fetchedAt: now, calendar: cal)
        #expect(l.state.movements.count == 1)
        let row = l.state.movements.first
        #expect(row?.source == .notification)
        #expect(row?.bankRef == "p")
        #expect(row?.bankStatus == .booked)
        #expect(l.balance(.rev)?.cents == 8_750)
    }

    @Test func pendingRowOlderThanTheWindowIsKeptButDoesNotCount() {
        let old = Movement(bank: .rev, amountCents: -5000, merchant: "Hotel", kind: .payment, source: .bank,
                           date: iso("2025-01-01T12:00:00Z"), bankRef: "old", bankStatus: .pending,
                           importedAt: iso("2025-01-01T12:00:00Z"))
        var l = Ledger(state: LedgerState(movements: [old], links: [.rev: link()]))
        let from = iso("2025-11-20T00:00:00Z")
        _ = l.applyBankFetch(bank: .rev, records: [], balance: BalanceReading(cents: 10_000, at: iso("2026-11-20T12:59:00Z"), kind: .booked),
                             dateFrom: from, complete: true, fetchedAt: fetched, calendar: cal)
        #expect(l.state.movements.count == 1)
        #expect(l.balance(.rev)?.cents == 10_000)
    }

    // MARK: R48 saldo de cierre

    private func closing(_ reference: String?, change: String? = nil) -> [EBBalance] {
        [EBBalance(balanceAmount: EBAmount(currency: "EUR", amount: "100.00"), balanceType: "CLBD",
                   lastChangeDateTime: change, referenceDate: reference)]
    }

    @Test func closingBalanceOfYesterdayIsStampedAtTheEndOfThatDay() {
        let fetchedAt = iso("2026-11-20T10:00:00Z")
        let reading = chooseBalanceReading(closing("2026-11-19"), fetchedAt: fetchedAt)
        #expect(reading?.at == iso("2026-11-19T23:00:00Z"))
        let payment = Movement(bank: .rev, amountCents: -1250, merchant: "Mercadona", kind: .payment, source: .notification,
                               date: iso("2026-11-20T08:00:00Z"))
        var l = Ledger(state: LedgerState(movements: [payment], links: [.rev: link()]))
        _ = l.applyBankFetch(bank: .rev, records: [], balance: reading, dateFrom: iso("2026-11-13T00:00:00Z"), complete: true,
                             fetchedAt: fetchedAt, calendar: cal)
        #expect(l.balance(.rev)?.cents == 8_750)
    }

    @Test func sameClosingBalanceFetchedTwiceIsAdoptedOnce() {
        var l = Ledger(state: LedgerState(links: [.rev: link()]))
        let from = iso("2026-11-13T00:00:00Z")
        let t1 = iso("2026-11-20T10:00:00Z"), t2 = iso("2026-11-20T10:30:00Z")
        let first = l.applyBankFetch(bank: .rev, records: [], balance: chooseBalanceReading(closing("2026-11-19"), fetchedAt: t1),
                                     dateFrom: from, complete: true, fetchedAt: t1, calendar: cal)
        let second = l.applyBankFetch(bank: .rev, records: [], balance: chooseBalanceReading(closing("2026-11-19"), fetchedAt: t2),
                                      dateFrom: from, complete: true, fetchedAt: t2, calendar: cal)
        #expect(first?.balanceAdopted == true)
        #expect(second?.balanceAdopted == false)
        #expect(l.state.balances[.rev]?.fetchedAt == t1)
    }

    @Test func closingBalanceOfTodayIsStampedAtTheFetchTime() {
        let fetchedAt = iso("2026-11-20T10:00:00Z")
        #expect(chooseBalanceReading(closing("2026-11-20"), fetchedAt: fetchedAt)?.at == fetchedAt)
        #expect(chooseBalanceReading(closing(nil), fetchedAt: fetchedAt)?.at == fetchedAt)
        // La hora de cambio, si la hay, manda sobre el día de referencia.
        #expect(chooseBalanceReading(closing("2026-11-19", change: "2026-11-20T09:00:00Z"), fetchedAt: fetchedAt)?.at
            == iso("2026-11-20T09:00:00Z"))
    }

    // MARK: disco

    @Test func failingStoreThrowsAndLeavesTheFileUntouched() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mb-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let blocker = dir.appendingPathComponent("blocker")
        try Data("x".utf8).write(to: blocker)
        // Un archivo donde debería ir la carpeta del libro: guardar falla.
        let store = FileStore(directory: blocker)
        #expect(throws: (any Error).self) { _ = try store.update { _ in 1 } }
        #expect(try Data(contentsOf: blocker) == Data("x".utf8))
    }
}
