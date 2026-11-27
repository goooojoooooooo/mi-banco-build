import Foundation
import Testing
@testable import MiBancoCore

// Cuenta remunerada, ronda de arreglos 2: el par pendiente↔apuntado se juzga como UN traspaso, y sin la consulta de después
// de guardar una fila de solo día del día de la base no cuenta (inflar el dinero es peor que no verlo).

private let madrid: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Madrid")!
    return c
}()

private func nov(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    madrid.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

private func row(_ cents: Int, _ day: Int, imported: Date, ref: String, status: BankStatus) -> Movement {
    Movement(bank: .rev, amountCents: cents, merchant: "To EUR Savings", kind: .payment, source: .bank, date: nov(day),
             bankRef: ref, bankStatus: status, importedAt: imported, dayOnly: true, firstSeenStatus: status)
}

private func savings(_ movements: [Movement], connected: Bool = false, refreshedAt: Date? = nil, now: Date) -> Int? {
    var state = LedgerState(movements: movements)
    if connected {
        state.links[.rev] = BankLinkInfo(connectedAt: nov(1), consentValidUntil: nov(30))
    }
    var l = Ledger(state: state)
    l.setSavings(balanceCents: 100_000, annualRateBasisPoints: nil, now: nov(10, 9))
    if let refreshedAt { l.noteSavingsRefresh(syncedAt: refreshedAt) }
    return l.savingsBalance(now: now).map { $0.cents - 100_000 }
}

@Suite struct SavingsRound2Tests {

    @Test func pendingSeenBeforeTheBaselineAndItsLaterBookedCountZero() {
        // El pendiente se vio antes de la base (08:00): el saldo puesto ya lo incluye. Su apuntado llega después, el mismo
        // día o el siguiente: es el mismo traspaso, no cuenta.
        let pending = row(-10_000, 10, imported: nov(10, 8), ref: "p1", status: .pending)
        let sameDay = row(-10_000, 10, imported: nov(10, 18), ref: "b1", status: .booked)
        #expect(savings([pending, sameDay], now: nov(11, 20)) == 0)
        let nextDay = row(-10_000, 11, imported: nov(11, 8), ref: "b2", status: .booked)
        #expect(savings([pending, nextDay], now: nov(11, 20)) == 0)
    }

    @Test func pendingSeenInTheSaveTimeSyncAndItsLaterBookedCountZero() {
        let pending = row(-10_000, 10, imported: nov(10, 9, 1), ref: "p1", status: .pending)
        let booked = row(-10_000, 11, imported: nov(11, 8), ref: "b1", status: .booked)
        #expect(savings([pending, booked], refreshedAt: nov(10, 9, 1), now: nov(11, 20)) == 0)
    }

    @Test func pendingAfterTheBaselineStillCountsOnce() {
        let pending = row(-10_000, 11, imported: nov(11, 8), ref: "p1", status: .pending)
        let booked = row(-10_000, 11, imported: nov(11, 18), ref: "b1", status: .booked)
        #expect(savings([pending, booked], now: nov(11, 20)) == 10_000)
    }

    @Test func connectedWithoutTheSaveTimeSyncSameDayRowsDoNotCount() {
        // Revolut conectado y sin la consulta de después de guardar: una fila de solo día del día de la base, sin aviso,
        // no se sabe si es de antes o de después de la base. No cuenta.
        let late = row(-5_000, 10, imported: nov(10, 16), ref: "b1", status: .booked)
        #expect(savings([late], connected: true, now: nov(10, 20)) == 0)
        // Con la consulta, sí (llegó después de ella).
        #expect(savings([late], connected: true, refreshedAt: nov(10, 9, 1), now: nov(10, 20)) == 5_000)
        // Un día posterior cuenta siempre.
        let tomorrow = row(-5_000, 11, imported: nov(11, 10), ref: "b2", status: .booked)
        #expect(savings([tomorrow], connected: true, now: nov(11, 20)) == 5_000)
    }
}
