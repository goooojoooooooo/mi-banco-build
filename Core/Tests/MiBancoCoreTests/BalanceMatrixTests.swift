import Foundation
import Testing
@testable import MiBancoCore

/// R53: matriz de lo que aporta cada fila sobre cada clase de lectura de saldo. Cada celda dice cuánto suma la fila (con
/// su gemelo, si lo tiene) sobre la lectura y si enseña «Te quedaban». «Te quedan» (`balance`) y «Te quedaban»
/// (`balancesAfter`) salen del MISMO criterio (`rowsAddingToReading`).
///
/// Por qué cada valor: una lectura disponible incluye lo apuntado y lo retenido hasta su hora; una de solo contabilizado
/// incluye solo lo apuntado (lo pendiente del banco sigue sumando encima, de cualquier fecha de los últimos 30 días); un
/// cierre del día D incluye lo de D y antes (por día de Madrid), y lo posterior a D suma una vez, venga de donde venga.
/// Un registro que el banco ya daba en la consulta de la lectura está dentro de ella (R31).
@Suite struct BalanceMatrixTests {
    private static func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    enum Kind: String, Sendable { case available, bookedOnly, closing, closingAvailable }
    enum Row: String, Sendable {
        case pendingBankRow, bookedSeenBooked, bookedFlipped, bookedSeenAfterFetch, unlinkedCapture
        case linkedBeforeBooked, linkedBeforePending, linkedInFetchBooked, linkedInFetchPending, pendingWithTwin
    }
    /// before/at/after: respecto a la hora de la lectura; dayD/dayAfterD: día del cierre y el siguiente.
    enum Timing: String, Sendable { case before, at, after, dayD, dayAfterD }

    struct Cell: Sendable, CustomTestStringConvertible {
        let row: Row
        let kind: Kind
        let timing: Timing
        /// Céntimos que suma la fila (y su gemelo) sobre la lectura: 0 o el importe (-10,00 €), nunca dos veces.
        let delta: Int
        /// true = la fila enseña «Te quedaban» (igual al saldo actual: es la única que suma).
        let figure: Bool
        var testDescription: String { "\(row.rawValue) · \(kind.rawValue) · \(timing.rawValue)" }
    }

    private static let amount = -1_000
    private static let base = 10_000

    // Lectura normal: hora de referencia 12:59Z, consulta 13:00Z del 20.
    private static let readingAt = iso("2026-11-20T12:59:00Z")
    private static let readingFetch = iso("2026-11-20T13:00:00Z")
    // Cierre del 19 consultado el 20 a las 10:00Z: hora = fin del 19 en Madrid.
    private static let closingFetch = iso("2026-11-20T10:00:00Z")
    private static let endOfD = iso("2026-11-19T23:00:00Z")
    private static let startOfD = iso("2026-11-18T23:00:00Z")

    private static func reading(_ kind: Kind) -> ManualBalance {
        switch kind {
        case .available:
            ManualBalance(cents: base, setAt: readingAt, origin: .bank, fetchedAt: readingFetch)
        case .bookedOnly:
            ManualBalance(cents: base, setAt: readingAt, origin: .bank, fetchedAt: readingFetch, countsPending: true)
        case .closing:
            ManualBalance(cents: base, setAt: endOfD, origin: .bank, fetchedAt: closingFetch, countsPending: true,
                          closingDay: startOfD)
        case .closingAvailable:
            ManualBalance(cents: base, setAt: endOfD, origin: .bank, fetchedAt: closingFetch, closingDay: startOfD)
        }
    }

    /// Filas del banco: solo día (mediodía de Madrid = 11:00Z).
    private static func bankDate(_ t: Timing) -> Date {
        switch t {
        case .before, .dayD: iso("2026-11-19T11:00:00Z")
        case .at, .dayAfterD: iso("2026-11-20T11:00:00Z")
        case .after: iso("2026-11-21T11:00:00Z")
        }
    }

    /// Capturados: hora precisa. "after" cae entre la hora de referencia y la consulta (el caso de R31).
    private static func captureDate(_ t: Timing) -> Date {
        switch t {
        case .before: readingAt.addingTimeInterval(-3600)
        case .at: readingAt
        case .after: readingAt.addingTimeInterval(30)
        case .dayD: iso("2026-11-19T15:00:00Z")
        case .dayAfterD: iso("2026-11-20T08:00:00Z")
        }
    }

