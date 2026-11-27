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
        obs(.shortfall, "6b", NyxFacts(merchant: "Spotify", bank: .rev, cents: 1099, balanceCents: 3000, suggestedCents: 1000, day: nov(28))),
        obs(.shortfall, "6c", NyxFacts(merchant: "Spotify", bank: .rev, otherBank: .ima, cents: 1099, balanceCents: 3000, suggestedCents: 1000, day: nov(29))),
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
        let mLater = msg(.shortfall, later, now: nov(24))
        #expect(render(mLater.open, .plain).hasPrefix("El viernes 27 te cobran"))
        #expect(mLater.closed == "El viernes te cobran Spotify en Revolut y la cuenta se queda corta.")
        #expect(mLater.neutral == "El viernes te cobran algo en Revolut y la cuenta se queda corta.")
        #expect(nyxNotificationText(mLater, hidden: true) == ("Un cobro que no cabe", mLater.closed))
        #expect(nyxDisplayText(mLater, hidden: true) == mLater.closed)

        var twoDays = f
        twoDays.day = date(11, 26)
        let mTwo = msg(.shortfall, twoDays, now: nov(24))
        #expect(render(mTwo.open, .plain).hasPrefix("El jueves 26 te cobran"))
        #expect(mTwo.closed == "Pasado mañana te cobran Spotify en Revolut y la cuenta se queda corta.")
        #expect(mTwo.neutral == "Pasado mañana te cobran algo en Revolut y la cuenta se queda corta.")
        #expect(nyxNotificationText(mTwo, hidden: true).body == mTwo.closed)

        var sevenDays = f
        sevenDays.day = date(12, 1)
        let mSeven = msg(.shortfall, sevenDays, now: nov(24))
        #expect(render(mSeven.open, .plain).hasPrefix("El martes 1 te cobran"))
        #expect(mSeven.closed == "El martes te cobran Spotify en Revolut y la cuenta se queda corta.")

        var sameMonthFar = f
        sameMonthFar.day = date(11, 15)
        let mSameMonth = msg(.shortfall, sameMonthFar, now: nov(5))
        #expect(mSameMonth.closed == "Este mes te cobran Spotify en Revolut y la cuenta se queda corta.")
        #expect(mSameMonth.neutral == "Este mes te cobran algo en Revolut y la cuenta se queda corta.")

        var nextMonth = f
        nextMonth.day = date(12, 5)
        let mNextMonth = msg(.shortfall, nextMonth, now: nov(24))
        #expect(mNextMonth.closed == "El mes que viene te cobran Spotify en Revolut y la cuenta se queda corta.")
        #expect(mNextMonth.neutral == "El mes que viene te cobran algo en Revolut y la cuenta se queda corta.")

        // Comercio con cifras a 3 días: cae al neutro (también sin dígitos), no al genérico.
        var numericMerchant = later
        numericMerchant.merchant = "Tienda 24"
        let mNum = msg(.shortfall, numericMerchant, now: nov(24))
        let nNum = nyxNotificationText(mNum, hidden: true)
        #expect(nNum.title == "Un cobro que no cabe")
        #expect(nNum.body == "El viernes te cobran algo en Revolut y la cuenta se queda corta.")
        #expect(!nNum.body.contains { $0.isNumber })
    }

    @Test func diasPasadosNoSalenComoHoy() {
        let base = NyxFacts(merchant: "Spotify", bank: .rev, otherBank: .ima, cents: 1099, balanceCents: 3000,
                            suggestedCents: 1000, day: nov(25))
        let cases: [(day: Date, openPrefix: String, closedPrefix: String)] = [
            (nov(25), "El miércoles 25 te cobraron", "Ayer te cobraron"),
            (nov(21), "El sábado 21 te cobraron", "Hace unos días te cobraron"),
            (nov(15), "El 15 nov te cobraron", "La semana pasada te cobraron"),
            (date(10, 20), "El 20 oct te cobraron", "El mes pasado te cobraron"),
        ]
        for item in cases {
            var f = base
            f.day = item.day
            let m = msg(.shortfall, f, now: nov(26, 12))
            let open = render(m.open, .plain)
            #expect(!open.hasPrefix("Hoy"), "\(item.day): \(open)")
            #expect(open.hasPrefix(item.openPrefix), "\(item.day): \(open)")
            #expect(!m.closed.hasPrefix("Hoy") && m.closed.hasPrefix(item.closedPrefix), "\(item.day): \(m.closed)")
            #expect(!m.neutral.hasPrefix("Hoy") && m.neutral.hasPrefix(item.closedPrefix), "\(item.day): \(m.neutral)")
            let notif = nyxNotificationText(m, hidden: true)
            #expect(!notif.title.contains { $0.isNumber } && !notif.body.contains { $0.isNumber })
            #expect(notif.body != "Tengo algo que contarte.")
        }
    }

    @Test func cobroPasadoSeEscribeEnPasadoYNoOfreceTraspaso() {
        let base = NyxFacts(merchant: "Spotify", bank: .rev, otherBank: .ima, cents: 1099, balanceCents: 3000,
                            suggestedCents: 1000, day: nov(25))
        func isTransfer(_ a: NyxAction) -> Bool {
            if case .prepareTransfer = a { return true }
            return false
        }
        // Mismo mes y más de 13 días atrás: no puede leerse «Este mes te cobran…» (futuro).
        var far = base
        far.day = nov(2)
        let sameMonthFarBack = msg(.shortfall, far, now: nov(26, 12))
        #expect(sameMonthFarBack.closed.hasPrefix("Este mes te cobraron"), "\(sameMonthFarBack.closed)")
        #expect(sameMonthFarBack.neutral.hasPrefix("Este mes"), "\(sameMonthFarBack.neutral)")
        for diff in [-1, -3, -9, -24] {
            var f = base
            f.day = cal.date(byAdding: .day, value: diff, to: nov(26, 12))!
            let m = msg(.shortfall, f, now: nov(26, 12))
            let open = render(m.open, .plain)
            for text in [open, m.closed, m.neutral] {
                #expect(!text.contains("te cobran "), "\(diff): \(text)")
                #expect(!text.contains("se queda"), "\(diff): \(text)")
                #expect(text.contains("te cobraron") || text.contains("tuviste"), "\(diff): \(text)")
            }
            // Con el ojo abierto no hay oferta de traspaso calculada con un saldo viejo.
            #expect(!open.contains("traspaso") && !open.contains("pásale") && !open.contains("tienes"), "\(diff): \(open)")
            #expect(!m.actions.contains(where: isTransfer), "\(diff)")
            #expect(!nyxActionTitles(m, hidden: false).contains { $0.lowercased().contains("traspaso") }, "\(diff)")
        }
        // Un cobro futuro conserva el presente y la oferta.
        var future = base
        future.day = nov(28)
        let fm = msg(.shortfall, future, now: nov(26, 12))
        #expect(render(fm.open, .plain).contains("te cobran") && render(fm.open, .plain).contains("traspaso"))
        #expect(fm.actions.contains(where: isTransfer))
    }

    @Test func cobroPasadoCerradoNoLlevaDigitos() {
        var f = NyxFacts(merchant: "Spotify", bank: .rev, otherBank: .ima, cents: 1099, balanceCents: 3000,
                         suggestedCents: 1000, day: nov(2))
        for day in [nov(25), nov(21), nov(15), nov(2), date(10, 20)] {
            f.day = day
            let m = msg(.shortfall, f, now: nov(26, 12))
            let notif = nyxNotificationText(m, hidden: true)
            #expect(!notif.body.contains { $0.isNumber } && !notif.body.contains("te cobran "), "\(day): \(notif.body)")
            #expect(notif.body != "Tengo algo que contarte.")
        }
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
        // La línea de novedades de la puesta al día tampoco lleva ningún dígito con el ojo cerrado.
        for count in [1, 2, 3, 10, 25] {
            let line = nyxSeenLine(count, hidden: true)
            #expect(line != nil && !(line ?? "").contains { $0.isNumber }, "nyxSeenLine(\(count)): \(line ?? "nil")")
        }
        #expect(nyxSeenLine(0, hidden: true) == nil)

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

    @Test func botonesConOjoCerradoNoFiltranDigitos() {
        #expect(nyxActionTitle(.muteMerchant("Tienda 24")) == "Silenciar Tienda 24")
        #expect(nyxActionTitle(.muteMerchant("Tienda 24"), hidden: false) == "Silenciar Tienda 24")
        #expect(nyxActionTitle(.muteMerchant("Tienda 24"), hidden: true) == "Silenciar este comercio")
        #expect(nyxActionTitle(.muteMerchant("Mercadona"), hidden: true) == "Silenciar Mercadona")
        let sm = msg(.suggestMute, NyxFacts(merchant: "Tienda 24"))
        #expect(nyxActionTitles(sm, hidden: false) == ["Silenciar Tienda 24"])
        #expect(nyxActionTitles(sm, hidden: true) == ["Silenciar este comercio"])
    }

    @Test func observacionDanadaSinDatosDevuelveFraseNeutra() {
        for situation in NyxSituation.allCases {
            let m = msg(situation, NyxFacts(), now: nov(26, 12))
            let open = render(m.open, .plain)
            #expect(!open.contains("Revolut"), "\(situation): \(open)")
            #expect(!m.closed.contains("Revolut"), "\(situation): \(m.closed)")
            #expect(!open.contains("0,00"), "\(situation): \(open)")
            #expect(!open.hasPrefix("ese comercio"), "\(situation): \(open)")
            #expect(!m.closed.hasPrefix("ese comercio"), "\(situation): \(m.closed)")
            #expect(![m.closedTitle, m.closed, m.neutral].joined().contains { $0.isNumber }, "\(situation)")
            #expect(!containsAdvice(open) && !containsAdvice(m.closed) && !containsAdvice(m.neutral), "\(situation)")
            #expect(open.count <= 160 && m.closed.count <= 160 && m.neutral.count <= 160, "\(situation)")
        }
        #expect(render(msg(.duplicateCharge, NyxFacts()).open, .plain) == "Un comercio te ha cobrado dos veces lo mismo en pocos minutos.")
        #expect(render(msg(.subscriptionUp, NyxFacts()).open, .plain) == "Una suscripción te cobra más que antes.")
        #expect(render(msg(.unusualPayment, NyxFacts()).open, .plain) == "Un pago más alto de lo habitual.")
        #expect(render(msg(.lowBalance, NyxFacts()).open, .plain) == "Saldo bajo en una cuenta.")
    }

    @Test func todasLasSituacionesDeVigilantesRealesSinDigitosConOjoCerrado() {
        let now = nov(24, 12)
        func pay(_ cents: Int, _ merchant: String?, _ when: Date, bank: BankID = .rev) -> Movement {
            Movement(bank: bank, amountCents: -cents, merchant: merchant, kind: .payment, source: .notification, date: when)
        }
        func inc(_ cents: Int, _ merchant: String?, _ when: Date, bank: BankID = .ima) -> Movement {
            Movement(bank: bank, amountCents: cents, merchant: merchant, kind: .income, source: .notification, date: when)
        }

        var produced: [(NyxObservation, Date)] = []

        // 1. Espejos de movimientos nuevos (pago poco habitual, grande, duplicado, suscripción sube/baja, nómina, ingreso grande).
        let unusualNew = pay(7000, "Mercadona", nov(24, 10))
        let largeNew = pay(20_000, "Zara", nov(24, 10, 5))
        let dupA = pay(1299, "Cabify", nov(24, 10, 10))
        let dupB = pay(1299, "Cabify", nov(24, 10, 15))
        let subUpNew = pay(1299, "Netflix", nov(24, 10, 20))
        let subDownNew = pay(1099, "Max", nov(24, 10, 25))
        let salaryNew = inc(180_000, "Nómina Empresa", nov(24, 10, 30))
        let largeIncNew = inc(90_000, "Devolución", nov(24, 10, 35))
        let moneyMovements = [
            pay(2000, "Mercadona", nov(2)), pay(2100, "Mercadona", nov(9)), pay(1900, "Mercadona", nov(16)), unusualNew,
            largeNew,
            dupA, dupB,
            pay(1099, "Netflix", date(9, 24)), pay(1099, "Netflix", date(10, 24)), subUpNew,
            pay(1299, "Max", date(9, 24)), pay(1299, "Max", date(10, 24)), subDownNew,
            salaryNew, largeIncNew,
        ]
        let moneyState = LedgerState(balances: [:], movements: moneyMovements, unread: [])
        produced += nyxMoneyObservations(
            state: moneyState, book: AccountBook(),
            newMovementIDs: [unusualNew.id, largeNew.id, dupB.id, subUpNew.id, subDownNew.id, salaryNew.id, largeIncNew.id],
            moment: .background, now: now, calendar: cal
        ).map { ($0, now) }

        // 2. Saldo bajo.
        let lowPay = pay(5000, "Kiosko", nov(24, 10))
        let lowState = LedgerState(
            balances: [.rev: ManualBalance(cents: 12_000, setAt: nov(24, 9), fromBank: false)],
            movements: [lowPay], unread: [])
        produced += nyxMoneyObservations(state: lowState, book: AccountBook(), newMovementIDs: [lowPay.id],
                                         moment: .background, now: now, calendar: cal).map { ($0, now) }

        // 3. Cobro que no cabe a 2 días (nov 26 desde nov 24 → «Pasado mañana» cerrado, «El jueves 26» abierto).
        let shortState = LedgerState(
            balances: [.rev: ManualBalance(cents: 3000, setAt: nov(24, 9), fromBank: true),
                       .ima: ManualBalance(cents: 100_000, setAt: nov(24, 9), fromBank: true)],
            movements: [pay(1099, "Spotify", date(9, 26)), pay(1099, "Spotify", date(10, 26))],
            unread: [])
        var shortBook = AccountBook()
        shortBook.floors[.rev] = 2500
        produced += nyxMoneyObservations(state: shortState, book: shortBook, newMovementIDs: [],
                                         moment: .open, now: now, calendar: cal).map { ($0, now) }

        // 4. Presupuesto cerca del límite y presupuesto superado.
        let budgetState = LedgerState(
            balances: [:],
            movements: [pay(12_000, "Tienda Ropa", nov(15)), pay(38_000, "Otra Tienda", nov(16))],
            unread: [],
            categoryOverrides: ["tienda ropa": .compras, "otra tienda": .ocio],
            budgets: Budgets(monthlyCents: 60_000, byCategory: [.compras: 10_000]))
        produced += nyxMoneyObservations(state: budgetState, book: AccountBook(), newMovementIDs: [],
                                         moment: .open, now: now, calendar: cal).map { ($0, now) }

        // 5. Presupuesto fuera de ritmo (día 10 del mes).
        let paceNow = nov(10, 12)
        let paceState = LedgerState(balances: [:], movements: [pay(25_000, "Tienda", nov(10, 9))], unread: [],
                                    budgets: Budgets(monthlyCents: 60_000))
        produced += nyxMoneyObservations(state: paceState, book: AccountBook(), newMovementIDs: [],
                                         moment: .open, now: paceNow, calendar: cal).map { ($0, paceNow) }

        // 6. Categoría por encima de lo habitual sin presupuesto (historial empezando el día 1 → 3 meses completos).
        let catHistory = [8, 9, 10].map { pay(10_000, "La Tasca", date($0, 1)) } + [pay(13_500, "La Tasca", nov(20))]
        let catState = LedgerState(balances: [:], movements: catHistory, unread: [],
                                   categoryOverrides: ["la tasca": .comerFuera])
        produced += nyxMoneyObservations(state: catState, book: AccountBook(), newMovementIDs: [],
                                         moment: .open, now: now, calendar: cal).map { ($0, now) }

        // 7. Vigilante de salud (todas las 7 situaciones de salud).
        var expLink = BankLinkInfo(connectedAt: date(9, 1), consentValidUntil: nov(20))
        expLink.lastSuccessAt = nov(19)
        var soonLink = BankLinkInfo(connectedAt: date(9, 1), consentValidUntil: nov(27))
        soonLink.lastSuccessAt = nov(24, 9)
        var staleLink = BankLinkInfo(connectedAt: date(9, 1), consentValidUntil: date(12, 20))
        staleLink.lastSuccessAt = nov(20)
        var healthState = LedgerState(
            balances: [.ima: ManualBalance(cents: 5000, setAt: nov(20), fromBank: false)],
            movements: [], unread: [],
            links: [.rev: expLink, .ima: soonLink, .tr: staleLink])
        healthState.guideSightings[GuideTrack.revolut.rawValue] = GuideSighting(first: date(10, 1), last: nov(10))
        var healthMem = NyxMemory()
        healthMem.firstUseAt = nov(10)
        produced += nyxHealthObservations(
            state: healthState,
            health: NyxAppHealth(notificationsAllowed: false, appExpiresAt: nov(25, 10)),
            memory: healthMem, now: now, calendar: cal
        ).map { ($0, now) }

        // 8. Vigilante de aprendizaje (suggestMute y suggestAlertOff).
        var learnMem = NyxMemory()
        learnMem.merchantDismissals["glovo"] = [nov(1), nov(20)]
        learnMem.record(NyxObservation(situation: .unusualPayment, subject: "g", priority: .normal, observedAt: nov(20),
                                       facts: NyxFacts(merchant: "Glovo")), delivery: .list, now: nov(20))
        learnMem.dismissals["salary"] = [nov(5)]
        learnMem.dismissals["largeIncome"] = [nov(10), nov(20)]
        produced += nyxLearningObservations(memory: learnMem, alertSettings: AlertSettings(), mutedMerchants: [],
                                            now: now, calendar: cal).map { ($0, now) }

        // Todas las 22 situaciones deben salir de los vigilantes reales.
        #expect(Set(produced.map { $0.0.situation }) == Set(NyxSituation.allCases))

        let banned = ["conviene", "deberias", "tranquil", "calma", "no te preocupes", "todo bien",
                      "buenas noticias", "bienvenid", "encantad", " listo", " lista"]
        for (obs, obsNow) in produced {
            let m = nyxMessage(for: obs, now: obsNow, calendar: cal)
            let notif = nyxNotificationText(m, hidden: true)
            let display = nyxDisplayText(m, hidden: true)
            let closedActions = nyxActionTitles(m, hidden: true)
            #expect(!notif.title.contains { $0.isNumber }, "\(obs.situation): \(notif.title)")
            #expect(!notif.body.contains { $0.isNumber }, "\(obs.situation): \(notif.body)")
            #expect(!display.contains { $0.isNumber }, "\(obs.situation): \(display)")
            #expect(display == notif.body, "\(obs.situation)")
            #expect(notif.body != "Tengo algo que contarte.", "\(obs.situation) cayó al genérico")
            for actionTitle in closedActions {
                #expect(!actionTitle.contains { $0.isNumber }, "\(obs.situation): \(actionTitle)")
            }
            for text in [notif.title, notif.body, render(m.open, .plain)] + closedActions {
                #expect(!containsAdvice(text), "\(obs.situation): \(text)")
                #expect(text.count <= 160, "\(obs.situation): \(text.count) chars")
                let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                for word in banned {
                    #expect(!folded.contains(word), "\(obs.situation): \(text)")
                }
            }
        }
    }
}
