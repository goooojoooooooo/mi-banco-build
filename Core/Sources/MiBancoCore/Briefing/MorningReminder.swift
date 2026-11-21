import Foundation

/// Cuántos recordatorios matinales se programan por adelantado (`briefing-morning-0...2`).
public let morningReminderCount = 3

/// Hora por defecto del recordatorio de la mañana: 08:30 (510 minutos desde medianoche).
public let defaultMorningBriefingMinutes = 510

/// Texto fijo del aviso de la mañana (sin cifras, sin importes ni consejos: seguro en pantalla bloqueada y modo privado).
public let morningReminderText: (title: String, body: String) = (
    title: "Tu resumen de hoy",
    body: "Mira qué ha pasado desde la última vez."
)

/// Minutos desde medianoche -> "08:30" (fuera de 0..<1440 cae a "08:30"). Sin DateFormatter: igual en Linux y en iOS.
public func formatMinutesOfDay(_ minutes: Int) -> String {
    let valid = (0..<1_440).contains(minutes) ? minutes : defaultMorningBriefingMinutes
    let h = valid / 60
    let m = valid % 60
    return (h < 10 ? "0" : "") + String(h) + ":" + (m < 10 ? "0" : "") + String(m)
}

/// Subtítulo de la regla en Avisos («A las 08:30, si aún no has visto el resumen.»).
public func morningReminderSubtitle(minutes: Int) -> String {
    "A las \(formatMinutesOfDay(minutes)), si aún no has visto el resumen."
}

/// Las próximas tres fechas del aviso matinal a `minutes` (minutos desde medianoche) en `calendar`.
/// - Nunca devuelve una fecha anterior o igual a `now`.
/// - Si `shownToday` es true, salta cualquier fecha que pertenezca al mismo día de resumen que `now`
///   (`BriefingSchedule.briefingDay`, que empieza a las 05:00): así abrir a la 01:30 no se salta el aviso de las 08:30,
///   y abrir a las 07:00 sí se salta el de las 08:30 de hoy.
/// - Valores de `minutes` fuera de `0..<1440` caen a `defaultMorningBriefingMinutes` (08:30).
public func morningReminderDates(now: Date, minutes: Int, shownToday: Bool, calendar: Calendar) -> [Date] {
    let valid = (0..<1_440).contains(minutes) ? minutes : defaultMorningBriefingMinutes
    let hour = valid / 60
    let minute = valid % 60
    let todayStart = calendar.startOfDay(for: now)
    let nowBriefingDay = BriefingSchedule.briefingDay(of: now, calendar: calendar)

    var dates: [Date] = []
    var offset = 0
    while dates.count < morningReminderCount && offset < 14 {
        defer { offset += 1 }
        guard let day = calendar.date(byAdding: .day, value: offset, to: todayStart) else { break }
        let ymd = calendar.dateComponents([.year, .month, .day], from: day)
        var parts = DateComponents(year: ymd.year, month: ymd.month, day: ymd.day, hour: hour, minute: minute, second: 0)
        parts.calendar = calendar
        parts.timeZone = calendar.timeZone
        guard let candidate = calendar.date(from: parts) else { continue }
        guard candidate > now else { continue }
        if shownToday && BriefingSchedule.briefingDay(of: candidate, calendar: calendar) <= nowBriefingDay {
            continue
        }
        dates.append(candidate)
    }
    return dates
}
