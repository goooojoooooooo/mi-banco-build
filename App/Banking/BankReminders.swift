import Foundation
import MiBancoCore
import UserNotifications

/// Avisos locales de caducidad del consentimiento (10 días antes y al caducar). Los textos y las fechas salen de Core
/// (`bankReminders`); aquí solo se programan. Se rehacen tras cada cambio de conexión y cada consulta, con
/// identificadores fijos: lo que ya no toca (desconexión, renovación) se quita y lo demás se sustituye, nunca se duplica.
/// No son avisos de movimientos: categoría propia `BANK_CONSENT`.
enum BankReminders {
    static let category = "BANK_CONSENT"
    /// Claves del `userInfo` para llevar a Ajustes › Bancos (la pantalla llega con la tarea 11; hasta entonces el toque
    /// abre la pestaña Avisos).
    static let routeKey = "route"
    static let routeValue = "bank"
    static let bankKey = "bank"

    static func reschedule(links: [BankID: BankLinkInfo]) async {
        let planned = bankReminders(links: links, now: Date(), calendar: bankingCalendar)
        let center = UNUserNotificationCenter.current()
        // Sin puntos de suspensión: dos llamadas seguidas se encolan en orden y gana siempre la última.
        let keep = Set(planned.map(\.id))
        let stale = BankID.allCases.flatMap { bankReminderIDs(for: $0) }.filter { !keep.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        for reminder in planned {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.categoryIdentifier = category
            content.threadIdentifier = "bank-consent"
            content.interruptionLevel = .active
            content.userInfo = [routeKey: routeValue, bankKey: reminder.bank.rawValue]
            var parts = bankingCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireAt)
            parts.calendar = bankingCalendar
            parts.timeZone = bankingCalendar.timeZone
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            // Mismo identificador: sustituye al pendiente. Sin permiso simplemente no sale.
            center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)) { _ in }
        }
    }
}