    private static func bankRow(_ status: BankStatus, firstSeen: BankStatus, imported: Date, date: Date) -> Movement {
        Movement(bank: .rev, amountCents: amount, merchant: "Cafe", kind: .payment, source: .bank, date: date,
                 bankRef: UUID().uuidString, bankStatus: status, importedAt: imported, dayOnly: true,
                 firstSeenStatus: firstSeen)
    }

    private static func capture(_ date: Date, linked status: BankStatus?, linkedAt: Date?) -> Movement {
        Movement(bank: .rev, amountCents: amount, merchant: "Cafe", kind: .payment, source: .notification, date: date,
                 bankRef: status == nil ? nil : "r", bankStatus: status, linkedAt: linkedAt)
    }

    /// La fila de la celda va primero; detrás, su gemelo apuntado si lo tiene.
    private static func movements(_ c: Cell) -> [Movement] {
        let fetch = c.kind == .closing || c.kind == .closingAvailable ? closingFetch : readingFetch
        let bd = bankDate(c.timing), cd = captureDate(c.timing)
        switch c.row {
        case .pendingBankRow: return [bankRow(.pending, firstSeen: .pending, imported: fetch, date: bd)]
        case .bookedSeenBooked: return [bankRow(.booked, firstSeen: .booked, imported: fetch, date: bd)]
        case .bookedFlipped: return [bankRow(.booked, firstSeen: .pending, imported: fetch.addingTimeInterval(-7200), date: bd)]
        case .bookedSeenAfterFetch: return [bankRow(.booked, firstSeen: .booked, imported: fetch.addingTimeInterval(3600), date: bd)]
        case .unlinkedCapture: return [capture(cd, linked: nil, linkedAt: nil)]
        case .linkedBeforeBooked: return [capture(cd, linked: .booked, linkedAt: cd.addingTimeInterval(10))]
        case .linkedBeforePending: return [capture(cd, linked: .pending, linkedAt: cd.addingTimeInterval(10))]
        case .linkedInFetchBooked: return [capture(cd, linked: .booked, linkedAt: fetch)]
        case .linkedInFetchPending: return [capture(cd, linked: .pending, linkedAt: fetch)]
        case .pendingWithTwin:
            return [bankRow(.pending, firstSeen: .pending, imported: fetch.addingTimeInterval(-3600), date: bd),
                    bankRow(.booked, firstSeen: .booked, imported: fetch, date: bd)]
        }
    }

    private static func c(_ row: Row, _ kind: Kind, _ timing: Timing, _ adds: Bool, _ figure: Bool) -> Cell {
        Cell(row: row, kind: kind, timing: timing, delta: adds ? amount : 0, figure: figure)
    }

    private static let plus = true, zero = false, figure = true, noFigure = false

