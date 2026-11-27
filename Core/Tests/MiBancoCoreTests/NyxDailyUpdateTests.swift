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
                merchant: String? = nil, bank: BankID? = nil, cents: Int? = nil,
                at: Date = nov(26, 9)) -> NyxObservation {
    NyxObservation(situation: situation, subject: subject, priority: priority, observedAt: at,
                   facts: NyxFacts(merchant: merchant, bank: bank, cents: cents))
}

@Suite struct NyxDailyUpdateTests {
    @Test func diaTranquiloEnsenaCadaBancoYLosCobros() {
        let input = BriefingInput(
            now: nov(26, 9),
            since: nov(25, 9),
            isFirst: false,
            banks: [
                BankLine(bank: .rev, cents: 34_020, estimated: false, changeCents: 0),
                BankLine(bank: .ima, cents: 128_455, estimated: false, changeCents: 0),
            ],
            totalCents: 162_475,
            upcoming: [UpcomingCharge(name: "Netflix", bank: .rev, cents: 1399, date: nov(29))])
        let b = makeNyxBriefing(input, calendar: cal)
        let ids = b.sections.flatMap(\.lines).map(\.id)
        #expect(ids.contains("money-rev") && ids.contains("money-ima") && ids.contains("upcoming-0"))
        #expect(!makeBriefing(input, calendar: cal).sections.flatMap(\.lines).map(\.id).contains("money-rev"))
    }

    @Test func laCosaDelDiaEsLaMasImportanteYNoRepiteOjoConEsto() {
        let input = BriefingInput(now: nov(26, 9), since: nov(25, 9), isFirst: false,
                                  attention: [.consentExpiring(.rev, nov(29))])
        let briefing = makeNyxBriefing(input, calendar: cal)
        var mem = NyxMemory()
        mem.record(ob(.budgetOffPace, "b", .normal, at: nov(25)), delivery: .list, now: nov(25))
        mem.record(ob(.subscriptionDown, "d", .quiet, at: nov(24)), delivery: .list, now: nov(24))
        mem.record(ob(.salary, "old", .normal, at: nov(10)), delivery: .list, now: nov(10))
        mem.record(ob(.duplicateCharge, "x", .urgent, at: nov(25)), delivery: .list, now: nov(25))
        mem.mark(ob(.duplicateCharge, "x", .urgent).id, .dismissed, now: nov(25))
        let current = [
            ob(.shortfall, "s", .urgent, at: nov(26, 9)),
            ob(.bankExpiring, "rev|2026-11-29|tarde", .normal, bank: .rev, at: nov(26, 9)),
        ]
        let c = nyxFocusCandidates(current: current, memory: mem, briefing: briefing, input: input, now: nov(26, 9))
        #expect(c.map(\.situation) == [.shortfall, .budgetOffPace, .subscriptionDown])
    }

