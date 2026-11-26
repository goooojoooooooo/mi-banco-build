import Foundation
import Testing
@testable import MiBancoCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Madrid")!
    c.locale = Locale(identifier: "es_ES")
    return c
}()

private func date(_ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, year: Int = 2026) -> Date {
    cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private func nov(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date { date(11, day, hour, minute) }

private func ledger(_ movements: [Movement], balances: [BankID: ManualBalance] = [:],
                    links: [BankID: BankLinkInfo] = [:]) -> LedgerState {
    LedgerState(balances: balances, movements: movements, unread: [], links: links)
}

private func linked(_ until: Date, problem: SyncProblem? = nil, lastSuccess: Date? = nov(26, 9)) -> LedgerState {
    var link = BankLinkInfo(connectedAt: date(9, 1), consentValidUntil: until)
    link.problem = problem
    link.lastSuccessAt = lastSuccess
    return ledger([], links: [.rev: link])
}

private func health(_ s: LedgerState, _ h: NyxAppHealth = NyxAppHealth(), memory: NyxMemory = NyxMemory(),
                    now: Date = nov(26, 12)) -> [NyxObservation] {
    nyxHealthObservations(state: s, health: h, memory: memory, now: now, calendar: cal)
}

@Suite struct NyxHealthWatchTests {
    @Test func conexionQueCaduca() {
        #expect(health(linked(nov(29, 12))).contains { $0.id == "bankExpiring|rev|2026-11-29|tarde" && $0.priority == .normal })
        #expect(health(linked(date(12, 5))).contains { $0.id == "bankExpiring|rev|2026-12-05|pronto" && $0.priority == .quiet })
        #expect(!health(linked(date(12, 10))).contains { $0.situation == .bankExpiring })
        #expect(health(linked(date(12, 10), problem: .consentExpired)).contains { $0.situation == .bankExpired && $0.priority == .urgent })
        #expect(health(linked(nov(25))).contains { $0.situation == .bankExpired })
    }

    @Test func bancoSinActualizar() {
        #expect(health(linked(date(12, 20), lastSuccess: nov(24, 11))).contains { $0.situation == .bankStale })
        #expect(!health(linked(date(12, 20), lastSuccess: nov(24, 13))).contains { $0.situation == .bankStale })
        #expect(health(linked(date(12, 20), lastSuccess: nil)).contains { $0.situation == .bankStale })
    }

    @Test func avisosQueNoLleganYQueNuncaLlegaron() {
        var s = ledger([], balances: [.ima: ManualBalance(cents: 5000, setAt: nov(20), fromBank: false)])
        s.guideSightings[GuideTrack.revolut.rawValue] = GuideSighting(first: date(10, 1), last: nov(10))
        s.guideSightings[GuideTrack.walletRevolut.rawValue] = GuideSighting(first: date(10, 1), last: date(10, 2))
        var mem = NyxMemory()
        mem.firstUseAt = nov(18)
        let out = health(s, memory: mem)
        #expect(out.contains { $0.id == "alertsSilent|revolut|2026-11-10" && $0.facts.days == 16 })
        #expect(!out.contains { $0.facts.track == GuideTrack.walletRevolut.rawValue })
        #expect(out.contains { $0.id == "alertsNeverArrived|walletImagin" })
        mem.firstUseAt = nov(20)
        #expect(!health(s, memory: mem).contains { $0.situation == .alertsNeverArrived })
    }

    @Test func avisosApagadosYAppQueCaduca() {
        #expect(health(ledger([]), NyxAppHealth(notificationsAllowed: false)).contains { $0.situation == .notificationsOff && $0.priority == .normal })
        #expect(!health(ledger([]), NyxAppHealth(notificationsAllowed: nil)).contains { $0.situation == .notificationsOff })
        #expect(health(ledger([]), NyxAppHealth(appExpiresAt: nov(27, 10))).contains { $0.id == "appExpiring|2026-11-27|tarde" && $0.priority == .urgent })
        #expect(health(ledger([]), NyxAppHealth(appExpiresAt: nov(28, 10))).contains { $0.id == "appExpiring|2026-11-28|pronto" && $0.priority == .normal })
        #expect(!health(ledger([]), NyxAppHealth(appExpiresAt: nov(29))).contains { $0.situation == .appExpiring })
        #expect(!health(ledger([]), NyxAppHealth(appExpiresAt: nov(26, 11))).contains { $0.situation == .appExpiring })
    }

    @Test func fechaDeCaducidadDelPerfil() {
        let plist = #"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>ExpirationDate</key><date>2026-12-01T10:00:00Z</date></dict></plist>"#
        let data = Data("\u{0}\u{1}basura".utf8) + Data(plist.utf8) + Data("firma".utf8)
        #expect(provisioningExpiry(fromEmbeddedProfile: data) == ISO8601DateFormatter().date(from: "2026-12-01T10:00:00Z"))
        #expect(provisioningExpiry(fromEmbeddedProfile: Data("nada".utf8)) == nil)
    }
}
