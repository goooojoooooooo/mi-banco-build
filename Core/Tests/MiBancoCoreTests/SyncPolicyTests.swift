import Foundation
import Testing
@testable import MiBancoCore

private let madrid: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Madrid")!
    return c
}()

private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
    madrid.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
}

private let now = at(2026, 11, 20, 12)

private func link(validUntil: Date = at(2027, 5, 19)) -> BankLinkInfo {
    BankLinkInfo(connectedAt: at(2026, 11, 1), consentValidUntil: validUntil)
}

@Suite struct SyncPolicyTests {
    @Test func expiredSkipsFetch() {
        let l = link(validUntil: now.addingTimeInterval(-1))
        for t in [SyncTrigger.afterConnect, .appOpen, .background, .manual] {
            #expect(SyncPolicy.decide(l, trigger: t, now: now, calendar: madrid) == .skip(.consentExpired))
        }
    }

    @Test func notConnectedAndRejectedKey() {
        #expect(SyncPolicy.decide(nil, trigger: .appOpen, now: now, calendar: madrid) == .skip(.notConnected))
        var l = link()
        l.problem = .keyRejected
        #expect(SyncPolicy.decide(l, trigger: .manual, now: now, calendar: madrid) == .skip(.consentExpired))
    }

    @Test func afterConnectFetchesLongest() {
        #expect(SyncPolicy.decide(link(), trigger: .afterConnect, now: now, calendar: madrid)
            == .fetch(dateFrom: at(2025, 11, 20), strategy: .longest))
    }

    @Test func budget() {
        var l = link()
        for h in [8, 9, 10, 11] { l = l.recordingAttempt(at: at(2026, 11, 20, h)) }
        let expected = SyncDecision.skip(.budgetUsed(nextAt: at(2026, 11, 21, 8)))
        #expect(SyncPolicy.decide(l, trigger: .appOpen, now: now, calendar: madrid) == expected)
        #expect(SyncPolicy.decide(l, trigger: .manual, now: now, calendar: madrid) == expected)
    }

    @Test func freshOnOpen() {
        var l = link()
        l.lastSuccessAt = at(2026, 11, 20, 10, 30)
        l.historyLoaded = true
        #expect(SyncPolicy.decide(l, trigger: .appOpen, now: now, calendar: madrid) == .skip(.fresh))
        #expect(SyncPolicy.decide(l, trigger: .manual, now: now, calendar: madrid)
            == .fetch(dateFrom: at(2026, 11, 13), strategy: .standard))
    }

    @Test func manualDebounce() {
        var l = link()
        l.lastAttemptAt = at(2026, 11, 20, 11, 59)
        #expect(SyncPolicy.decide(l, trigger: .manual, now: now, calendar: madrid) == .skip(.fresh))
    }

    @Test func rateLimitBacksOff() {
        let l = link().recordingFailure(.rateLimited, at: now)
        #expect(l.backoffUntil == at(2026, 11, 20, 18))
        #expect(SyncPolicy.decide(l, trigger: .appOpen, now: now, calendar: madrid)
            == .skip(.waiting(until: at(2026, 11, 20, 18))))
        #expect(link().recordingFailure(.offline, at: now).backoffUntil == nil)
    }

    @Test func unknownIsNotRetriedAggressively() {
        let l = link().recordingFailure(.unknown, at: now)
        #expect(l.backoffUntil == now.addingTimeInterval(SyncPolicy.autoSpacing))
    }

    @Test func successClears() {
        let failed = link().recordingFailure(.rateLimited, at: now)
        let ok = failed.recordingSuccess(at: now)
        #expect(ok.problem == nil)
        #expect(ok.backoffUntil == nil)
        #expect(ok.historyLoaded)
        #expect(ok.lastSuccessAt == now)
    }

    @Test func logPrunes() {
        let l = link().recordingAttempt(at: at(2026, 11, 19, 11)).recordingAttempt(at: now)
        #expect(l.fetchLog.count == 1)
        #expect(l.lastAttemptAt == now)
    }

    @Test func reminderTenDaysBefore() {
        var utc = DateComponents(year: 2027, month: 5, day: 19, hour: 9)
        utc.timeZone = TimeZone(identifier: "UTC")
        let validUntil = Calendar(identifier: .gregorian).date(from: utc)!
        #expect(consentReminderDate(validUntil: validUntil, now: now, calendar: madrid) == at(2027, 5, 9, 10))
        #expect(consentReminderDate(validUntil: now.addingTimeInterval(5 * 86_400), now: now, calendar: madrid) == nil)
    }
}
