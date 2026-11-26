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

private func pay(_ cents: Int, _ merchant: String?, _ when: Date, bank: BankID = .rev,
                 source: Movement.Source = .notification) -> Movement {
    Movement(bank: bank, amountCents: -cents, merchant: merchant, kind: .payment, source: source, date: when)
}

private func ledger(_ movements: [Movement], balances: [BankID: ManualBalance] = [:],
                    settings: AlertSettings = AlertSettings(), muted: Set<String> = [],
                    budgets: Budgets = Budgets(), links: [BankID: BankLinkInfo] = [:],
                    overrides: [String: SpendingCategory] = [:]) -> LedgerState {
    LedgerState(balances: balances, movements: movements, unread: [], alertSettings: settings,
                mutedMerchants: muted, categoryOverrides: overrides, budgets: budgets, links: links)
}

private func obs(_ subject: String, _ situation: NyxSituation = .shortfall, merchant: String? = nil,
                 at: Date = nov(26)) -> NyxObservation {
    NyxObservation(situation: situation, subject: subject, priority: .normal, observedAt: at,
                   facts: NyxFacts(merchant: merchant))
}

@Suite struct NyxMemoryTests {
    @Test func idEsSituacionYSujeto() {
        let o = NyxObservation(situation: .shortfall, subject: "rev|spotify|2026-11-27", priority: .urgent,
                               observedAt: nov(26), facts: NyxFacts())
        #expect(o.id == "shortfall|rev|spotify|2026-11-27")
        #expect(NyxSituation.subscriptionUp.mirrors == .subscriptionPriceChange)
        #expect(NyxSituation.subscriptionDown.mirrors == .subscriptionPriceChange)
        #expect(NyxSituation.shortfall.mirrors == nil)
        #expect(NyxSituation.salary.alertSwitch == .income)
        #expect(NyxAlertSwitch.budgets.turnedOff(AlertSettings()).budgets == false)
        #expect(assistantName == "Nyx")
    }

    @Test func registrarNoDuplicaYCuentaInterrupciones() {
        var m = NyxMemory()
        m.record(obs("a"), delivery: .notification, now: nov(26, 9))
        m.record(obs("a"), delivery: .banner, now: nov(26, 10))
        #expect(m.entries.count == 1 && m.entries[0].delivery == .notification && m.entries[0].status == .new)
        #expect(m.interruptions == [nov(26, 9)])
        m.record(obs("b"), delivery: .viaAvisos, now: nov(26, 11))
        #expect(m.interruptions.count == 1)
        #expect(m.entries.map(\.id) == [obs("b").id, obs("a").id])
        #expect(m.newCount == 2)
        m.markAllSeen(now: nov(26, 12))
        #expect(m.newCount == 0)
        #expect(m.entries.allSatisfy { $0.status == .seen && $0.statusAt == nov(26, 12) })
    }

    @Test func descartarApuntaSituacionYComercio() {
        var m = NyxMemory()
        m.record(obs("x", .unusualPayment, merchant: "Mercadona"), delivery: .list, now: nov(26, 9))
        m.mark(obs("x", .unusualPayment).id, .dismissed, now: nov(26, 10))
        #expect(m.dismissals["unusualPayment"] == [nov(26, 10)])
        #expect(m.merchantDismissals["mercadona"] == [nov(26, 10)])
        #expect(m.entries[0].status == .dismissed && m.entries[0].statusAt == nov(26, 10))
        m.mark(obs("x", .unusualPayment).id, .done, now: nov(26, 11))
        #expect(m.actions["unusualPayment"] == [nov(26, 11)] && m.merchantActions["mercadona"] == [nov(26, 11)])
    }

    @Test func pruneRespetaPlazosYTope() {
        var m = NyxMemory()
        m.record(obs("old", at: nov(1)), delivery: .list, now: nov(1))
        for i in 0..<105 { m.record(obs("n\(i)", at: nov(25)), delivery: .list, now: nov(25)) }
        m.interruptions = [nov(24, 11), nov(26, 9)]
        m.prune(now: nov(26, 12))
        #expect(!m.knows(obs("old", at: nov(1)).id))
        #expect(m.entries.count == 100)
        #expect(m.interruptions == [nov(26, 9)])

        // Retención de 30 días independiente del tope de 100 entradas.
        var aged = NyxMemory()
        aged.record(obs("viejo", at: date(10, 20)), delivery: .list, now: date(10, 20))
        aged.record(obs("reciente", at: nov(20)), delivery: .list, now: nov(20))
        aged.prune(now: nov(26, 12))
        #expect(!aged.knows(obs("viejo", at: date(10, 20)).id))
        #expect(aged.knows(obs("reciente", at: nov(20)).id))
    }

    @Test func pruneQuitaFechasFuturas() {
        var m = NyxMemory()
        m.interruptions = [nov(28)]
        m.dismissals["shortfall"] = [nov(29)]
        m.lastInterruption["shortfall"] = nov(29)
        m.prune(now: nov(26))
        #expect(m.interruptions.isEmpty && (m.dismissals["shortfall"] ?? []).isEmpty && m.lastInterruption["shortfall"] == nil)
    }

    @Test func memoriaDeUnaVersionNuevaSeLeeLoQueSeEntiende() throws {
        let sample = NyxEntry(observation: obs("ok"), delivery: .list, status: .new, statusAt: nov(26))
        let validEntryJSON = try #require(String(data: try JSONEncoder().encode(sample), encoding: .utf8))
        let json = #"{"entries":[{"observation":{"id":"zzz|1","situation":"zzz","priority":2,"observedAt":0,"facts":{},"viaInstantAlert":false},"delivery":"list","status":"new","statusAt":0},"# + validEntryJSON + #"],"futureKey":1,"lastLookAt":0}"#
        let m = try JSONDecoder().decode(NyxMemory.self, from: Data(json.utf8))
        #expect(m.entries.count == 1)
        #expect(m.entries[0].id == sample.id)
        #expect(m.lastLookAt != nil)
        #expect(try JSONDecoder().decode(NyxMemory.self, from: Data("{}".utf8)) == NyxMemory())
    }

    @Test func memoriaRotaEmpiezaDeCero() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("no es json".utf8).write(to: dir.appendingPathComponent("nyx-memory.json"))
        let store = NyxMemoryStore(directory: dir)
        #expect(store.loadRecovering() == NyxMemory())
        try store.update { $0.lastLookAt = nov(26) }
        #expect(try store.load().lastLookAt == nov(26))
        try store.delete()
        #expect(try store.load() == NyxMemory())
        try store.delete()
    }

    @Test func movimientosNuevosDesdeLaUltimaVez() {
        let capture = pay(1000, "Bar", nov(26, 10))
        let early = pay(1000, "Bar", nov(26, 8))
        var lateRow = pay(500, "Kiosko", nov(25, 12), source: .bank)
        lateRow.importedAt = nov(26, 10)
        var oldRow = pay(500, "Kiosko", nov(10), source: .bank)
        oldRow.importedAt = nov(26, 10)
        var mine = pay(700, "Tienda", nov(26, 11))
        mine.flaggedNotMine = true
        let s = ledger([early, capture, lateRow, mine, oldRow])
        #expect(Set(nyxNewMovementIDs(in: s, since: nov(26, 9), now: nov(26, 12))) == [capture.id, lateRow.id])
        #expect(nyxNewMovementIDs(in: s, since: nil, now: nov(26, 12)).contains(early.id))
    }
}
