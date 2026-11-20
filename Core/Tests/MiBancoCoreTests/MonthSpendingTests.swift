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

private func pay(_ cents: Int, _ merchant: String?, _ when: Date, bank: BankID = .rev, isShop: Bool = false,
                 flagged: Bool = false) -> Movement {
    Movement(bank: bank, amountCents: -cents, merchant: merchant, kind: .payment, source: .notification, date: when,
             isShop: isShop, flaggedNotMine: flagged)
}

private func income(_ cents: Int, _ merchant: String?, _ when: Date, bank: BankID = .ima) -> Movement {
    Movement(bank: bank, amountCents: cents, merchant: merchant, kind: .income, source: .notification, date: when)
}

private func ledger(_ movements: [Movement]) -> LedgerState { LedgerState(movements: movements) }

@Suite struct MonthSpendingTests {
    private func novemberBook() -> (state: LedgerState, mercadona19: Movement, mercadona12: Movement) {
        let m19 = pay(1250, "Mercadona", nov(19), isShop: true)
        let m12 = pay(1890, "Mercadona", nov(12), isShop: true)
        let all: [Movement] = [
            m19, m12,
            pay(1830, "Glovo", nov(14), isShop: true),
            pay(1480, "Renfe", nov(16), isShop: true),
            pay(20000, "Transferencia a imagin", nov(15, 10, 0)),
            income(20000, "Transferencia de Revolut", nov(15, 10, 5)),
            pay(4995, "Zara", nov(13), isShop: true, flagged: true),
            income(145_000, "Nómina", nov(1)),
            pay(3480, "Mercadona", date(10, 2), isShop: true),
            pay(1260, "Glovo", date(10, 5), isShop: true),
            pay(4620, "Carrefour", date(10, 11), isShop: true),
        ]
        return (ledger(all), m19, m12)
    }

    @Test func formatos() {
        #expect(formatEURWhole(47498) == "475\u{00A0}€")
        #expect(formatEURWhole(123_449) == "1.234\u{00A0}€")
        #expect(formatEURWhole(123_450) == "1.235\u{00A0}€")
        #expect(formatEURWhole(0) == "0\u{00A0}€")
        #expect(formatEURWhole(-1550) == "-16\u{00A0}€")
        #expect(changePercent(from: 8100, to: 3140) == -61)
        #expect(changePercent(from: 1260, to: 1830) == 45)
        #expect(changePercent(from: 0, to: 1480) == nil)
        #expect(formatSignedPercent(12) == "+12\u{00A0}%")
        #expect(formatSignedPercent(-30) == "-30\u{00A0}%")
        #expect(formatSignedPercent(0) == "0\u{00A0}%")
    }

