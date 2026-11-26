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

private func ledger(_ movements: [Movement], muted: Set<String> = []) -> LedgerState {
    LedgerState(balances: [:], movements: movements, unread: [], mutedMerchants: muted)
}

private func msg(_ s: NyxSituation, _ f: NyxFacts, now: Date = nov(26, 12)) -> NyxMessage {
    nyxMessage(for: NyxObservation(situation: s, subject: "t", priority: .normal, observedAt: now, facts: f),
               now: now, calendar: cal)
}

private func everySituationFixture() -> [NyxObservation] {
    let id = UUID()
    let now = nov(26, 12)
    func obs(_ s: NyxSituation, _ subject: String = "t", _ f: NyxFacts) -> NyxObservation {
        NyxObservation(situation: s, subject: subject, priority: .normal, observedAt: now, facts: f)
    }
    return [
        obs(.unusualPayment, "1", NyxFacts(merchant: "Glovo", bank: .rev, movementID: id, cents: 7000, usualCents: 2000)),
        obs(.largePayment, "2a", NyxFacts(merchant: "Zara", bank: .rev, movementID: id, cents: 20_000)),
        obs(.largePayment, "2b", NyxFacts(bank: .rev, movementID: id, cents: 20_000)),
        obs(.duplicateCharge, "3", NyxFacts(merchant: "Glovo", bank: .rev, movementID: id, cents: 1299)),
        obs(.subscriptionUp, "4", NyxFacts(merchant: "Spotify", bank: .rev, movementID: id, cents: 1199, differenceCents: 100)),
        obs(.subscriptionDown, "5", NyxFacts(merchant: "Spotify", bank: .rev, movementID: id, cents: 999, differenceCents: 100)),
        obs(.shortfall, "6a", NyxFacts(merchant: "Spotify", bank: .rev, otherBank: .ima, cents: 1099, balanceCents: 3000, suggestedCents: 1000, day: nov(27))),
        obs(.shortfall, "6b", NyxFacts(merchant: "Spotify", bank: .rev, cents: 1099, balanceCents: 3000, suggestedCents: 1000, day: nov(27))),
        obs(.budgetNear, "7", NyxFacts(remainingCents: 5000, percent: 84, budgetScope: "del mes")),
        obs(.budgetExceeded, "8", NyxFacts(spentCents: 65_000, limitCents: 60_000, budgetScope: "del mes")),
        obs(.budgetOffPace, "9", NyxFacts(spentCents: 25_000, limitCents: 60_000, budgetScope: "de Supermercado")),
        obs(.categoryAboveNormal, "10", NyxFacts(usualCents: 10_050, spentCents: 13_500, category: .comerFuera)),
        obs(.salary, "11", NyxFacts(merchant: "Empresa", bank: .ima, movementID: id, cents: 180_000)),
        obs(.largeIncome, "12a", NyxFacts(merchant: "Glovo", bank: .ima, movementID: id, cents: 90_000)),
        obs(.largeIncome, "12b", NyxFacts(bank: .ima, movementID: id, cents: 90_000)),
        obs(.lowBalance, "13", NyxFacts(bank: .rev, balanceCents: 4500)),
        obs(.bankExpired, "14", NyxFacts(bank: .rev, day: nov(25))),
        obs(.bankExpiring, "15", NyxFacts(bank: .rev, day: nov(29), days: 3)),
        obs(.bankStale, "16", NyxFacts(bank: .rev, day: nov(24))),
        obs(.alertsSilent, "17a", NyxFacts(bank: .rev, day: nov(10), days: 16, track: GuideTrack.revolut.rawValue)),
        obs(.alertsSilent, "17b", NyxFacts(bank: .ima, day: nov(10), days: 16, track: GuideTrack.walletImagin.rawValue)),
        obs(.alertsNeverArrived, "18", NyxFacts(bank: .ima, track: GuideTrack.walletImagin.rawValue)),
        obs(.notificationsOff, "19", NyxFacts(day: nov(23))),
        obs(.appExpiring, "20", NyxFacts(day: nov(27))),
        obs(.suggestMute, "21", NyxFacts(merchant: "Glovo")),
        obs(.suggestAlertOff, "22", NyxFacts(alertSwitch: .income)),
    ]
}

@Suite struct NyxCatalogueTests {
    @Test func pagoPocoHabitual() {
        let id = UUID()
        let m = msg(.unusualPayment, NyxFacts(merchant: "Mercadona", bank: .rev, movementID: id, cents: 7000, usualCents: 2000))
        #expect(m.title == "Pago poco habitual")
        #expect(render(m.open, .plain) == "Mercadona: \(formatEUR(7000)). Ahí sueles gastar unos \(formatEUR(2000)).")
        #expect(m.closed == "Un pago en Mercadona más alto de lo habitual.")
        #expect(m.actions == [.markNotMine(id), .muteMerchant("Mercadona")] && m.actionTitles == ["No es mío", "Silenciar Mercadona"])
    }

