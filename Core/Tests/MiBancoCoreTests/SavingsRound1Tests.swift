import Foundation
import Testing
@testable import MiBancoCore

// Cuenta remunerada, ronda de arreglos 1: filas del banco de solo día alrededor de la base, un solo total en todas partes,
// traspasos con la remunerada fuera del gasto, quitar la cuenta y el campo del interés.

private let madrid: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Madrid")!
    return c
}()

private func nov(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    madrid.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

/// Fila de Enable Banking de solo día: fecha a mediodía de Madrid, vista por primera vez en `imported`.
private func bankDay(_ cents: Int, _ day: Int, imported: Date, text: String? = nil, bookedDay: Date? = nil) -> Movement {
    Movement(bank: .rev, amountCents: cents, merchant: text ?? (cents < 0 ? "To EUR Savings" : "From EUR Savings"),
             kind: cents < 0 ? .payment : .income, source: .bank, date: nov(day), bankRef: UUID().uuidString,
             bankStatus: .booked, importedAt: imported, dayOnly: true, firstSeenStatus: .booked, bookedDay: bookedDay)
}

private func notice(_ cents: Int, _ date: Date) -> Movement {
    Movement(bank: .rev, amountCents: cents, merchant: cents < 0 ? "To EUR Savings" : "From EUR Savings",
             kind: cents < 0 ? .payment : .income, source: .notification, date: date)
}

private func savings(_ base: Date, _ movements: [Movement], refreshedAt: Date? = nil, now: Date) -> Int? {
    var l = Ledger(state: LedgerState(movements: movements))
    l.setSavings(balanceCents: 100_000, annualRateBasisPoints: nil, now: base)
    if let refreshedAt { l.noteSavingsRefresh(syncedAt: refreshedAt) }
    return l.savingsBalance(now: now).map { $0.cents - 100_000 }
}

@Suite struct SavingsRound1Tests {

    // MARK: C1 · Filas de solo día alrededor de la base

    @Test func dayOnlyRowsByMadridDay() {
        // Día anterior a la base: ya estaba dentro. Día posterior: suma.
        #expect(savings(nov(10, 9), [bankDay(-10_000, 9, imported: nov(10, 10))], now: nov(11, 20)) == 0)
        #expect(savings(nov(10, 9), [bankDay(-10_000, 11, imported: nov(11, 10))], now: nov(11, 20)) == 10_000)
    }

    @Test func morningBaselineSameDay() {
        // Vista antes de poner la base (08:00): ya estaba dentro, aunque su mediodía sea posterior a las 09:00.
        #expect(savings(nov(10, 9), [bankDay(-10_000, 10, imported: nov(10, 8))], now: nov(10, 20)) == 0)
        // Escenario A: traspaso a las 08:30, base a las 09:00 y el refresco de Revolut que sigue a guardar la trae (09:01).
        #expect(savings(nov(10, 9), [bankDay(-10_000, 10, imported: nov(10, 9, 1))], refreshedAt: nov(10, 9, 1),
                        now: nov(10, 20)) == 0)
        // Uno que llega en una consulta posterior a ese refresco es de después de la base: suma una vez.
        #expect(savings(nov(10, 9), [bankDay(-10_000, 10, imported: nov(10, 16))], refreshedAt: nov(10, 9, 1),
                        now: nov(10, 20)) == 10_000)
    }

    @Test func afternoonBaselineSameDay() {
        // Escenario B: base a las 14:00, traspaso a las 15:00; la fila (mediodía) llega a las 16:00. No se pierde.
        #expect(savings(nov(10, 14), [bankDay(-5_000, 10, imported: nov(10, 16))], now: nov(10, 20)) == 5_000)
        // Vista antes de la base (13:00): dentro de la base.
        #expect(savings(nov(10, 14), [bankDay(-5_000, 10, imported: nov(10, 13))], now: nov(10, 20)) == 0)
        // Con refresco tras guardar (14:02): lo que trae el refresco estaba dentro; lo de después suma.
        #expect(savings(nov(10, 14), [bankDay(-5_000, 10, imported: nov(10, 14, 2)), bankDay(-7_000, 10, imported: nov(10, 18))],
                        refreshedAt: nov(10, 14, 2), now: nov(10, 20)) == 7_000)
    }

    @Test func bookingDayNextDay() {
        // Escenario C: traspaso a las 23:30 del día 9 que Revolut apunta el día 10 (solo trae el día de apunte). Con la base
        // del día 10 a las 09:00 ya estaba dentro: lo trae el refresco de después de guardar, o una consulta anterior.
        let late = bankDay(-20_000, 10, imported: nov(10, 9, 1), bookedDay: nov(10))
        #expect(savings(nov(10, 9), [late], refreshedAt: nov(10, 9, 1), now: nov(11, 20)) == 0)
        let earlier = bankDay(-20_000, 10, imported: nov(10, 7), bookedDay: nov(10))
        #expect(savings(nov(10, 9), [earlier], now: nov(11, 20)) == 0)
    }

    @Test func unlinkedNoticeBeforeTheBaseline() {
        // Escenario D: aviso a las 08:30 (antes de la base de las 09:00) y su fila del banco del mismo día, sin enlazar: es
        // el mismo traspaso, de antes de la base. No cuenta ni el aviso ni la fila.
        #expect(savings(nov(10, 9), [notice(-10_000, nov(10, 8, 30)), bankDay(-10_000, 10, imported: nov(10, 11))],
                        now: nov(10, 20)) == 0)
        // El mismo par con el aviso después de la base: cuenta una vez.
        #expect(savings(nov(10, 9), [notice(-10_000, nov(10, 10)), bankDay(-10_000, 10, imported: nov(10, 11))],
                        now: nov(10, 20)) == 10_000)
    }

    @Test func refreshOnlyCountsRightAfterTheBaseline() {
        var l = Ledger(state: LedgerState())
        l.setSavings(balanceCents: 100_000, annualRateBasisPoints: nil, now: nov(10, 9))
        l.noteSavingsRefresh(syncedAt: nov(10, 8, 59))
        #expect(l.state.savings?.coveredThrough == nil)
        l.noteSavingsRefresh(syncedAt: nov(10, 11))
        #expect(l.state.savings?.coveredThrough == nil)
        l.noteSavingsRefresh(syncedAt: nov(10, 9, 3))
        #expect(l.state.savings?.coveredThrough == nov(10, 9, 3))
        // El primero vale; uno posterior no lo mueve.
        l.noteSavingsRefresh(syncedAt: nov(10, 9, 5))
        #expect(l.state.savings?.coveredThrough == nov(10, 9, 3))
        // Corregir otra vez la base lo borra.
        l.setSavings(balanceCents: 1, annualRateBasisPoints: nil, now: nov(11, 9))
        #expect(l.state.savings?.coveredThrough == nil)
    }

    // MARK: Un solo total

    @Test func oneTotalForEverything() throws {
        var l = Ledger(state: LedgerState(balances: [.rev: ManualBalance(cents: 34_020, setAt: nov(10, 8), origin: .manual)]))
        l.setSavings(balanceCents: 500_000, annualRateBasisPoints: nil, now: nov(10, 9))
        #expect(l.banksTotal() == 34_020)
        #expect(l.total(now: nov(10, 20)) == 534_020)

        // El asistente dice el mismo total y la remunerada en su línea.
        let answer = answerIntent(.balances(bank: nil), state: l.state, portfolio: nil, book: AccountBook(), now: nov(10, 20), calendar: madrid)
        let totalLine = try #require(answer.lines.first { $0.id == "bal-total" })
        #expect(totalLine.parts.contains(.amount(534_020)))
        let savingsLine = try #require(answer.lines.first { $0.id == "bal-savings" })
        #expect(savingsLine.parts.contains(.amount(500_000)))
    }

    @Test func summaryTreatsSavingsTransfersAsMovingMoney() {
        // Base el día 10; el 11 el dueño mueve 1.000,00 € de Revolut a la remunerada (el banco lo da con hora).
        let move = Movement(bank: .rev, amountCents: -100_000, merchant: "To EUR Savings", kind: .payment, source: .bank,
                            date: nov(11, 10), bankRef: "t1", bankStatus: .booked, importedAt: nov(11, 10, 5))
        var l = Ledger(state: LedgerState(balances: [.rev: ManualBalance(cents: 200_000, setAt: nov(11, 9), origin: .manual)],
                                          movements: [move]))
        l.setSavings(balanceCents: 500_000, annualRateBasisPoints: nil, now: nov(10, 9))
        let input = briefingInput(state: l.state, portfolio: nil, book: AccountBook(),
                                  record: BriefingRecord(shownAt: nov(11, 8), since: nov(11, 8)), isFirst: false,
                                  now: nov(11, 20), calendar: madrid)
        #expect(input.totalCents == l.total(now: nov(11, 20)))
        #expect(input.savingsCents == 600_000)
        // El dinero solo cambió de cuenta: el total no baja y no es un pago.
        #expect(input.totalChangeCents == 0)
        #expect(!input.payments.contains { $0.id == move.id })
    }

    // MARK: Traspasos con la remunerada = traspasos entre tus cuentas

    @Test func savingsTransfersAreOwnTransfers() {
        let out = Movement(bank: .rev, amountCents: -200_000, merchant: "To EUR Savings", kind: .payment, source: .notification,
                           date: nov(10, 10))
        let back = Movement(bank: .rev, amountCents: 50_000, merchant: "From EUR Savings", kind: .income, source: .notification,
                            date: nov(10, 11))
        var notIt = Movement(bank: .rev, amountCents: -3_000, merchant: "Ahorro viaje", kind: .payment, source: .notification,
                             date: nov(10, 12))
        notIt.ownTransfer = false
        let ids = ownTransferIDs(in: [out, back, notIt])
        #expect(ids.contains(out.id))
        #expect(ids.contains(back.id))
        #expect(!ids.contains(notIt.id))
        #expect(spendingMovements(in: [out, back, notIt]).map(\.id) == [notIt.id])
        // Ni aviso de pago grande ni nada en Avisos por moverlo.
        var state = LedgerState(movements: [out])
        state.alertSettings.largePayment = true
        state.alertSettings.largePaymentThresholdCents = 10_000
        #expect(insights(for: state, now: nov(10, 12), calendar: madrid).allSatisfy { $0.kind != .largePayment })
        // «Esto no es la remunerada» (ownTransfer == false) tampoco mueve su saldo.
        var l = Ledger(state: LedgerState(movements: [notIt]))
        l.setSavings(balanceCents: 0, annualRateBasisPoints: nil, now: nov(10, 9))
        #expect(l.savingsBalance(now: nov(10, 20))?.cents == 0)
    }

    // MARK: Quitar la cuenta

    @Test func removingTheSavingsAccount() throws {
        var l = Ledger(state: LedgerState(balances: [.rev: ManualBalance(cents: 34_020, setAt: nov(10, 8), origin: .manual)]))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(l.state)
        l.setSavings(balanceCents: 500_000, annualRateBasisPoints: 200, now: nov(10, 9))
        l.removeSavings()
        #expect(l.state.savings == nil)
        #expect(l.savingsBalance(now: nov(10, 20)) == nil)
        #expect(l.total(now: nov(10, 20)) == 34_020)
        #expect(try encoder.encode(l.state) == before)
    }

    // MARK: Campo del interés

    @Test func rateInputVariantsAndSpokenMask() {
        #expect(parseAnnualRateInput("2,00") == 200)
        #expect(parseAnnualRateInput("2.00") == 200)
        #expect(parseAnnualRateInput("2 %") == 200)
        #expect(parseAnnualRateInput("2 €") == nil)
        #expect(parseAnnualRateInput("2,00€") == nil)
        #expect(parseAnnualRateInput("2,125") == nil)
        var edit = MaskedFieldEditing()
        #expect(edit.spoken(stored: "2,00", hidden: true, editing: false, hiddenText: "interés oculto") == "interés oculto")
        #expect(edit.spoken(stored: "2,00", hidden: true, editing: false) == "importe oculto")
        edit.begin(stored: "2,00", hidden: true)
        #expect(edit.spoken(stored: "2,00", hidden: true, editing: true, hiddenText: "interés oculto") == "interés oculto")
    }
}
