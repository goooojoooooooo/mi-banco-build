import Foundation

/// Cuándo se enseñó el último resumen y desde cuándo cuenta el siguiente.
public struct BriefingRecord: Codable, Equatable, Sendable {
    public var shownAt: Date
    public var since: Date

    public init(shownAt: Date, since: Date) {
        self.shownAt = shownAt
        self.since = since
    }
}

/// Un resumen al día. El día empieza a las 05:00 en el calendario que se pase (Madrid en la app): una apertura a la una y
/// media de la madrugada todavía es "ayer".
public enum BriefingSchedule {
    public static let dayStartHour = 5

    /// Lo máximo que mira hacia atrás un resumen tras muchos días sin abrir la app.
    static let maxLookbackDays = 7

    /// El día (a las 00:00) al que pertenece un instante: antes de las 05:00 cuenta como el día anterior.
    static func briefingDay(of date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        guard calendar.component(.hour, from: date) < dayStartHour,
              let previous = calendar.date(byAdding: .day, value: -1, to: start) else { return start }
        return calendar.startOfDay(for: previous)
    }

    /// El registro del resumen que toca enseñar ahora, o nil si ya se enseñó uno hoy. La primera vez mira 24 horas atrás;
    /// después, desde el resumen anterior (como mucho una semana).
    public static func due(previous: BriefingRecord?, now: Date, calendar: Calendar) -> BriefingRecord? {
        guard let previous else {
            return BriefingRecord(shownAt: now, since: now.addingTimeInterval(-86_400))
        }
        guard briefingDay(of: now, calendar: calendar) > briefingDay(of: previous.shownAt, calendar: calendar) else { return nil }
        var since = previous.shownAt
        if let limit = calendar.date(byAdding: .day, value: -maxLookbackDays, to: now), since < limit { since = limit }
        return BriefingRecord(shownAt: now, since: since)
    }

    /// Abrir el resumen a mano: si ya hay uno de hoy se devuelve tal cual (mismo "desde"); si no, el que tocaría.
    public static func manual(previous: BriefingRecord?, now: Date, calendar: Calendar) -> BriefingRecord {
        if let previous, briefingDay(of: now, calendar: calendar) <= briefingDay(of: previous.shownAt, calendar: calendar) {
            return previous
        }
        return due(previous: previous, now: now, calendar: calendar) ?? previous
            ?? BriefingRecord(shownAt: now, since: now.addingTimeInterval(-86_400))
    }
}
