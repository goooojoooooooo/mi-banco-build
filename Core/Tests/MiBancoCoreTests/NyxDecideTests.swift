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

private func ob(_ situation: NyxSituation, _ subject: String, _ priority: NyxPriority,
                merchant: String? = nil, via: Bool = false) -> NyxObservation {
    NyxObservation(situation: situation, subject: subject, priority: priority, observedAt: nov(26, 11),
                   facts: NyxFacts(merchant: merchant), viaInstantAlert: via)
}

private func decide(_ o: [NyxObservation], _ m: NyxMemory = NyxMemory(), talk: NyxTalkLevel = .whenItMatters,
                    moment: NyxMoment = .background, active: Bool = false, notificationsAllowed: Bool = true,
                    now: Date = nov(26, 12), settings: AlertSettings = AlertSettings(),
                    muted: Set<String> = []) -> [String: NyxDelivery] {
    Dictionary(uniqueKeysWithValues: nyxDecide(o, memory: m, talk: talk, moment: moment, appActive: active,
                                               notificationsAllowed: notificationsAllowed, mutedMerchants: muted,
                                               alertSettings: settings, now: now, calendar: cal)
        .map { ($0.observation.id, $0.delivery) })
}

@Suite struct NyxDecideTests {
    @Test func formaSegunMomentoYHora() {
        let o = ob(.shortfall, "a", .urgent)
        #expect(decide([o])[o.id] == .notification)
        #expect(decide([o], active: true)[o.id] == .banner)
        #expect(decide([o], now: nov(26, 23, 30))[o.id] == .silentNotification)
        #expect(decide([o], now: nov(27, 7, 59))[o.id] == .silentNotification)
        #expect(decide([ob(.notificationsOff, "w", .normal)])[ob(.notificationsOff, "w", .normal).id] == .list)
        #expect(decide([ob(.notificationsOff, "w", .normal)], active: true)[ob(.notificationsOff, "w", .normal).id] == .banner)

        // Bordes exactos de horas tranquilas (23:00–08:00).
        #expect(!nyxIsQuietHour(nov(26, 22, 59), calendar: cal))
        #expect(nyxIsQuietHour(nov(26, 23, 0), calendar: cal))
        #expect(nyxIsQuietHour(nov(27, 7, 59), calendar: cal))
        #expect(!nyxIsQuietHour(nov(27, 8, 0), calendar: cal))
        #expect(decide([o], now: nov(26, 22, 59))[o.id] == .notification)
        #expect(decide([o], now: nov(26, 23, 0))[o.id] == .silentNotification)
        #expect(decide([o], now: nov(27, 7, 59))[o.id] == .silentNotification)
        #expect(decide([o], now: nov(27, 8, 0))[o.id] == .notification)
    }

    @Test func unSoloBannerPorTandaConLaAppAbierta() {
        let u = ob(.shortfall, "u", .urgent)
        let n1 = ob(.budgetOffPace, "n1", .normal)
        let n2 = ob(.salary, "n2", .normal)
        let decisions = nyxDecide([n2, u, n1], memory: NyxMemory(), talk: .whenItMatters, moment: .open, appActive: true,
                                  mutedMerchants: [], alertSettings: AlertSettings(), now: nov(26, 12), calendar: cal)
        let byID = Dictionary(uniqueKeysWithValues: decisions.map { ($0.observation.id, $0.delivery) })
        #expect(byID[u.id] == .banner)
        #expect(byID[n1.id] == .list)
        #expect(byID[n2.id] == .list)

        var mem = NyxMemory()
        mem.apply(decisions, now: nov(26, 12))
        #expect(mem.interruptions.count == 1)
        #expect(Set(mem.lastInterruption.keys) == ["shortfall"])
        #expect(mem.entry(n1.id)?.delivery == .list)
        #expect(mem.entry(n2.id)?.delivery == .list)
    }

    @Test func sinPermisoDeAvisosBajaAListaSinGastarCupoNiPausa() {
        let u = ob(.shortfall, "u", .urgent)
        let n = ob(.budgetOffPace, "n", .normal)
        let dayDecisions = nyxDecide([u, n], memory: NyxMemory(), talk: .whenItMatters, moment: .background, appActive: false,
                                     notificationsAllowed: false, mutedMerchants: [], alertSettings: AlertSettings(),
                                     now: nov(26, 12), calendar: cal)
        #expect(dayDecisions.allSatisfy { $0.delivery == .list })

        let quietDecisions = nyxDecide([u], memory: NyxMemory(), talk: .whenItMatters, moment: .background, appActive: false,
                                       notificationsAllowed: false, mutedMerchants: [], alertSettings: AlertSettings(),
                                       now: nov(26, 23, 30), calendar: cal)
        #expect(quietDecisions.map(\.delivery) == [.list])

        var mem = NyxMemory()
        mem.apply(dayDecisions, now: nov(26, 12))
        #expect(mem.interruptions.isEmpty)
        #expect(mem.lastInterruption.isEmpty)
        #expect(mem.entry(u.id)?.delivery == .list)
        #expect(mem.entry(n.id)?.delivery == .list)

        // Ni cupo ni pausa quedaron gastados: otra observación de la misma situación entra normal si ya hay permiso o app abierta.
        let later = ob(.budgetOffPace, "n2", .normal)
        #expect(decide([later], mem, active: false, notificationsAllowed: true, now: nov(26, 12, 30))[later.id] == .notification)
        // Con la app abierta el aviso interno `.banner` sigue saliendo aunque los avisos del sistema estén apagados.
        #expect(decide([later], mem, active: true, notificationsAllowed: false, now: nov(26, 12, 30))[later.id] == .banner)
    }