    static let matrix: [Cell] = [
        // MARK: disponible (incluye apuntado y retenido hasta su hora)
        c(.pendingBankRow, .available, .before, zero, noFigure),
        c(.pendingBankRow, .available, .at, zero, noFigure),
        c(.pendingBankRow, .available, .after, zero, noFigure),
        c(.bookedSeenBooked, .available, .before, zero, noFigure),
        c(.bookedSeenBooked, .available, .at, zero, noFigure),
        c(.bookedSeenBooked, .available, .after, zero, noFigure),
        c(.bookedFlipped, .available, .before, zero, noFigure),
        c(.bookedFlipped, .available, .at, zero, noFigure),
        c(.bookedFlipped, .available, .after, zero, noFigure),
        c(.bookedSeenAfterFetch, .available, .before, zero, noFigure),
        c(.bookedSeenAfterFetch, .available, .at, zero, noFigure),
        c(.bookedSeenAfterFetch, .available, .after, zero, noFigure),
        c(.unlinkedCapture, .available, .before, zero, noFigure),
        c(.unlinkedCapture, .available, .at, zero, figure),
        c(.unlinkedCapture, .available, .after, plus, figure),
        c(.linkedBeforeBooked, .available, .before, zero, noFigure),
        c(.linkedBeforeBooked, .available, .at, zero, figure),
        c(.linkedBeforeBooked, .available, .after, zero, noFigure),
        c(.linkedBeforePending, .available, .before, zero, noFigure),
        c(.linkedBeforePending, .available, .at, zero, figure),
        c(.linkedBeforePending, .available, .after, zero, noFigure),
        c(.linkedInFetchBooked, .available, .before, zero, noFigure),
        c(.linkedInFetchBooked, .available, .at, zero, figure),
        c(.linkedInFetchBooked, .available, .after, zero, noFigure),
        c(.linkedInFetchPending, .available, .before, zero, noFigure),
        c(.linkedInFetchPending, .available, .at, zero, figure),
        c(.linkedInFetchPending, .available, .after, zero, noFigure),
        c(.pendingWithTwin, .available, .before, zero, noFigure),
        c(.pendingWithTwin, .available, .at, zero, noFigure),
        c(.pendingWithTwin, .available, .after, zero, noFigure),

        // MARK: solo contabilizado (lo pendiente del banco suma encima, sea de la fecha que sea)
        c(.pendingBankRow, .bookedOnly, .before, plus, noFigure),
        c(.pendingBankRow, .bookedOnly, .at, plus, noFigure),
        c(.pendingBankRow, .bookedOnly, .after, plus, figure),
        c(.bookedSeenBooked, .bookedOnly, .before, zero, noFigure),
        c(.bookedSeenBooked, .bookedOnly, .at, zero, noFigure),
        c(.bookedSeenBooked, .bookedOnly, .after, zero, noFigure),
        c(.bookedFlipped, .bookedOnly, .before, zero, noFigure),
        c(.bookedFlipped, .bookedOnly, .at, zero, noFigure),
        c(.bookedFlipped, .bookedOnly, .after, zero, noFigure),
        c(.bookedSeenAfterFetch, .bookedOnly, .before, zero, noFigure),
        c(.bookedSeenAfterFetch, .bookedOnly, .at, zero, noFigure),
        c(.bookedSeenAfterFetch, .bookedOnly, .after, zero, noFigure),
        c(.unlinkedCapture, .bookedOnly, .before, zero, noFigure),
        c(.unlinkedCapture, .bookedOnly, .at, zero, figure),
        c(.unlinkedCapture, .bookedOnly, .after, plus, figure),
        c(.linkedBeforeBooked, .bookedOnly, .before, zero, noFigure),
        c(.linkedBeforeBooked, .bookedOnly, .at, zero, figure),
        c(.linkedBeforeBooked, .bookedOnly, .after, zero, noFigure),
        c(.linkedBeforePending, .bookedOnly, .before, plus, noFigure),
        c(.linkedBeforePending, .bookedOnly, .at, plus, figure),
        c(.linkedBeforePending, .bookedOnly, .after, plus, figure),
        c(.linkedInFetchBooked, .bookedOnly, .before, zero, noFigure),
        c(.linkedInFetchBooked, .bookedOnly, .at, zero, figure),
        c(.linkedInFetchBooked, .bookedOnly, .after, zero, noFigure),
        c(.linkedInFetchPending, .bookedOnly, .before, plus, noFigure),
        c(.linkedInFetchPending, .bookedOnly, .at, plus, figure),
        c(.linkedInFetchPending, .bookedOnly, .after, plus, figure),
        c(.pendingWithTwin, .bookedOnly, .before, zero, noFigure),
        c(.pendingWithTwin, .bookedOnly, .at, zero, noFigure),
        c(.pendingWithTwin, .bookedOnly, .after, zero, noFigure),

        // MARK: cierre contabilizado del día D (lo posterior a D suma; lo pendiente suma siempre)
        c(.pendingBankRow, .closing, .dayD, plus, noFigure),
        c(.pendingBankRow, .closing, .dayAfterD, plus, figure),
        c(.bookedSeenBooked, .closing, .dayD, zero, noFigure),
        c(.bookedSeenBooked, .closing, .dayAfterD, plus, figure),
        c(.bookedFlipped, .closing, .dayD, zero, noFigure),
        c(.bookedFlipped, .closing, .dayAfterD, plus, figure),
        c(.bookedSeenAfterFetch, .closing, .dayD, zero, noFigure),
        c(.bookedSeenAfterFetch, .closing, .dayAfterD, plus, figure),
        c(.unlinkedCapture, .closing, .dayD, zero, noFigure),
        c(.unlinkedCapture, .closing, .dayAfterD, plus, figure),
        c(.linkedBeforeBooked, .closing, .dayD, zero, noFigure),
        c(.linkedBeforeBooked, .closing, .dayAfterD, plus, figure),
        c(.linkedBeforePending, .closing, .dayD, plus, noFigure),
        c(.linkedBeforePending, .closing, .dayAfterD, plus, figure),
        c(.linkedInFetchBooked, .closing, .dayD, zero, noFigure),
        c(.linkedInFetchBooked, .closing, .dayAfterD, plus, figure),
        c(.linkedInFetchPending, .closing, .dayD, plus, noFigure),
        c(.linkedInFetchPending, .closing, .dayAfterD, plus, figure),
        c(.pendingWithTwin, .closing, .dayD, zero, noFigure),
        c(.pendingWithTwin, .closing, .dayAfterD, plus, noFigure),

        // MARK: cierre disponible del día D (incluye lo retenido al final de D; lo posterior a D suma)
        c(.pendingBankRow, .closingAvailable, .dayD, zero, noFigure),
        c(.pendingBankRow, .closingAvailable, .dayAfterD, plus, figure),
        c(.bookedSeenBooked, .closingAvailable, .dayD, zero, noFigure),
        c(.bookedSeenBooked, .closingAvailable, .dayAfterD, plus, figure),
        c(.bookedFlipped, .closingAvailable, .dayD, zero, noFigure),
        c(.bookedFlipped, .closingAvailable, .dayAfterD, plus, figure),
        c(.bookedSeenAfterFetch, .closingAvailable, .dayD, zero, noFigure),
        c(.bookedSeenAfterFetch, .closingAvailable, .dayAfterD, plus, figure),
        c(.unlinkedCapture, .closingAvailable, .dayD, zero, noFigure),
        c(.unlinkedCapture, .closingAvailable, .dayAfterD, plus, figure),
        c(.linkedBeforeBooked, .closingAvailable, .dayD, zero, noFigure),
        c(.linkedBeforeBooked, .closingAvailable, .dayAfterD, plus, figure),
        c(.linkedBeforePending, .closingAvailable, .dayD, zero, noFigure),
        c(.linkedBeforePending, .closingAvailable, .dayAfterD, plus, figure),
        c(.linkedInFetchBooked, .closingAvailable, .dayD, zero, noFigure),
        c(.linkedInFetchBooked, .closingAvailable, .dayAfterD, plus, figure),
        c(.linkedInFetchPending, .closingAvailable, .dayD, zero, noFigure),
        c(.linkedInFetchPending, .closingAvailable, .dayAfterD, plus, figure),
        c(.pendingWithTwin, .closingAvailable, .dayD, zero, noFigure),
        c(.pendingWithTwin, .closingAvailable, .dayAfterD, plus, noFigure),
    ]