    @Test func candidatasExcluyenDiasPasadosYPrefierenObservacionActual() {
        let now = nov(26, 9)
        let input = BriefingInput(now: now, since: nov(25, 9), isFirst: false)
        let briefing = makeNyxBriefing(input, calendar: cal)

        let pastShortfall = NyxObservation(
            situation: .shortfall, subject: "rev|spotify|2026-11-24", priority: .urgent, observedAt: nov(23, 9),
            facts: NyxFacts(merchant: "Spotify", bank: .rev, cents: 1099, balanceCents: 3000, suggestedCents: 1000,
                            day: cal.startOfDay(for: nov(24))))
        let pastBankExpiring = NyxObservation(
            situation: .bankExpiring, subject: "ima|2026-11-25|tarde", priority: .normal, observedAt: nov(24, 9),
            facts: NyxFacts(bank: .ima, day: nov(25, 18), days: 1))
        let pastAppExpiring = NyxObservation(
            situation: .appExpiring, subject: "2026-11-25|tarde", priority: .urgent, observedAt: nov(24, 20),
            facts: NyxFacts(day: nov(25, 20)))
        let staleLowBalance = NyxObservation(
            situation: .lowBalance, subject: "rev|2026-11-24", priority: .normal, observedAt: nov(24, 12),
            facts: NyxFacts(bank: .rev, balanceCents: 4500))
        let oldBudgetNear = NyxObservation(
            situation: .budgetNear, subject: "month|2026-11", priority: .normal, observedAt: nov(24, 12),
            facts: NyxFacts(remainingCents: 8000, percent: 81, budgetScope: "del mes"))
        let staleBank = NyxObservation(
            situation: .bankStale, subject: "tr|2026-11-22", priority: .quiet, observedAt: nov(25, 12),
            facts: NyxFacts(bank: .tr, day: nov(22)))

        var mem = NyxMemory()
        for item in [pastShortfall, pastBankExpiring, pastAppExpiring, staleLowBalance, oldBudgetNear, staleBank] {
            mem.record(item, delivery: .list, now: item.observedAt)
        }

        let freshLowBalance = NyxObservation(
            situation: .lowBalance, subject: "rev|2026-11-26", priority: .normal, observedAt: now,
            facts: NyxFacts(bank: .rev, balanceCents: 1500))
        let freshBudgetNear = NyxObservation(
            situation: .budgetNear, subject: "month|2026-11", priority: .normal, observedAt: now,
            facts: NyxFacts(remainingCents: 2000, percent: 95, budgetScope: "del mes"))

        let candidates = nyxFocusCandidates(
            current: [freshLowBalance, freshBudgetNear], memory: mem, briefing: briefing, input: input,
            now: now, calendar: cal)

        #expect(!candidates.contains { $0.id == pastShortfall.id })
        #expect(!candidates.contains { $0.id == pastBankExpiring.id })
        #expect(!candidates.contains { $0.id == pastAppExpiring.id })
        #expect(!candidates.contains { $0.id == staleLowBalance.id })
        #expect(candidates.first { $0.situation == .lowBalance }?.facts.balanceCents == 1500)
        #expect(candidates.first { $0.situation == .budgetNear }?.facts.remainingCents == 2000)
        // Las observaciones con fecha histórica de referencia (como `bankStale`) NO se excluyen.
        #expect(candidates.contains { $0.id == staleBank.id })

        // Un `shortfall` que cae HOY sí sigue siendo candidato.
        let todayShortfall = NyxObservation(
            situation: .shortfall, subject: "rev|spotify|2026-11-26", priority: .urgent, observedAt: now,
            facts: NyxFacts(merchant: "Spotify", bank: .rev, cents: 1099, balanceCents: 3000, suggestedCents: 1000,
                            day: cal.startOfDay(for: now)))
        let withToday = nyxFocusCandidates(
            current: [todayShortfall], memory: NyxMemory(), briefing: briefing, input: input, now: now, calendar: cal)
        #expect(withToday.map(\.id) == [todayShortfall.id])
    }

    @Test func elModeloSoloEligeUnNumero() {
        let c = [ob(.shortfall, "s", .urgent, merchant: "Netflix"), ob(.budgetOffPace, "b", .normal)]
        let p = nyxFocusPrompt(c)
        #expect(p.contains("1.") && p.contains("2.") && !p.contains("Netflix") && !p.contains("€"))
        #expect(p.filter(\.isNumber) == "12")
        #expect(nyxFocusChoice(from: " 2. ", count: 2) == 2)
        #expect(nyxFocusChoice(from: "3", count: 2) == nil)
        #expect(nyxFocusChoice(from: "el dos", count: 2) == nil)
        for s in NyxSituation.allCases {
            #expect(!containsNumber(s.promptLabel) && !containsAdvice(s.promptLabel), "\(s): \(s.promptLabel)")
        }
    }

