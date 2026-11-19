import Foundation
import MiBancoCore

/// Fechas en español con el mismo estilo en toda la app ("18:47", "17 nov", "hoy, 18:47").
enum DateText {
    private static let spanish = Locale(identifier: "es_ES")

    static func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: spanish).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    /// "17 nov"
    static func day(_ date: Date) -> String {
        let month = date.formatted(Date.FormatStyle(locale: spanish).month(.abbreviated)).replacing(".", with: "")
        return "\(Calendar.current.component(.day, from: date)) \(month)"
    }

    /// "Hoy, 18:47" · "Ayer, 9:10" · "Martes, 17 nov, 18:30"
    static func moment(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let day = LedgerSnapshot.dayTitle(calendar.startOfDay(for: date), now: now, calendar: calendar)
        return "\(day), \(time(date))"
    }

    /// "al día, 18:47" (hoy) o "exacto, 17 nov"; "estimado" si no es exacto.
    static func balanceStatus(_ info: BalanceInfo, now: Date = Date()) -> String {
        guard !info.estimated else { return "estimado" }
        return Calendar.current.isDate(info.setAt, inSameDayAs: now) ? "al día, \(time(info.setAt))" : "exacto, \(day(info.setAt))"
    }

    /// Explicación del saldo en la cara trasera de una tarjeta.
    static func balanceExplanation(_ info: BalanceInfo?, bank: BankID, now: Date = Date()) -> String {
        guard let info else { return "Aún no sabemos su saldo. Escríbelo una vez y cada aviso lo mantendrá al día." }
        let when = Calendar.current.isDate(info.setAt, inSameDayAs: now) ? "de las \(time(info.setAt))" : "del \(day(info.setAt))"
        if !info.estimated { return "Lo dijo \(bank.displayName) en su aviso \(when)." }
        if info.fromBank { return "Parte del saldo que dio el banco en su aviso \(when) y suma lo que ha llegado después." }
        return "Lo corregiste \(Calendar.current.isDate(info.setAt, inSameDayAs: now) ? "hoy" : "el \(day(info.setAt))") y desde entonces suma los movimientos que llegan."
    }
}
