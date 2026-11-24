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

private func pay(_ cents: Int, _ merchant: String?, _ when: Date, bank: BankID = .rev, flagged: Bool = false,
                 dayOnly: Bool = false) -> Movement {
    Movement(bank: bank, amountCents: -cents, merchant: merchant, kind: .payment, source: .notification, date: when,
             isShop: true, flaggedNotMine: flagged, dayOnly: dayOnly)
}

private func income(_ cents: Int, _ merchant: String?, _ when: Date, bank: BankID = .ima) -> Movement {
    Movement(bank: bank, amountCents: cents, merchant: merchant, kind: .income, source: .notification, date: when)
}

private func ledger(_ movements: [Movement]) -> LedgerState { LedgerState(movements: movements) }

/// El gráfico del mes de Gasto: gasto acumulado día a día, con el mes anterior entero de referencia.
@Suite struct MonthSeriesTests {
    /// Noviembre de 2026 visto el día 20 a las 12:00, con octubre y septiembre detrás.
    private func book() -> LedgerState {
        ledger([
            pay(1000, "Mercadona", date(11, 3, 10)),
            pay(500, "Bar Pepe", date(11, 3, 21)),
            pay(2000, "Zara", date(11, 10)),
            pay(700, "Glovo", date(11, 20, 11)),
            // Después de «ahora» (hoy por la tarde y dentro de cinco días): aún no cuentan.
            pay(900, "Renfe", date(11, 20, 18)),
            pay(4000, "Decathlon", date(11, 25)),
            // No son gasto: un ingreso, un «no es mío» y un traspaso entre tus cuentas.
            income(145_000, "Nómina", date(11, 2)),
            pay(4995, "Zara", date(11, 13), flagged: true),
            Movement(bank: .rev, amountCents: -20_000, merchant: "Transferencia a imagin", kind: .payment,
                     source: .notification, date: date(11, 15, 10, 0)),
            Movement(bank: .ima, amountCents: 20_000, merchant: "Transferencia de Revolut", kind: .income,
                     source: .notification, date: date(11, 15, 10, 1)),
            // Octubre (31 días) y septiembre (30).
            pay(3000, "Carrefour", date(10, 5)),
            pay(1200, "Lidl", date(10, 31, 23)),
            pay(800, "Repsol", date(9, 30)),
        ])
    }

    @Test func mesEnCursoAcumulaDiaADiaHastaHoy() {
        let series = monthSeries(in: book(), month: date(11, 20), now: date(11, 20), calendar: cal)
        #expect(series.days == 30)
        #expect(series.previousDays == 31)
        #expect(series.axisDays == 31)
        // Del día 0 al 20: 21 puntos, uno por día, en orden.
        #expect(series.current.map(\.day) == Array(0...20))
        #expect(series.current[0].cents == 0)
        #expect(series.current[2].cents == 0)
        #expect(series.current[3].cents == 1500)
        #expect(series.current[9].cents == 1500)
        #expect(series.current[10].cents == 3500)
        #expect(series.current[19].cents == 3500)
        #expect(series.current[20].cents == 4200)
        #expect(series.totalCents == 4200)
    }

    @Test func elUltimoPuntoEsElTotalDeGasto() {
        let state = book()
        for (month, now) in [(date(11, 20), date(11, 20)), (date(10, 15), date(11, 20)), (date(9, 1), date(11, 20)),
                             (date(11, 1), date(11, 30, 23, 59))] {
            let series = monthSeries(in: state, month: month, now: now, calendar: cal)
            let spending = monthSpending(in: state, month: month, now: now, calendar: cal)
            #expect(series.totalCents == spending.totalCents)
            #expect(series.monthStart == spending.monthStart)
        }
    }

    @Test func elMesAnteriorVaEnteroSinRecortar() {
        let series = monthSeries(in: book(), month: date(11, 20), now: date(11, 20), calendar: cal)
        // Octubre de punta a punta (0…31), aunque noviembre vaya por el día 20.
        #expect(series.previous.map(\.day) == Array(0...31))
        #expect(series.previous[4].cents == 0)
        #expect(series.previous[5].cents == 3000)
        #expect(series.previous[30].cents == 3000)
        #expect(series.previous[31].cents == 4200)
        #expect(series.previousTotalCents == 4200)
        #expect(series.topCents == 4200)
    }

    @Test func unMesPasadoLlegaASuUltimoDia() {
        let series = monthSeries(in: book(), month: date(10, 9), now: date(11, 20), calendar: cal)
        #expect(series.days == 31)
        #expect(series.previousDays == 30)
        #expect(series.current.map(\.day) == Array(0...31))
        #expect(series.current[31].cents == 4200)
        // Su referencia es septiembre entero.
        #expect(series.previous.map(\.day) == Array(0...30))
        #expect(series.previous[29].cents == 0)
        #expect(series.previous[30].cents == 800)
    }

    @Test func nuncaBaja() {
        let state = book()
        for month in [date(11, 20), date(10, 1), date(9, 1)] {
            let series = monthSeries(in: state, month: month, now: date(11, 20), calendar: cal)
            for line in [series.current, series.previous] {
                for (a, b) in zip(line, line.dropFirst()) {
                    #expect(b.cents >= a.cents)
                    #expect(b.day == a.day + 1)
                }
            }
        }
    }