    @Test func descartarSuggestMuteNoVuelveAProponerSilenciar() {
        var m = NyxMemory()
        let p1 = NyxObservation(situation: .unusualPayment, subject: "p1", priority: .normal, observedAt: date(9, 20),
                                facts: NyxFacts(merchant: "Glovo"))
        let p2 = NyxObservation(situation: .unusualPayment, subject: "p2", priority: .normal, observedAt: date(10, 15),
                                facts: NyxFacts(merchant: "Glovo"))
        m.record(p1, delivery: .list, now: date(9, 20))
        m.mark(p1.id, .dismissed, now: date(9, 20))
        m.record(p2, delivery: .list, now: date(10, 15))
        m.mark(p2.id, .dismissed, now: date(10, 15))

        let first = nyxLearningObservations(memory: m, alertSettings: AlertSettings(), mutedMerchants: [],
                                            now: date(10, 16), calendar: cal)
        let suggestion = first.first { $0.situation == .suggestMute }
        #expect(suggestion != nil)
        if let suggestion {
            m.apply([NyxDecision(observation: suggestion, delivery: .list)], now: date(10, 16))
            m.mark(suggestion.id, .dismissed, now: date(10, 17))
        }
        // Pasados > 30 días de la sugerencia y > 60 del primer descarte real: solo queda 1 descarte real, no debe repetirse.
        let later = nyxLearningObservations(memory: m, alertSettings: AlertSettings(), mutedMerchants: [],
                                            now: nov(26), calendar: cal)
        #expect(!later.contains { $0.situation == .suggestMute })
    }

    @Test func nivelDeHabla() {
        let u = ob(.shortfall, "u", .urgent)
        let n = ob(.budgetOffPace, "n", .normal)
        let q = ob(.bankStale, "q", .quiet)
        #expect(decide([u, n, q]) == [u.id: .notification, n.id: .notification, q.id: .list])
        #expect(decide([u, n, q], talk: .urgentOnly) == [u.id: .notification, n.id: .list, q.id: .list])
        #expect(decide([u, n, q], talk: .listOnly) == [u.id: .list, n.id: .list, q.id: .list])
        #expect(NyxTalkLevel.whenItMatters.displayName == "Cuando importe")
        #expect(NyxTalkLevel.urgentOnly.displayName == "Solo lo urgente")
        #expect(NyxTalkLevel.listOnly.displayName == "Nunca, solo la lista")
    }

    @Test func yaConocidaYSilenciadaSeDescartan() {
        var m = NyxMemory()
        m.record(ob(.shortfall, "a", .urgent), delivery: .list, now: nov(26, 9))
        #expect(decide([ob(.shortfall, "a", .urgent)], m).isEmpty)
        #expect(decide([ob(.unusualPayment, "x", .normal, merchant: "Mercadona")], muted: ["mercadona"]).isEmpty)
    }

    @Test func espejosNoRepitenYRespetanAvisos() {
        let instant = ob(.largePayment, "p", .normal, via: true)
        #expect(decide([instant], moment: .notice)[instant.id] == .viaAvisos)
        var off = AlertSettings()
        off.largePayment = false
        #expect(decide([ob(.largePayment, "q", .normal)], settings: off)[ob(.largePayment, "q", .normal).id] == .list)
    }

