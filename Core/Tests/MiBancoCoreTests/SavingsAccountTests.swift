import Foundation
import Testing
@testable import MiBancoCore

// Cuenta remunerada de Revolut (Plan 12): saldo de partida puesto por el dueño, traspasos de ida y vuelta con la cuenta
// de Revolut e intereses estimados día a día. Todo puro: mismas entradas, misma cifra.

private let madrid: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Madrid")!
    return c
}()

/// Un instante de noviembre de 2026 en Madrid.
private func nov(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    madrid.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

private func rev(_ cents: Int, _ merchant: String?, _ date: Date, source: Movement.Source = .bank,
                 bankMerchant: String? = nil, bankRef: String? = nil, status: BankStatus? = nil,
                 importedAt: Date? = nil, firstSeen: BankStatus? = nil) -> Movement {
    Movement(bank: .rev, amountCents: cents, merchant: merchant, kind: cents < 0 ? .payment : .income, source: source,
             date: date, bankRef: bankRef ?? (source == .bank ? UUID().uuidString : nil), bankStatus: status ?? (source == .bank ? .booked : nil),
             importedAt: importedAt ?? (source == .bank ? date : nil), bankMerchant: bankMerchant, firstSeenStatus: firstSeen)
}

private func ledger(baseline: Int, at: Date, rate: Int? = nil, movements: [Movement] = []) -> Ledger {
    var l = Ledger(state: LedgerState(movements: movements))
    l.setSavings(balanceCents: baseline, annualRateBasisPoints: rate, now: at)
    return l
}

@Suite struct SavingsAccountTests {

    // MARK: Qué es un traspaso con la cuenta remunerada

    @Test func recognisesRevolutSavingsTransfers() {
        #expect(isSavingsTransfer(rev(-10_000, "To EUR Savings", nov(10))))
        #expect(isSavingsTransfer(rev(3_000, "From EUR Savings", nov(10))))
        // El nombre del banco cuenta aunque el capturado traiga otro texto.
        #expect(isSavingsTransfer(rev(-10_000, "Traspaso", nov(10), bankMerchant: "To EUR Savings")))
        #expect(isSavingsTransfer(rev(-10_000, "A cuenta remunerada", nov(10))))
        // Ni compras, ni envíos a personas, ni bolsillos sin interés, ni otros bancos.
        #expect(!isSavingsTransfer(rev(-1_250, "Mercadona", nov(10))))
        #expect(!isSavingsTransfer(rev(-2_000, "To Ana", nov(10))))
        #expect(!isSavingsTransfer(rev(-2_000, "To pocket Viaje", nov(10))))
        var imagin = rev(-10_000, "Traspaso a ahorro", nov(10))
        imagin.bank = .ima
        #expect(!isSavingsTransfer(imagin))
    }

    // MARK: Saldo de partida y traspasos

    @Test func baselineAloneIsTheBalance() throws {
        let l = ledger(baseline: 500_000, at: nov(10, 9))
        let s = try #require(l.savingsBalance(now: nov(10, 20)))
        #expect(s.cents == 500_000)
        #expect(s.transfersCents == 0)
        #expect(s.interestCents == 0)
        #expect(s.baselineAt == nov(10, 9))
        #expect(Ledger(state: LedgerState()).savingsBalance(now: nov(10)) == nil)
    }

    @Test func transfersInAddAndTransfersOutSubtract() throws {
        let l = ledger(baseline: 500_000, at: nov(10, 9), movements: [
            rev(-10_000, "To EUR Savings", nov(10, 11)),
            rev(3_000, "From EUR Savings", nov(10, 15)),
            rev(-1_250, "Mercadona", nov(10, 16)),
        ])
        let s = try #require(l.savingsBalance(now: nov(10, 20)))
        #expect(s.transfersCents == 7_000)
        #expect(s.cents == 507_000)
    }

    @Test func movementsBeforeTheBaselineDoNotCount() throws {
        let l = ledger(baseline: 500_000, at: nov(10, 9), movements: [
            rev(-10_000, "To EUR Savings", nov(9, 11)),
            rev(-20_000, "To EUR Savings", nov(10, 8, 59)),
            rev(-5_000, "To EUR Savings", nov(10, 9, 1)),
        ])
        #expect(try #require(l.savingsBalance(now: nov(10, 20))).cents == 505_000)
    }

    @Test func notMineAndDeletedMovementsStopCounting() throws {
        let keep = rev(-5_000, "To EUR Savings", nov(10, 10))
        let flagged = rev(-7_000, "To EUR Savings", nov(10, 11))
        let deleted = rev(-9_000, "To EUR Savings", nov(10, 12))
        var l = ledger(baseline: 100_000, at: nov(10, 9), movements: [keep, flagged, deleted])
        #expect(try #require(l.savingsBalance(now: nov(10, 20))).cents == 121_000)
        l.setFlaggedNotMine(true, for: flagged.id)
        l.deleteMovement(id: deleted.id)
        #expect(try #require(l.savingsBalance(now: nov(10, 20))).cents == 105_000)
    }

    // MARK: Una sola vez aunque llegue por varias fuentes

    @Test func linkedCaptureCountsOnce() throws {
        // Aviso enlazado con su registro del banco: es UN movimiento en el libro.
        var merged = rev(-10_000, "To EUR Savings", nov(10, 11), source: .notification)
        merged.bankRef = "b1"
        merged.bankStatus = .booked
        merged.linkedAt = nov(10, 12)
        let l = ledger(baseline: 100_000, at: nov(10, 9), movements: [merged])
        #expect(try #require(l.savingsBalance(now: nov(10, 20))).cents == 110_000)
    }

    @Test func unlinkedCaptureWithItsBankRowCountsOnce() throws {
        // El aviso y la fila del banco (o del extracto) del mismo traspaso, aún sin enlazar: cuenta una vez, en las dos
        // direcciones.
        let l = ledger(baseline: 100_000, at: nov(10, 9), movements: [
            rev(-10_000, "To EUR Savings", nov(10, 11), source: .notification),
            rev(-10_000, "To EUR Savings", nov(10, 12)),
            rev(4_000, "From EUR Savings", nov(10, 13), source: .notification),
            rev(4_000, "From EUR Savings", nov(10, 12), source: .statement, bankRef: nil),
        ])
        #expect(try #require(l.savingsBalance(now: nov(10, 20))).cents == 106_000)
    }

    @Test func twinnedPendingCountsOnce() throws {
        // El banco dio el traspaso pendiente y después el apuntado con otra clave: es el mismo dinero.
        let pending = rev(-10_000, "To EUR Savings", nov(10, 11), bankRef: "p1", status: .pending, importedAt: nov(10, 11, 5))
        let booked = rev(-10_000, "To EUR Savings", nov(10, 11), bankRef: "b1", status: .booked, importedAt: nov(11, 8),
                         firstSeen: .booked)
        let l = ledger(baseline: 100_000, at: nov(10, 9), movements: [pending, booked])
        #expect(try #require(l.savingsBalance(now: nov(11, 20))).cents == 110_000)
    }

    // MARK: Intereses estimados

    @Test func interestAccruesDayByDay() {
        // 10.000,00 € al 2,00 %: 10 días terminados = 1.000.000 × 0,02 × 10 / 365 = 547,9 céntimos -> 548.
        let tenDays = savingsInterestCents(baselineCents: 1_000_000, baselineAt: nov(1, 10), flows: [],
                                           annualRateBasisPoints: 200, now: nov(11, 9), calendar: madrid)
        #expect(tenDays == 548)
        // El mismo día de la base no ha terminado ninguno.
        #expect(savingsInterestCents(baselineCents: 1_000_000, baselineAt: nov(1, 10), flows: [],
                                     annualRateBasisPoints: 200, now: nov(1, 23, 59), calendar: madrid) == 0)
        // Sin interés, nada; sobre un saldo negativo, nada.
        #expect(savingsInterestCents(baselineCents: 1_000_000, baselineAt: nov(1, 10), flows: [],
                                     annualRateBasisPoints: 0, now: nov(11, 9), calendar: madrid) == 0)
        #expect(savingsInterestCents(baselineCents: -50_000, baselineAt: nov(1, 10), flows: [],
                                     annualRateBasisPoints: 200, now: nov(11, 9), calendar: madrid) == 0)
    }

    @Test func interestFollowsTheBalanceOfEachDay() {
        // Base 10.000,00 € el día 1; +3.650,00 € el día 3 a las 15:00; hoy es el día 5: terminaron los días 1, 2, 3 y 4.
        // Saldos al final de cada día: 1.000.000, 1.000.000, 1.365.000, 1.365.000 -> 4.730.000 × 200 / 3.650.000 = 259,2.
        let cents = savingsInterestCents(baselineCents: 1_000_000, baselineAt: nov(1, 10),
                                         flows: [SavingsFlow(date: nov(3, 15), cents: 365_000)],
                                         annualRateBasisPoints: 200, now: nov(5, 9), calendar: madrid)
        #expect(cents == 259)
    }

    @Test func balanceAddsEstimatedInterest() throws {
        let l = ledger(baseline: 1_000_000, at: nov(1, 10), rate: 200)
        let s = try #require(l.savingsBalance(now: nov(11, 9)))
        #expect(s.interestCents == 548)
        #expect(s.cents == 1_000_548)
        #expect(s.annualRateBasisPoints == 200)
    }

    // MARK: Corregir el saldo

    @Test func correctionBecomesTheNewBaseline() throws {
        var l = ledger(baseline: 1_000_000, at: nov(1, 10), rate: 200, movements: [
            rev(-10_000, "To EUR Savings", nov(2, 11)),
        ])
        #expect(try #require(l.savingsBalance(now: nov(11, 9))).cents > 1_010_000)
        // El dueño pone el saldo real hoy: lo de antes queda dentro y los intereses empiezan otra vez desde aquí.
        l.setSavings(balanceCents: 1_012_345, annualRateBasisPoints: 200, now: nov(11, 9, 30))
        let corrected = try #require(l.savingsBalance(now: nov(11, 20)))
        #expect(corrected.cents == 1_012_345)
        #expect(corrected.interestCents == 0)
        #expect(corrected.baselineAt == nov(11, 9, 30))
        // Lo que llega después suma sobre la nueva base.
        l.state.movements.append(rev(-5_000, "To EUR Savings", nov(11, 12)))
        #expect(try #require(l.savingsBalance(now: nov(11, 20))).cents == 1_017_345)
        // Quitar el interés también es una corrección.
        l.setSavings(balanceCents: 1_000_000, annualRateBasisPoints: nil, now: nov(12, 9))
        let noRate = try #require(l.savingsBalance(now: nov(20, 9)))
        #expect(noRate.interestCents == 0)
        #expect(noRate.annualRateBasisPoints == nil)
    }

    // MARK: Total

    @Test func totalIncludesSavings() {
        var l = Ledger(state: LedgerState(balances: [.rev: ManualBalance(cents: 34_020, setAt: nov(10, 8), origin: .manual)]))
        #expect(l.total(now: nov(10, 20)) == 34_020)
        l.setSavings(balanceCents: 500_000, annualRateBasisPoints: nil, now: nov(10, 9))
        #expect(l.banksTotal() == 34_020)
        #expect(l.total(now: nov(10, 20)) == 534_020)
        // Sin ningún saldo de banco, el total es la cuenta remunerada.
        #expect(ledger(baseline: 500_000, at: nov(10, 9)).total(now: nov(10, 20)) == 500_000)
        #expect(Ledger(state: LedgerState()).total(now: nov(10, 20)) == nil)
    }

    // MARK: Textos

    @Test func rateInputAndFormatting() {
        #expect(parseAnnualRateInput("2,00") == 200)
        #expect(parseAnnualRateInput("2") == 200)
        #expect(parseAnnualRateInput("2,5 %") == 250)
        #expect(parseAnnualRateInput("1.75") == 175)
        #expect(parseAnnualRateInput("abc") == nil)
        #expect(parseAnnualRateInput("-1") == nil)
        #expect(parseAnnualRateInput("150") == nil)
        #expect(formatAnnualRate(200) == "2,00\u{00A0}%")
        #expect(formatAnnualRate(1_075) == "10,75\u{00A0}%")
    }

    @Test func statusTextHasNoDigitsWithTheEyeClosed() {
        let open = savingsStatusText(annualRateBasisPoints: 200, hidden: false)
        #expect(open == "estimado · 2,00\u{00A0}% anual")
        let closed = savingsStatusText(annualRateBasisPoints: 200, hidden: true)
        #expect(closed.contains("estimado"))
        #expect(!closed.contains { $0.isNumber })
        #expect(savingsStatusText(annualRateBasisPoints: nil, hidden: false) == "estimado")
        #expect(savingsStatusText(annualRateBasisPoints: nil, hidden: true) == "estimado")
    }

    // MARK: Guardado

    @Test func oldLedgerWithoutSavingsDecodesAndEncodesIdentically() throws {
        let oldJSON = """
        {"balances":[],"movements":[
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","bank":"rev","amountCents":-1250,"merchant":"Mercadona","kind":"payment",
        "source":"notification","date":0,"isShop":true}
        ],"unread":[]}
        """
        let state = try JSONDecoder().decode(LedgerState.self, from: Data(oldJSON.utf8))
        #expect(state.savings == nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let first = try encoder.encode(state)
        #expect(!String(decoding: first, as: UTF8.self).contains("savings"))
        let again = try encoder.encode(try JSONDecoder().decode(LedgerState.self, from: first))
        #expect(again == first)
        // Poner y quitar la cuenta deja el libro byte a byte como estaba.
        var touched = state
        touched.savings = SavingsAccount(baselineCents: 1, baselineAt: Date(timeIntervalSinceReferenceDate: 0))
        touched.savings = nil
        #expect(try encoder.encode(touched) == first)
    }

    @Test func savingsRoundTrips() throws {
        var state = LedgerState()
        state.savings = SavingsAccount(baselineCents: 512_345, baselineAt: nov(10, 9), annualRateBasisPoints: 200)
        let back = try JSONDecoder().decode(LedgerState.self, from: JSONEncoder().encode(state))
        #expect(back == state)
        #expect(back.savings?.annualRateBasisPoints == 200)
        // Sin interés no se escribe la clave del interés.
        let plain = SavingsAccount(baselineCents: 1, baselineAt: nov(10, 9))
        #expect(!String(decoding: try JSONEncoder().encode(plain), as: UTF8.self).contains("annualRateBasisPoints"))
    }
}
