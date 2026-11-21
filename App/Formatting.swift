import Foundation
import MiBancoCore

/// Fechas en español con el mismo estilo en toda la app ("18:47", "17 nov", "hoy, 18:47").
enum DateText {
    private static let spanish = Locale(identifier: "es_ES")

    /// Calendario gregoriano en Europa/Madrid y español, para alinear fechas con `MiBancoCore`.
    static let madridCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid") ?? .current
        calendar.locale = spanish
        return calendar
    }()

    /// "17:35" en hora de Madrid, independiente de la zona horaria del dispositivo o del simulador.
    static func madridTime(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(locale: spanish, timeZone: madridCalendar.timeZone)
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
        )
    }

    /// "20 nov" en fecha de Madrid.
    static func madridDay(_ date: Date) -> String {
        let month = date.formatted(
            Date.FormatStyle(locale: spanish, timeZone: madridCalendar.timeZone).month(.abbreviated)
        ).replacing(".", with: "")
        return "\(madridCalendar.component(.day, from: date)) \(month)"
    }

    /// "viernes" en fecha de Madrid (para J10: día de la última sesión sin desfase por zona UTC).
    static func madridWeekday(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(locale: spanish, timeZone: madridCalendar.timeZone).weekday(.wide)
        )
    }

    static func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: spanish).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    /// "17 nov"
    static func day(_ date: Date) -> String {
        let month = date.formatted(Date.FormatStyle(locale: spanish).month(.abbreviated)).replacing(".", with: "")
        return "\(Calendar.current.component(.day, from: date)) \(month)"
    }

    /// "Hoy, 18:47" · "Ayer, 9:10" · "Martes, 17 nov, 18:30" (o solo el día si `dayOnly` es verdadero, R13).
    static func moment(_ date: Date, dayOnly: Bool = false, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let day = LedgerSnapshot.dayTitle(calendar.startOfDay(for: date), now: now, calendar: calendar)
        return dayOnly ? day : "\(day), \(time(date))"
    }

    /// "al día, 18:47" (hoy) o "exacto, 17 nov"; "estimado" si no es exacto.
    static func balanceStatus(_ info: BalanceInfo, now: Date = Date()) -> String {
        guard !info.estimated else { return "estimado" }
        return Calendar.current.isDate(info.setAt, inSameDayAs: now) ? "al día, \(time(info.setAt))" : "exacto, \(day(info.setAt))"
    }

    /// Explicación del saldo en la cara trasera de una tarjeta (R25: nombra el origen real: banco, extracto, aviso o a mano).
    static func balanceExplanation(_ info: BalanceInfo?, bank: BankID, now: Date = Date()) -> String {
        guard let info else { return "Aún no sabemos su saldo. Escríbelo una vez y cada aviso lo mantendrá al día." }
        let isToday = Calendar.current.isDate(info.setAt, inSameDayAs: now)
        let when = isToday ? "de las \(time(info.setAt))" : "del \(day(info.setAt))"
        switch info.origin {
        case .bank:
            if !info.estimated { return "Lo dio \(bank.displayName) \(when)." }
            return "Parte del saldo que dio el banco \(when) y suma lo que ha llegado después."
        case .statement:
            if !info.estimated { return "Viene del extracto de \(bank.displayName) \(when)." }
            return "Parte del saldo del extracto \(when) y suma lo que ha llegado después."
        case .notice:
            if !info.estimated { return "Lo dijo \(bank.displayName) en su aviso \(when)." }
            return "Parte del saldo que dio el banco en su aviso \(when) y suma lo que ha llegado después."
        case .manual:
            if !info.estimated, info.fromBank { return "Lo dijo \(bank.displayName) en su aviso \(when)." }
            if info.fromBank { return "Parte del saldo que dio el banco en su aviso \(when) y suma lo que ha llegado después." }
            return "Lo corregiste \(isToday ? "hoy" : "el \(day(info.setAt))") y desde entonces suma los movimientos que llegan."
        }
    }
}
