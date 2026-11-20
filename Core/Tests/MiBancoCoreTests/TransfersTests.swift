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

/// Pago si `cents < 0`, ingreso si no.
private func t(_ bank: BankID, _ cents: Int, _ merchant: String?, _ when: Date, isShop: Bool = false,
               flagged: Bool = false, ownTransfer: Bool? = nil) -> Movement {
    Movement(bank: bank, amountCents: cents, merchant: merchant, kind: cents < 0 ? .payment : .income,
             source: .notification, date: when, isShop: isShop, flaggedNotMine: flagged, ownTransfer: ownTransfer)
}

@Suite struct TransferTests {
    @Test func parBasico() {
        let out = t(.rev, -20000, "Transferencia a imagin", nov(18, 10, 0))
        let inc = t(.ima, 20000, "Transferencia de Revolut", nov(18, 10, 5))
        let pairs = ownTransferPairs(in: [out, inc])
        #expect(pairs == [OwnTransferPair(paymentID: out.id, incomeID: inc.id)])
    }

    @Test func limiteDeTresDias() {
        let out = t(.rev, -20000, "Transferencia", nov(18, 10, 0))
        #expect(ownTransferPairs(in: [out, t(.ima, 20000, "Transferencia", nov(21, 10, 0))]).count == 1)
        #expect(ownTransferPairs(in: [out, t(.ima, 20000, "Transferencia", nov(21, 10, 1))]).isEmpty)
    }

    @Test func casosQueNoEmparejan() {
        let out = t(.rev, -20000, "Transferencia", nov(18))
        #expect(ownTransferPairs(in: [out, t(.rev, 20000, "Transferencia", nov(18))]).isEmpty)
        #expect(ownTransferPairs(in: [out, t(.ima, 19999, "Transferencia", nov(18))]).isEmpty)
        let shop = t(.rev, -20000, "Tienda", nov(18), isShop: true)
        #expect(ownTransferPairs(in: [shop, t(.ima, 20000, "Devolución", nov(18))]).isEmpty)
    }

    @Test func ganaElMasCercano() {
        let out = t(.rev, -20000, "Transferencia", nov(18, 10))
        let far = t(.ima, 20000, "Transferencia", nov(17, 10))
        let near = t(.tr, 20000, "Transferencia", nov(18, 12))
        let pairs = ownTransferPairs(in: [out, far, near])
        #expect(pairs == [OwnTransferPair(paymentID: out.id, incomeID: near.id)])
    }

    @Test func cadaUnoUnaVez() {
        let first = t(.rev, -5000, "Transferencia", nov(10, 12))
        let second = t(.rev, -5000, "Transferencia", nov(11, 12))
        let inc = t(.ima, 5000, "Transferencia", nov(11, 13))
        let pairs = ownTransferPairs(in: [first, second, inc])
        #expect(pairs == [OwnTransferPair(paymentID: second.id, incomeID: inc.id)])
    }

    @Test func decisionesDelDueno() {
        let out = t(.rev, -20000, "Transferencia", nov(18, 10, 0))
        let inc = t(.ima, 20000, "Transferencia", nov(18, 10, 5), ownTransfer: false)
        #expect(ownTransferPairs(in: [out, inc]).isEmpty)
        let loose = t(.rev, -700, "Carlos", nov(18), ownTransfer: true)
        #expect(ownTransferIDs(in: [loose]).contains(loose.id))
    }

    @Test func gastoExcluye() {
        let out = t(.rev, -20000, "Transferencia a imagin", nov(18, 10, 0))
        let inc = t(.ima, 20000, "Transferencia de Revolut", nov(18, 10, 5))
        let notMine = t(.rev, -999, "Algo raro", nov(18), flagged: true)
        let mercadona = t(.rev, -1250, "Mercadona", nov(19), isShop: true)
        let salary = t(.ima, 3500, "Nómina", nov(19))
        let spending = spendingMovements(in: [out, inc, notMine, mercadona, salary])
        #expect(spending.map(\.id) == [mercadona.id])
    }

    @Test func ritmoSinTraspasos() {
        let out = t(.rev, -20000, "Transferencia a imagin", nov(5, 10, 0))
        let inc = t(.ima, 20000, "Transferencia de Revolut", nov(5, 10, 5))
        let base = [t(.rev, -1000, "Mercadona", date(10, 5), isShop: true), t(.rev, -2000, "Mercadona", nov(6), isShop: true)]
        let with = spendingPace(movements: base + [out, inc], now: nov(19), calendar: cal)
        let without = spendingPace(movements: base, now: nov(19), calendar: cal)
        #expect(with == without)
        #expect(with?.thisMonthCents == 2000)
    }

    @Test func traspasoMensualNoEsSuscripcion() {
        var all: [Movement] = []
        for when in [date(9, 1), date(10, 1), nov(1)] {
            all.append(t(.rev, -20000, "Transferencia a imagin", when))
            all.append(t(.ima, 20000, "Transferencia de Revolut", when.addingTimeInterval(300)))
        }
        #expect(detectSubscriptions(in: all, now: nov(19), calendar: cal).isEmpty)
        let state = LedgerState(movements: all)
        let found = insights(for: state, now: nov(19), calendar: cal)
        let ids = Set(all.map(\.id))
        #expect(!found.contains { ($0.kind == .largeIncome || $0.kind == .largePayment) && $0.movementID.map(ids.contains) == true })
    }

    @Test func setOwnTransferGuardaYVuelveANil() {
        let m = t(.rev, -700, "Carlos", nov(18))
        var ledger = Ledger(state: LedgerState(movements: [m]))
        ledger.setOwnTransfer(false, for: m.id)
        #expect(ledger.state.movements[0].ownTransfer == false)
        ledger.setOwnTransfer(nil, for: m.id)
        #expect(ledger.state.movements[0].ownTransfer == nil)
    }
}