    @Test func matrixCoversEveryRowKindAndTiming() {
        // 10 filas × (2 lecturas × 3 momentos + 2 cierres × 2 días) = 100 celdas, sin repetir ninguna.
        #expect(Self.matrix.count == 100)
        #expect(Set(Self.matrix.map(\.testDescription)).count == 100)
    }

    @Test(arguments: BalanceMatrixTests.matrix)
    func balanceContributionMatrix(_ cell: Cell) {
        let base = Self.reading(cell.kind)
        let movements = Self.movements(cell)
        let subject = movements[0]
        let ledger = Ledger(state: LedgerState(balances: [.rev: base], movements: movements))
        // «Te quedan»
        let balance = ledger.balance(.rev)?.cents
        #expect(balance == Self.base + cell.delta)
        // «Te quedaban», con el mismo criterio
        let byDate = movements.sorted { $0.date > $1.date }
        let after = Ledger.balancesAfter(bank: .rev, current: balance ?? 0, reading: base, movements: byDate)
        #expect((after[subject.id] != nil) == cell.figure)
        if cell.figure { #expect(after[subject.id] == balance) }
        // Y lo que suma es exactamente lo que dice el criterio único.
        let adding = Ledger.rowsAddingToReading(movements, bank: .rev, base: base)
        #expect(movements.filter { adding.contains($0.id) }.reduce(0) { $0 + $1.amountCents } == cell.delta)
    }
}