    @Test func porCategoria() {
        let book = novemberBook()
        let out = monthSpending(in: book.state, month: nov(19), now: nov(19, 13), calendar: cal)
        #expect(out.totalCents == 6450)
        #expect(out.previousTotalCents == 9360)
        #expect(out.byCategory == [
            CategorySpend(category: .supermercado, cents: 3140, previousCents: 8100, count: 2),
            CategorySpend(category: .comerFuera, cents: 1830, previousCents: 1260, count: 1),
            CategorySpend(category: .transporte, cents: 1480, previousCents: 0, count: 1),
        ])
        #expect(out.monthStart == date(11, 1, 0, 0))
    }

    @Test func mesPasadoCompleto() {
        let out = monthSpending(in: novemberBook().state, month: date(10, 15), now: nov(19, 13), calendar: cal)
        #expect(out.totalCents == 9360)
        #expect(out.previousTotalCents == 0)
    }

    @Test func mesActualComparaConElMismoPuntoDelMesAnterior() {
        // R11: el día 10 se compara con el 1-10 de octubre, no con octubre entero.
        let state = ledger([
            pay(1000, "Mercadona", date(10, 4), isShop: true),
            pay(5000, "Mercadona", date(10, 25), isShop: true),
            pay(700, "Mercadona", nov(3), isShop: true),
        ])
        let out = monthSpending(in: state, month: nov(10), now: nov(10, 12), calendar: cal)
        #expect(out.totalCents == 700)
        #expect(out.previousTotalCents == 1000)
        #expect(out.byCategory == [CategorySpend(category: .supermercado, cents: 700, previousCents: 1000, count: 1)])
        // El mes pasado, visto desde diciembre, se compara con septiembre entero.
        let later = monthSpending(in: state, month: nov(10), now: date(12, 10), calendar: cal)
        #expect(later.totalCents == 700)
        #expect(later.previousTotalCents == 6000)
    }

    @Test func mesActualNoCuentaLoFuturo() {
        let state = ledger([pay(700, "Mercadona", nov(3), isShop: true), pay(900, "Mercadona", nov(25), isShop: true)])
        let out = monthSpending(in: state, month: nov(10), now: nov(10), calendar: cal)
        #expect(out.totalCents == 700)
    }

    @Test func movimientosDeUnaCategoria() {
        let book = novemberBook()
        let out = spendingMovements(in: book.state, category: .supermercado, month: nov(19), now: nov(19, 13), calendar: cal)
        #expect(out.map(\.id) == [book.mercadona19.id, book.mercadona12.id])
    }

    @Test func categoriaDeUnMovimiento() {
        var state = ledger([pay(900, "Bar Manolo", nov(3), isShop: true)])
        let m = state.movements[0]
        #expect(categoryOf(m, in: state, subscriptionKeys: []) == .comerFuera)
        state.categoryOverrides[normalizeMerchant("Bar Manolo")] = .ocio
        #expect(categoryOf(m, in: state, subscriptionKeys: []) == .ocio)
        #expect(categoryOf(income(100, "Nómina", nov(1)), in: state, subscriptionKeys: []) == nil)
    }

    private func forecastBook() -> LedgerState {
        ledger([
            pay(10000, "Lidl", nov(2), isShop: true),
            pay(5000, "Zara", nov(9), isShop: true),
            pay(1399, "Netflix", date(10, 5), isShop: true),
            pay(1399, "Netflix", nov(5), isShop: true),
            pay(1099, "Spotify", date(9, 20), isShop: true),
            pay(1099, "Spotify", date(10, 20), isShop: true),
        ])
    }

    @Test func claveDeSuscripciones() {
        let keys = subscriptionKeys(in: forecastBook(), now: nov(10, 12), calendar: cal)
        #expect(keys == [normalizeMerchant("Netflix"), normalizeMerchant("Spotify")])
    }

    @Test func prevision() {
        let out = monthForecast(in: forecastBook(), now: nov(10, 12), calendar: cal)
        #expect(out == MonthForecast(spentCents: 16399, projectedCents: 47498, pendingSubscriptionsCents: 1099))
    }

    @Test func previsionAntesDelDia5EsNil() {
        #expect(monthForecast(in: forecastBook(), now: date(11, 4, 20), calendar: cal) == nil)
    }

    @Test func mediaDeTresMeses() {
        let all = [
            pay(60000, "Lidl", date(8, 10), isShop: true),
            pay(64000, "Mercadona", date(9, 10), isShop: true),
            pay(68000, "Carrefour", date(10, 10), isShop: true),
        ]
        #expect(averageMonthlySpending(in: ledger(all), category: nil, before: nov(1), months: 3, calendar: cal) == 64000)
        // Si el libro empieza en septiembre solo cuentan septiembre y octubre.
        #expect(averageMonthlySpending(in: ledger(Array(all.dropFirst())), category: nil, before: nov(1), months: 3, calendar: cal) == 66000)
        // Un mes sin gasto de esa categoría cuenta como cero.
        let food = ledger([pay(10000, "Glovo", date(9, 10), isShop: true)])
        #expect(averageMonthlySpending(in: food, category: .comerFuera, before: nov(1), months: 3, calendar: cal) == 5000)
        #expect(averageMonthlySpending(in: food, category: .transporte, before: nov(1), months: 3, calendar: cal) == 0)
        #expect(averageMonthlySpending(in: ledger([]), category: nil, before: nov(1), months: 3, calendar: cal) == nil)
        // El libro empieza en el propio mes: no hay meses anteriores.
        #expect(averageMonthlySpending(in: ledger([pay(100, "Lidl", nov(3), isShop: true)]), category: nil, before: nov(10),
                                       months: 3, calendar: cal) == nil)
    }

    @Test func losTraspasosNoCuentan() {
        let with = LedgerState(movements: [
            pay(30000, "Transferencia a imagin", date(10, 5, 10, 0)),
            income(30000, "Transferencia de Revolut", date(10, 5, 10, 5)),
            pay(10000, "Lidl", date(10, 6), isShop: true),
            pay(10000, "Lidl", date(9, 6), isShop: true),
        ])
        #expect(averageMonthlySpending(in: with, category: nil, before: nov(1), months: 2, calendar: cal) == 10000)
    }

    @Test func reutilizaLoPrecalculado() {
        let book = novemberBook().state
        let transfers = ownTransferIDs(in: book.movements)
        let keys = subscriptionKeys(in: book, now: nov(19, 13), calendar: cal, ownTransferIDs: transfers)
        let direct = monthSpending(in: book, month: nov(19), now: nov(19, 13), calendar: cal)
        let shared = monthSpending(in: book, month: nov(19), now: nov(19, 13), calendar: cal,
                                   ownTransferIDs: transfers, subscriptionKeys: keys)
        #expect(direct == shared)
    }
}