    @Test func puestaAlDiaConYSinCosaDelDia() {
        let input = BriefingInput(now: nov(26, 9), since: nov(25, 9), isFirst: true, totalCents: 1000)
        let u = nyxDailyUpdate(input: input, candidates: [ob(.shortfall, "s", .urgent, merchant: "Spotify")],
                               focusChoice: nil, openingChoice: nil, seenSinceLastLook: 3, privateMode: false, calendar: cal)
        #expect(u.briefing.situation == .firstEver && openingCandidates(for: .firstEver).contains(u.opening))
        #expect(u.focus?.situation == .shortfall && !u.showsTip && u.seenSinceLastLook == 3)
        #expect(nyxDailyUpdate(input: input, candidates: [], focusChoice: nil, openingChoice: nil, seenSinceLastLook: 0,
                               privateMode: false, calendar: cal).showsTip)
        #expect(nyxSeenLine(0) == nil)
        #expect(nyxSeenLine(1) == "He visto una cosa desde la última vez.")
        #expect(nyxSeenLine(3) == "He visto 3 cosas desde la última vez.")
        #expect(nyxFocusHeader == "Para tener en cuenta")
        let two = [ob(.shortfall, "s", .urgent), ob(.budgetOffPace, "b", .normal)]
        #expect(nyxDailyUpdate(input: input, candidates: two, focusChoice: 2, openingChoice: nil, seenSinceLastLook: 0,
                               privateMode: false, calendar: cal).focus?.situation == .budgetOffPace)
    }

    @Test func primeraFraseSePresentaComoNyx() {
        #expect(openingCandidates(for: .firstEver).contains("Hola, soy Nyx. Cada día te contaré cómo van tus cuentas."))
        #expect(!openingCandidates(for: .firstEver).joined().contains("Onyx"))
    }

    @Test func vozConElOjoCerradoSinCifras() {
        let input = BriefingInput(now: nov(26, 9), since: nov(25, 9), isFirst: false, totalCents: 162_475,
                                  payments: [MovementDigest(id: UUID(), bank: .rev, name: "Zara", cents: 4995, date: nov(25, 18))])
        let short = NyxObservation(
            situation: .shortfall,
            subject: "rev|spotify|2026-11-27",
            priority: .urgent,
            observedAt: nov(26, 9),
            facts: NyxFacts(merchant: "Spotify", bank: .rev, otherBank: .ima, cents: 1099, balanceCents: 3000,
                            suggestedCents: 1000, day: nov(27)))
        let u = nyxDailyUpdate(input: input, candidates: [short], focusChoice: nil, openingChoice: 1,
                               seenSinceLastLook: 0, privateMode: true, calendar: cal)
        let spoken = nyxSpokenUpdate(u, input: input, privateMode: true, calendar: cal)
        #expect(spoken.text.contains(u.opening) && spoken.text.contains("Mañana te cobran Spotify en Revolut y la cuenta se queda corta."))
        #expect(!spoken.text.contains("€") && !spoken.text.contains("49,95") && !spoken.text.contains("10,99")
                && !spoken.text.contains("1.624") && spoken.lines.isEmpty)

        let openWithFocus = nyxSpokenUpdate(
            nyxDailyUpdate(input: input, candidates: [short], focusChoice: nil, openingChoice: 1,
                           seenSinceLastLook: 0, privateMode: false, calendar: cal),
            input: input, privateMode: false, calendar: cal)
        #expect(openWithFocus.lines.contains { $0.id == "headline" })
        #expect(openWithFocus.lines.contains { $0.id == "nyx-focus" })
        #expect(openWithFocus.text.contains(u.opening))

        let open = nyxSpokenUpdate(
            nyxDailyUpdate(input: input, candidates: [], focusChoice: nil, openingChoice: 1,
                           seenSinceLastLook: 0, privateMode: false, calendar: cal),
            input: input, privateMode: false, calendar: cal)
        #expect(open.lines.contains { $0.id == "headline" })
    }
}
