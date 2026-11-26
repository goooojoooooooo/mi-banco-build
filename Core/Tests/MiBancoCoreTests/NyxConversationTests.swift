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

private func pay(_ cents: Int, _ merchant: String?, _ when: Date, bank: BankID = .rev) -> Movement {
    Movement(bank: bank, amountCents: -cents, merchant: merchant, kind: .payment, source: .notification, date: when)
}

private func ledger(_ movements: [Movement]) -> LedgerState {
    LedgerState(balances: [:], movements: movements, unread: [])
}

private let s = ledger([pay(1500, "Mercadona", nov(3)), pay(900, "Lidl", nov(4))])

private func follow(_ q: String, _ prev: AssistantIntent) -> AssistantIntent? {
    nyxFollowUp(q, after: prev, state: s, portfolio: nil, now: nov(26), calendar: cal)
}

@Suite struct NyxConversationTests {
    @Test func preguntasSeguidasCambianSoloLoQueNombran() {
        let spend = AssistantIntent.spending(month: .current, category: nil, merchant: "Mercadona", bank: nil)
        #expect(follow("¿y el mes pasado?", spend) == .spending(month: .previous, category: nil, merchant: "Mercadona", bank: nil))
        #expect(follow("¿y en Revolut?", .spending(month: .current, category: nil, merchant: nil, bank: nil))
                == .spending(month: .current, category: nil, merchant: nil, bank: .rev))
        #expect(follow("¿y en Lidl?", spend) == .spending(month: .current, category: nil, merchant: "Lidl", bank: nil))
        #expect(follow("¿y en comer fuera?", spend) == .spending(month: .current, category: .comerFuera, merchant: nil, bank: nil))
        #expect(follow("¿y en imagin?", .balances(bank: .rev)) == .balances(bank: .ima))
        #expect(follow("¿y en total?", .balances(bank: .rev)) == .balances(bank: nil))
        #expect(follow("¿y en octubre?", .income(month: .current)) == .income(month: .specific(year: 2026, month: 10)))
        #expect(follow("¿y en diciembre?", .income(month: .current)) == .income(month: .specific(year: 2025, month: 12)))
    }

    @Test func unaPreguntaNuevaNoEsSeguida() {
        var conv = NyxConversation()
        conv.remember(.spending(month: .current, category: nil, merchant: "Mercadona", bank: nil))
        #expect(nyxRouteQuestion("¿Cuánto tengo?", conversation: conv, state: s, portfolio: nil, now: nov(26), calendar: cal)
                == .assistant(.balances(bank: nil)))
        #expect(nyxRouteQuestion("¿y el mes pasado?", conversation: NyxConversation(), state: s, portfolio: nil, now: nov(26), calendar: cal)
                == .assistant(routeAssistantQuestion("¿y el mes pasado?", state: s, portfolio: nil, now: nov(26), calendar: cal)))
    }

    @Test func elConsejoSeNiegaAunqueSeaSeguido() {
        var conv = NyxConversation()
        conv.remember(.investments(positionQuery: nil, moversOnly: false))
        let r = nyxAnswer("¿y vendo?", conversation: &conv, modelIntent: nil, memory: NyxMemory(), health: [],
                          state: s, portfolio: nil, book: AccountBook(), now: nov(26), calendar: cal)
        #expect(r.answer.isAdviceRefusal && render(r.answer.lines[0].parts, .plain) == investmentAdviceRefusal)
    }

    @Test func preguntasPropiasDeNyx() {
        var conv = NyxConversation()
        let none = nyxAnswer("¿Qué has visto?", conversation: &conv, modelIntent: nil, memory: NyxMemory(), health: [],
                             state: s, portfolio: nil, book: AccountBook(), now: nov(26), calendar: cal)
        #expect(none.question == .seen && none.answer.lines.map { render($0.parts, .plain) } == ["No he visto nada nuevo desde la última vez."])

        var mem = NyxMemory()
        mem.lastLookAt = nov(25, 10)
        mem.record(NyxObservation(situation: .lowBalance, subject: "rev|2026-11-26", priority: .normal, observedAt: nov(26, 9),
                                  facts: NyxFacts(bank: .rev, balanceCents: 4500)),
                   delivery: .list, now: nov(26, 9))
        let some = nyxAnswer("¿Qué me he perdido?", conversation: &conv, modelIntent: nil, memory: mem, health: [],
                             state: s, portfolio: nil, book: AccountBook(), now: nov(26, 12), calendar: cal)
        #expect(some.question == .seen && some.answer.intent == .unknown)
        #expect(some.answer.lines.count == 2)
        #expect(render(some.answer.lines[0].parts, .plain) == "Esto es lo que he visto desde ayer:")
        #expect(some.answer.lines[1].id == "seen-lowBalance|rev|2026-11-26")

        let ok = nyxAnswer("¿Va todo bien con la app?", conversation: &conv, modelIntent: nil, memory: NyxMemory(), health: [],
                           state: s, portfolio: nil, book: AccountBook(), now: nov(26), calendar: cal)
        #expect(ok.question == .appStatus && render(ok.answer.lines[0].parts, .plain) == "No veo ningún problema con tus bancos ni con los avisos.")

        let h = [NyxObservation(situation: .bankExpired, subject: "rev|2026-11-25", priority: .urgent, observedAt: nov(26),
                                facts: NyxFacts(bank: .rev))]
        let bad = nyxAnswer("¿funciona todo?", conversation: &conv, modelIntent: nil, memory: NyxMemory(), health: h,
                            state: s, portfolio: nil, book: AccountBook(), now: nov(26), calendar: cal)
        #expect(bad.question == .appStatus && bad.answer.intent == .unknown)
        #expect(render(bad.answer.lines[0].parts, .plain) == "La conexión con Revolut ha caducado. Renuévala para volver a ver su saldo al día.")
    }

    @Test func laConversacionRecuerdaYSeBorra() {
        var conv = NyxConversation()
        _ = nyxAnswer("¿Cuánto llevo en Mercadona?", conversation: &conv, modelIntent: nil, memory: NyxMemory(), health: [],
                      state: s, portfolio: nil, book: AccountBook(), now: nov(26), calendar: cal)
        #expect(conv.lastIntent != nil)
        let next = nyxAnswer("¿y el mes pasado?", conversation: &conv, modelIntent: nil, memory: NyxMemory(), health: [],
                             state: s, portfolio: nil, book: AccountBook(), now: nov(26), calendar: cal)
        #expect(next.question == .assistant(.spending(month: .previous, category: nil, merchant: "Mercadona", bank: nil)))
        conv.reset()
        #expect(conv.lastIntent == nil)
    }
}
