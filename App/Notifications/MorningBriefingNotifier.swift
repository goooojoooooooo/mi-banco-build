import Foundation
import UserNotifications
import MiBancoCore

/// Recordatorio local de la mañana («Tu resumen de hoy», tarea 10): programa las próximas 3 fechas (`briefing-morning-0…2`)
/// en zona horaria de Madrid. Sin cifras, sin importes ni consejos (seguro en pantalla bloqueada y modo privado).
enum MorningBriefingNotifier {
    static let category = "BRIEFING"
    static var identifiers: [String] { (0..<morningReminderCount).map { "briefing-morning-\($0)" } }

    static func reschedule(settings: AlertSettings, shownToday: Bool, now: Date = Date()) async {
        #if DEBUG
        if DemoMode.isActive { return }
        #endif
        await Queue.shared.run(settings: settings, shownToday: shownToday, now: now)
    }

    fileprivate static func apply(settings: AlertSettings, shownToday: Bool, now: Date) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        guard settings.morningBriefing else { return }

        let calendar = DateText.madridCalendar
        let dates = morningReminderDates(
            now: now,
            minutes: settings.morningBriefingMinutes,
            shownToday: shownToday,
            calendar: calendar
        )
        for (index, date) in dates.enumerated() where index < identifiers.count {
            let content = UNMutableNotificationContent()
            content.title = morningReminderText.title
            content.body = morningReminderText.body
            content.sound = .default
            content.categoryIdentifier = category
            content.threadIdentifier = "briefing.morning"
            content.interruptionLevel = .active
            content.userInfo = [AlertRoute.Keys.route: AlertRoute.Keys.briefingRoute]

            var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            parts.calendar = calendar
            parts.timeZone = calendar.timeZone
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let request = UNNotificationRequest(identifier: identifiers[index], content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    /// Reprogramaciones en serie para que nunca se pisen entre sí al cambiar la hora o al abrir la app.
    private actor Queue {
        static let shared = Queue()
        private var running = false
        private var next: (settings: AlertSettings, shownToday: Bool, now: Date)?

        func run(settings: AlertSettings, shownToday: Bool, now: Date) async {
            next = (settings, shownToday, now)
            guard !running else { return }
            running = true
            while let job = next {
                next = nil
                await MorningBriefingNotifier.apply(settings: job.settings, shownToday: job.shownToday, now: job.now)
            }
            running = false
        }
    }
}
