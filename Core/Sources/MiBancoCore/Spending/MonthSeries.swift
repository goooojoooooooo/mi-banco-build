import Foundation

/// Un punto del gráfico del mes: lo gastado desde el día 1 hasta el final del día `day` (el día 0 es el arranque: 0).
public struct MonthSeriesPoint: Equatable, Sendable, Identifiable {
    public let day: Int
    public let cents: Int
    public var id: Int { day }

    public init(day: Int, cents: Int) {
        self.day = day
        self.cents = cents
    }
}

/// El gasto acumulado día a día de un mes y el del mes anterior ENTERO, para el gráfico de Gasto.
/// - `current`: del día 0 al último día que puede tener datos (hoy en el mes en curso; el último día en un mes pasado;
///   solo el día 0 en un mes que aún no ha empezado). Su último punto es el total del mes (`monthSpending`).
/// - `previous`: el mes anterior de punta a punta (del día 0 a su último día), sin recortar: es la línea de referencia.
public struct MonthSeries: Equatable, Sendable {
    public let monthStart: Date
    public let days: Int
    public let previousDays: Int
    public let current: [MonthSeriesPoint]
    public let previous: [MonthSeriesPoint]

    public init(monthStart: Date, days: Int, previousDays: Int, current: [MonthSeriesPoint], previous: [MonthSeriesPoint]) {
        self.monthStart = monthStart
        self.days = days
        self.previousDays = previousDays
        self.current = current
        self.previous = previous
    }

    /// Lo gastado en el mes (hasta hoy si es el mes en curso).
    public var totalCents: Int { current.last?.cents ?? 0 }
    /// Lo gastado en el mes anterior entero.
    public var previousTotalCents: Int { previous.last?.cents ?? 0 }
    /// El importe más alto de las dos líneas: el techo del eje.
    public var topCents: Int { max(totalCents, previousTotalCents) }
    /// Ni este mes ni el anterior tienen gasto: no hay nada que dibujar.
    public var isEmpty: Bool { topCents <= 0 }
    /// Días del eje horizontal: el mes más largo de los dos.
    public var axisDays: Int { max(days, previousDays, 1) }

    /// Paso «redondo» del eje de importes, en céntimos: 1, 2 o 5 × 10ⁿ euros; el menor que deja como mucho `maxLines`
    /// líneas hasta `topCents`. Con un techo de 0 o menos devuelve 1 € (no habrá líneas).
    public static func axisStep(topCents: Int, maxLines: Int = 3) -> Int {
        let lines = max(1, maxLines)
        var magnitude = 100
        while true {
            for factor in [1, 2, 5] {
                let step = magnitude * factor
                if topCents / step <= lines { return step }
            }
            // Un importe que no cabe en un `Int` multiplicado por 10 no existe; se corta antes de desbordar.
            if magnitude > Int.max / 50 { return magnitude * 5 }
            magnitude *= 10
        }
    }

    /// Las líneas del eje de importes (en céntimos), de menor a mayor; vacío si el techo no llega al primer paso.
    public func axisTicks(maxLines: Int = 3) -> [Int] {
        let top = topCents
        guard top > 0 else { return [] }
        let step = Self.axisStep(topCents: top, maxLines: maxLines)
        guard step <= top else { return [] }
        return Array(stride(from: step, through: top, by: step))
    }
}

/// La serie del gráfico de un mes. Cuenta exactamente lo mismo que `monthSpending` (pagos tuyos, sin los «no es mío», sin
/// traspasos ni capturados sin confirmar; en el mes en curso, solo hasta `now`, con los de solo día desde el inicio de su
/// día): el último punto de `current` es `monthSpending(...).totalCents`. Quien lo llama para varios meses calcula
/// `spendingExclusions(in:now:)` una vez y lo pasa.
public func monthSeries(in state: LedgerState, month: Date, now: Date, calendar: Calendar,
                        notSpending ownTransfers: Set<UUID>? = nil) -> MonthSeries {
    guard let interval = calendar.dateInterval(of: .month, for: month),
          let previousStart = calendar.date(byAdding: .month, value: -1, to: interval.start) else {
        return MonthSeries(monthStart: month, days: 0, previousDays: 0,
                           current: [MonthSeriesPoint(day: 0, cents: 0)], previous: [MonthSeriesPoint(day: 0, cents: 0)])
    }
    let days = calendar.range(of: .day, in: .month, for: interval.start)?.count ?? 0
    let previousDays = calendar.range(of: .day, in: .month, for: previousStart)?.count ?? 0
    let isCurrent = now >= interval.start && now < interval.end
    // Hasta qué día llega la línea: hoy, el último día (mes pasado) o ninguno (mes que aún no ha empezado).
    let lastDay = isCurrent ? calendar.component(.day, from: now) : (now >= interval.end ? days : 0)

    var byDay = [Int](repeating: 0, count: days + 1)
    var previousByDay = [Int](repeating: 0, count: previousDays + 1)
    let transfers = ownTransfers ?? spendingExclusions(in: state, now: now)
    for m in spendingMovements(in: state.movements, notSpending: transfers) {
        let amount = abs(m.amountCents)
        if m.date >= interval.start {
            // Igual que la ventana del mes en `monthSpending`: en curso, hasta `now`; pasado, hasta su final.
            let counts = isCurrent ? movementCounts(m, upTo: now, calendar: calendar) : (now >= interval.end && m.date < interval.end)
            guard counts else { continue }
            let day = min(max(calendar.component(.day, from: m.date), 1), max(lastDay, 1))
            if day < byDay.count { byDay[day] += amount }
        } else if m.date >= previousStart {
            let day = calendar.component(.day, from: m.date)
            if day >= 1, day < previousByDay.count { previousByDay[day] += amount }
        }
    }

    func accumulated(_ perDay: [Int], through last: Int) -> [MonthSeriesPoint] {
        var sum = 0
        var out = [MonthSeriesPoint(day: 0, cents: 0)]
        guard last >= 1 else { return out }
        for day in 1...min(last, max(perDay.count - 1, 1)) where day < perDay.count {
            sum += perDay[day]
            out.append(MonthSeriesPoint(day: day, cents: sum))
        }
        return out
    }

    return MonthSeries(
        monthStart: interval.start, days: days, previousDays: previousDays,
        current: accumulated(byDay, through: lastDay),
        previous: accumulated(previousByDay, through: previousDays))
}
