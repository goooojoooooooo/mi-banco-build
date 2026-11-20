import Foundation
import MiBancoCore

/// Gasto (solo pagos que son tuyos) de los últimos 7 días, de más antiguo a hoy, de todos los bancos o de uno.
/// Se calcula una vez por cambio de estado o de día.
struct WeekSpend: Sendable, Equatable {
    struct Day: Identifiable, Sendable, Equatable {
        /// 0 = hace 6 días, 6 = hoy.
        var id: Int
        /// Inicial del día: L M X J V S D.
        var initial: String
        var spokenName: String
        var cents: Int
    }

    var days: [Day] = []
    var totalCents = 0
    var peakID: Int?
    var maxCents = 0
    /// Resumen para VoiceOver, ya redactado (sin cifras cuando el modo privado está activo: ver `spokenSummary`).
    var summary = ""

    init() {}

    init(movements: [Movement], bank: BankID?, now: Date, calendar: Calendar = .current, notSpending: Set<UUID>? = nil) {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -6, to: today) else { return }

        var spent = Array(repeating: 0, count: 7)
        for m in spendingMovements(in: movements, notSpending: notSpending) where m.date >= start && m.amountCents < 0 {
            if let bank, m.bank != bank { continue }
            let index = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: m.date)).day ?? -1
            guard (0..<7).contains(index) else { continue }
            spent[index] += -m.amountCents
        }

        let wide = Date.FormatStyle(locale: Locale(identifier: "es_ES")).weekday(.wide)
        for i in 0..<7 {
            let date = calendar.date(byAdding: .day, value: i, to: start) ?? start
            let weekday = calendar.component(.weekday, from: date)
            days.append(Day(id: i, initial: Self.initials[(weekday - 1) % 7],
                            spokenName: i == 6 ? "hoy" : date.formatted(wide), cents: spent[i]))
        }
        totalCents = spent.reduce(0, +)
        if let peak = days.max(by: { $0.cents < $1.cents }), peak.cents > 0 {
            peakID = peak.id
            maxCents = peak.cents
            summary = "El día que más, \(peak.spokenName), con \(formatEUR(peak.cents))."
        }
    }

    /// `Calendar.component(.weekday)`: 1 = domingo.
    private static let initials = ["D", "L", "M", "X", "J", "V", "S"]
}
