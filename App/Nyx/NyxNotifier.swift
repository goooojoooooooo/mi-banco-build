import Foundation
import UserNotifications
import MiBancoCore

/// Resumen en memoria de un aviso de Nyx recién compuesto (sin registros).
struct NyxPostedAlert: Sendable {
    let title: String
    let body: String
}

/// Publica los avisos locales propios de Nyx y programa el recordatorio único de caducidad de SideStore (`nyx.expiry`).
/// Respeta siempre el ojo cerrado (`hidden`) y nunca registra datos.
enum NyxNotifier {
    static let category = "NYX"
    static let expiryIdentifier = "nyx.expiry"

    /// Construye la petición local para una decisión `.notification` o `.silentNotification`; devuelve nil para el resto.
    static func makeRequest(
        for decision: NyxDecision,
        hidden: Bool,
        now: Date,
        calendar: Calendar
    ) -> UNNotificationRequest? {
        guard decision.delivery == .notification || decision.delivery == .silentNotification else { return nil }
        let message = nyxMessage(for: decision.observation, now: now, calendar: calendar)
        let text = nyxNotificationText(message, hidden: hidden)
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        content.categoryIdentifier = category
        content.threadIdentifier = "nyx.\(decision.observation.situation.rawValue)"
        if decision.delivery == .silentNotification {
            content.sound = nil
            content.interruptionLevel = .passive
        } else {
            content.sound = .default
            content.interruptionLevel = .active
        }
        content.userInfo = [
            AlertRoute.Keys.route: AlertRoute.Keys.nyxRoute,
            AlertRoute.Keys.nyxEntryID: decision.observation.id,
        ]
        return UNNotificationRequest(
            identifier: "nyx.\(decision.observation.id)",
            content: content,
            trigger: nil
        )
    }

    /// Publica las decisiones de aviso de Nyx. Devuelve los pares `(title, body)` compuestos.
    @discardableResult
    static func post(
        _ decisions: [NyxDecision],
        hidden: Bool = AlertPoster.eyeClosed,
        now: Date = AppClock.now,
        calendar: Calendar = DateText.madridCalendar
    ) async -> [NyxPostedAlert] {
        let requests = decisions.compactMap { makeRequest(for: $0, hidden: hidden, now: now, calendar: calendar) }
        guard !requests.isEmpty else { return [] }
        let composed = requests.map { NyxPostedAlert(title: $0.content.title, body: $0.content.body) }
        #if DEBUG
        if DemoMode.isActive {
            return composed
        }
        #endif
        let center = UNUserNotificationCenter.current()
        for request in requests {
            try? await center.add(request)
        }
        return composed
    }

    /// Construye la petición única `nyx.expiry` a las `expiresAt − 24 h`, nunca en el pasado.
    static func makeExpiryRequest(
        expiresAt: Date?,
        hidden: Bool,
        now: Date,
        calendar: Calendar
    ) -> UNNotificationRequest? {
        guard let expiresAt else { return nil }
        let fireDate = expiresAt.addingTimeInterval(-24 * 3_600)
        guard fireDate > now else { return nil }
        let obs = NyxObservation(
            situation: .appExpiring,
            subject: "expiry",
            priority: .urgent,
            observedAt: fireDate,
            facts: NyxFacts(day: expiresAt)
        )
        let message = nyxMessage(for: obs, now: fireDate, calendar: calendar)
        let text = nyxNotificationText(message, hidden: hidden)
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        content.sound = .default
        content.categoryIdentifier = category
        content.threadIdentifier = "nyx.\(NyxSituation.appExpiring.rawValue)"
        content.interruptionLevel = .active
        content.userInfo = [
            AlertRoute.Keys.route: AlertRoute.Keys.nyxRoute,
            AlertRoute.Keys.nyxEntryID: obs.id,
        ]
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        parts.calendar = calendar
        parts.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        return UNNotificationRequest(identifier: expiryIdentifier, content: content, trigger: trigger)
    }

    /// Reprograma `nyx.expiry` a `expiresAt − 24 h` (o lo retira si no hay caducidad futura).
    static func scheduleExpiryReminder(
        expiresAt: Date?,
        hidden: Bool = AlertPoster.eyeClosed,
        now: Date = AppClock.now,
        calendar: Calendar = DateText.madridCalendar
    ) async {
        #if DEBUG
        if DemoMode.isActive { return }
        #endif
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [expiryIdentifier])
        guard let request = makeExpiryRequest(expiresAt: expiresAt, hidden: hidden, now: now, calendar: calendar) else {
            return
        }
        try? await center.add(request)
    }
}