    @Test func pausaYTopeDiario() {
        var m = NyxMemory()
        m.record(ob(.budgetOffPace, "x", .normal), delivery: .notification, now: nov(26, 10))
        #expect(decide([ob(.budgetOffPace, "y", .normal)], m)[ob(.budgetOffPace, "y", .normal).id] == .list)
        #expect(decide([ob(.budgetOffPace, "y", .normal)], m, now: nov(26, 14, 1))[ob(.budgetOffPace, "y", .normal).id] == .notification)
        var full = NyxMemory()
        full.interruptions = [nov(26, 6), nov(26, 7), nov(26, 8)]
        #expect(decide([ob(.salary, "s", .normal)], full)[ob(.salary, "s", .normal).id] == .list)
        #expect(decide([ob(.shortfall, "u", .urgent)], full)[ob(.shortfall, "u", .urgent).id] == .notification)
        var yesterday = NyxMemory()
        yesterday.interruptions = [nov(26, 4, 30), nov(25, 22), nov(25, 21)]
        #expect(decide([ob(.salary, "s", .normal)], yesterday)[ob(.salary, "s", .normal).id] == .notification)
        let eligible = NyxSituation.allCases.filter { $0 != .notificationsOff && !$0.isMerchantCentric }
        let batch = (0..<5).map { ob(eligible[$0], "b\($0)", .normal) }
        #expect(decide(batch).values.filter { $0 == .notification }.count == 3)
    }

    @Test func fechasFuturasNoCuentanParaElTope() {
        var m = NyxMemory()
        m.interruptions = [nov(27, 9), nov(27, 10), nov(27, 11)]
        m.lastInterruption["salary"] = nov(27, 9)
        #expect(decide([ob(.salary, "s", .normal)], m)[ob(.salary, "s", .normal).id] == .notification)
    }

    @Test func aprendeLoQueNoLeImporta() {
        var m = NyxMemory()
        m.dismissals["budgetOffPace"] = [nov(10), nov(15), nov(20)]
        #expect(nyxIsDemoted(.budgetOffPace, memory: m, now: nov(26)))
        #expect(decide([ob(.budgetOffPace, "z", .normal)], m)[ob(.budgetOffPace, "z", .normal).id] == .list)
        m.actions["budgetOffPace"] = [nov(21)]
        #expect(!nyxIsDemoted(.budgetOffPace, memory: m, now: nov(26)))

        var mm = NyxMemory()
        mm.merchantDismissals["glovo"] = [nov(1), nov(20)]
        mm.record(ob(.unusualPayment, "g", .normal, merchant: "Glovo"), delivery: .list, now: nov(20))
        let learned = nyxLearningObservations(memory: mm, alertSettings: AlertSettings(), mutedMerchants: [], now: nov(26), calendar: cal)
        #expect(learned.contains { $0.id == "suggestMute|glovo|2026-11" && $0.facts.merchant == "Glovo" && $0.priority == .quiet })
        mm.suggestedAt["mute|glovo"] = nov(5)
        #expect(nyxLearningObservations(memory: mm, alertSettings: AlertSettings(), mutedMerchants: [], now: nov(26), calendar: cal).isEmpty)

        var ma = NyxMemory()
        ma.dismissals["salary"] = [nov(5)]
        ma.dismissals["largeIncome"] = [nov(10), nov(20)]
        #expect(nyxLearningObservations(memory: ma, alertSettings: AlertSettings(), mutedMerchants: [], now: nov(26), calendar: cal)
            .contains { $0.id == "suggestAlertOff|income|2026-11" && $0.facts.alertSwitch == .income })
    }

    @Test func unAvisoConVariasCosasNoDuplica() {
        let batch = [
            ob(.largePayment, "m", .normal, via: true),
            ob(.budgetExceeded, "month|2026-11", .normal, via: true),
            ob(.lowBalance, "rev|2026-11-26", .normal, via: true),
            ob(.shortfall, "rev|netflix|2026-11-27", .urgent),
        ]
        var m = NyxMemory()
        let first = nyxDecide(batch, memory: m, talk: .whenItMatters, moment: .notice, appActive: false,
                              mutedMerchants: [], alertSettings: AlertSettings(), now: nov(26, 12), calendar: cal)
        #expect(first.filter { $0.delivery == .viaAvisos }.count == 3)
        #expect(first.filter { $0.delivery == .notification }.map(\.observation.situation) == [.shortfall])
        m.apply(first, now: nov(26, 12))
        #expect(nyxDecide(batch, memory: m, talk: .whenItMatters, moment: .notice, appActive: false,
                          mutedMerchants: [], alertSettings: AlertSettings(), now: nov(26, 12, 1), calendar: cal).isEmpty)
    }

    @Test func preferenciasAntiguasTraenNivelPorDefecto() throws {
        let old = try JSONDecoder().decode(AssistantPreferences.self,
                                           from: Data(#"{"disabledTopics":[],"topicWeights":{},"cardFeedback":{}}"#.utf8))
        #expect(old.nyxTalkLevel == .whenItMatters && old.nyxReadAloudWithHeadphones == false)
        var p = AssistantPreferences()
        p.nyxTalkLevel = .urgentOnly
        p.nyxReadAloudWithHeadphones = true
        let decoded = try JSONDecoder().decode(AssistantPreferences.self, from: JSONEncoder().encode(p))
        #expect(decoded.nyxTalkLevel == .urgentOnly && decoded.nyxReadAloudWithHeadphones == true)
    }
}