    @Test func unPagoDeSoloDiaCuentaDesdeElInicioDeSuDia() {
        // Fila del banco de hoy (guardada a las 12:00) vista a las 9:00: ya cuenta. La de mañana, no.
        let state = ledger([
            pay(1500, "Mercadona", date(11, 20, 12), dayOnly: true),
            pay(900, "Lidl", date(11, 21, 12), dayOnly: true),
        ])
        let now = date(11, 20, 9)
        let series = monthSeries(in: state, month: now, now: now, calendar: cal)
        #expect(series.current.last == MonthSeriesPoint(day: 20, cents: 1500))
        #expect(series.totalCents == monthSpending(in: state, month: now, now: now, calendar: cal).totalCents)
    }

    @Test func sinGastoEsUnaLineaPlanaYSeDicePorVacia() {
        let now = date(11, 4)
        let series = monthSeries(in: ledger([income(1000, "Bizum", date(11, 2))]), month: now, now: now, calendar: cal)
        #expect(series.current.map(\.cents) == [0, 0, 0, 0, 0])
        #expect(series.previous.count == 32)
        #expect(series.isEmpty)
        #expect(series.axisTicks().isEmpty)
    }

    @Test func conGastoSoloElMesAnteriorNoEstaVacia() {
        let now = date(11, 4)
        let series = monthSeries(in: ledger([pay(2500, "Zara", date(10, 12))]), month: now, now: now, calendar: cal)
        #expect(series.totalCents == 0)
        #expect(series.previousTotalCents == 2500)
        #expect(!series.isEmpty)
    }

    @Test func unMesQueNoHaEmpezadoSoloTieneElArranque() {
        let series = monthSeries(in: book(), month: date(12, 1), now: date(11, 20), calendar: cal)
        #expect(series.current == [MonthSeriesPoint(day: 0, cents: 0)])
        // Su mes anterior (noviembre) sí está, entero: lo fechado hasta el día 30, también lo que aún no ha pasado.
        #expect(series.previous.count == 31)
    }

    @Test func febreroCortoYElCambioDeAno() {
        let march = monthSeries(in: ledger([]), month: date(3, 10, year: 2027), now: date(3, 10, year: 2027), calendar: cal)
        #expect(march.days == 31)
        #expect(march.previousDays == 28)
        #expect(march.axisDays == 31)
        #expect(march.current.count == 11)
        #expect(march.previous.count == 29)
        // Enero: el mes anterior es diciembre del año pasado.
        let state = ledger([pay(1000, "Lidl", date(12, 31, 20)), pay(300, "Bar", date(1, 1, 1, year: 2027))])
        let january = monthSeries(in: state, month: date(1, 2, year: 2027), now: date(1, 2, year: 2027), calendar: cal)
        #expect(january.previous.last == MonthSeriesPoint(day: 31, cents: 1000))
        #expect(january.current.map(\.cents) == [0, 300, 300])
    }

    @Test func lasExclusionesQueSePasanSonLasQueSeUsan() {
        let extra = pay(2000, "Zara", date(11, 10))
        let state = ledger([pay(1000, "Mercadona", date(11, 3)), extra])
        let now = date(11, 20)
        let series = monthSeries(in: state, month: now, now: now, calendar: cal, notSpending: [extra.id])
        #expect(series.totalCents == 1000)
    }

    @Test func elPasoDelEjeEsRedondoYDejaPocasLineas() {
        // 946,41 € → cada 500 € (cada 200 € serían cuatro líneas).
        #expect(MonthSeries.axisStep(topCents: 94_641) == 50_000)
        // 1.290 € → cada 500 € (dos líneas); 300 € → cada 100 € (tres); 42 € → cada 20 € (dos).
        #expect(MonthSeries.axisStep(topCents: 129_000) == 50_000)
        #expect(MonthSeries.axisStep(topCents: 30_000) == 10_000)
        #expect(MonthSeries.axisStep(topCents: 4_200) == 2_000)
        // Sin gasto o con menos de 1 €: 1 € (y ninguna línea).
        #expect(MonthSeries.axisStep(topCents: 0) == 100)
        #expect(MonthSeries.axisStep(topCents: -500) == 100)
        // Un importe enorme no desborda.
        #expect(MonthSeries.axisStep(topCents: Int.max) > 0)
        for top in [1, 99, 100, 101, 999, 12_345, 94_641, 129_000, 5_000_000, 987_654_321] {
            let step = MonthSeries.axisStep(topCents: top)
            #expect(top / step <= 3)
            // 1, 2 o 5 seguido de ceros (en euros).
            let digits = String(step / 100)
            #expect(["1", "2", "5"].contains(String(digits.prefix(1))))
            #expect(digits.dropFirst().allSatisfy { $0 == "0" })
        }
    }

    @Test func lasLineasDelEjeNoPasanDelTecho() {
        let series = monthSeries(in: book(), month: date(11, 20), now: date(11, 20), calendar: cal)
        // Techo 42,00 € → 20 € y 40 €.
        #expect(series.axisTicks() == [2_000, 4_000])
        let small = monthSeries(in: ledger([pay(50, "Chicle", date(11, 3))]), month: date(11, 20), now: date(11, 20), calendar: cal)
        #expect(small.axisTicks().isEmpty)
    }
}