    @Test func cobroQueNoCabe() {
        let f = NyxFacts(merchant: "Spotify", bank: .rev, otherBank: .ima, cents: 1099, balanceCents: 3000, suggestedCents: 1000, day: nov(27))
        let m = msg(.shortfall, f)
        #expect(render(m.open, .plain) == "Mañana te cobran Spotify (\(formatEUR(1099))) en Revolut y tienes \(formatEUR(3000)). Puedo dejarte preparado un traspaso de \(formatEUR(1000)) desde imagin.")
        #expect(m.closed == "Mañana te cobran Spotify en Revolut y la cuenta se queda corta.")
        #expect(m.actions == [.prepareTransfer(from: .ima, to: .rev, cents: 1000)])
        var alone = f
        alone.otherBank = nil
        #expect(render(msg(.shortfall, alone).open, .plain).hasSuffix("Para cubrirlo, pásale \(formatEUR(1000)) antes."))
        var later = f
        later.day = date(11, 27)
        #expect(msg(.shortfall, later, now: nov(24)).closed.hasPrefix("El viernes 27 te cobran"))
    }

    @Test func presupuestosYCategorias() {
        #expect(render(msg(.budgetNear, NyxFacts(remainingCents: 5000, percent: 84, budgetScope: "del mes")).open, .plain)
                == "Llevas el 84\u{00A0}% de tu presupuesto del mes: te quedan \(formatEUR(5000)).")
        #expect(msg(.subscriptionUp, NyxFacts(merchant: "Spotify", bank: .rev, cents: 1199, differenceCents: 100)).closed
                == "Spotify te cobra más que antes.")
        #expect(msg(.bankExpired, NyxFacts(bank: .rev)).title == "Revolut necesita renovarse")
        #expect(msg(.budgetOffPace, NyxFacts(spentCents: 25_000, limitCents: 60_000, budgetScope: "de Supermercado")).closed
                == "A este ritmo, el presupuesto de Supermercado se acaba antes de fin de mes.")
        let c = msg(.categoryAboveNormal, NyxFacts(usualCents: 10_050, spentCents: 13_500, category: .comerFuera))
        #expect(render(c.open, .plain) == "Este mes llevas \(formatEUR(13_500)) en Comer fuera; tu media es de unos \(formatEUR(10_050)) al mes.")
        #expect(c.actions == [.setBudget(category: .comerFuera, suggestedCents: 11_000)] && c.actionTitles == ["Poner un presupuesto"])
    }

    @Test func saludDeLaApp() {
        #expect(render(msg(.bankExpiring, NyxFacts(bank: .rev, day: nov(29))).open, .plain)
                == "La conexión con Revolut caduca el 29 nov. Si la renuevas antes, su saldo sigue al día.")
        #expect(msg(.bankExpiring, NyxFacts(bank: .rev, day: nov(29))).closed
                == "La conexión con Revolut caduca pronto. Si la renuevas antes, su saldo sigue al día.")
        #expect(msg(.appExpiring, NyxFacts(day: nov(27))).title == "Onyx caduca mañana")
        #expect(msg(.appExpiring, NyxFacts(day: nov(27))).actions == [.openSideStore])
        #expect(render(msg(.alertsSilent, NyxFacts(bank: .rev, days: 16, track: "revolut")).open, .plain)
                == "Hace 16 días que no me llega ningún aviso de Revolut. Si has pagado con Revolut desde entonces, repasa la guía.")
        #expect(msg(.notificationsOff, NyxFacts()).actions == [.openNotificationSettings])
    }

    @Test func comercioConCifrasConElOjoCerradoSaleNeutro() {
        let m = msg(.largePayment, NyxFacts(merchant: "Tienda 24", bank: .rev, movementID: UUID(), cents: 20_000))
        let n = nyxNotificationText(m, hidden: true)
        #expect(n.body == "Pago grande con Revolut." && !n.title.contains { $0.isNumber } && !n.body.contains { $0.isNumber })
        #expect(nyxDisplayText(m, hidden: true) == n.body)
        #expect(nyxNotificationText(m, hidden: false).body == "Pago de \(formatEUR(20_000)) en Tienda 24, con Revolut.")
    }

    @Test func catalogoCompletoSinConsejosNiCifrasCerradas() {
        let banned = ["conviene", "deberias", "tranquil", "calma", "no te preocupes", "todo bien",
                      "buenas noticias", "bienvenid", "encantad", " listo", " lista"]
        for f in everySituationFixture() {
            let m = nyxMessage(for: f, now: nov(26, 12), calendar: cal)
            let texts = [m.title, m.closedTitle, render(m.open, .plain), m.closed, m.neutral] + m.actionTitles
            for t in texts {
                #expect(!containsAdvice(t), "\(f.situation): \(t)")
                #expect(t.count <= 160, "\(f.situation): \(t.count) chars")
                let folded = t.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                for word in banned {
                    #expect(!folded.contains(word), "\(f.situation): \(t)")
                }
            }
            #expect(![m.closedTitle, m.closed, m.neutral].joined().contains { $0.isNumber }, "\(f.situation)")
            #expect(!m.actions.isEmpty, "\(f.situation) has no button")
            #expect(m.actions.count == m.actionTitles.count, "\(f.situation) actions/titles mismatch")
        }
        #expect(Set(everySituationFixture().map(\.situation)) == Set(NyxSituation.allCases))
    }

    @Test func accionesDeUnMovimientoQueYaNoExisteNoSeOfrecen() {
        let id = UUID()
        let m = msg(.unusualPayment, NyxFacts(merchant: "Mercadona", movementID: id, cents: 7000, usualCents: 2000))
        #expect(nyxAvailableActions(m, state: ledger([])) == [.muteMerchant("Mercadona")])
        #expect(nyxAvailableActions(m, state: ledger([], muted: ["mercadona"])).isEmpty)
    }
}
