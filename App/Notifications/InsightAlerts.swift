import Foundation
import UserNotifications
import MiBancoCore

/// Avisos de ideas (`immediateAlerts`): uno por aviso, nunca dos veces el mismo id. Todo en el iPhone, sin push.
/// No se registra nada (ni importes, ni comercios, ni textos).
enum InsightNotifier {
    static let category = "INSIGHT"
    private static let postedKey = "postedInsightIDs"
    private static let postedLimit = 200

    static func post(_ insights: [Insight]) async {
        guard !insights.isEmpty else { return }
        let defaults = UserDefaults.standard
        var posted = defaults.stringArray(forKey: postedKey) ?? []
        let already = Set(posted)
        let fresh = insights.filter { !already.contains($0.id) }
        guard !fresh.isEmpty else { return }
        // Se apuntan antes de publicar: si dos ingestas coinciden, la segunda ya no lo repite.
        posted = Array((posted + fresh.map(\.id)).suffix(postedLimit))
        defaults.set(posted, forKey: postedKey)

        let center = UNUserNotificationCenter.current()
        for insight in fresh {
            let content = UNMutableNotificationContent()
            content.title = insight.title
            content.body = insight.detail ?? ""
            content.sound = .default
            content.categoryIdentifier = category
            content.threadIdentifier = "insight.\(insight.kind.rawValue)"
            content.interruptionLevel = .active
            var info: [String: Any] = [AlertRoute.Keys.route: AlertRoute.Keys.insightRoute,
                                       AlertRoute.Keys.insightID: insight.id]
            if let id = insight.movementID { info[AlertRoute.Keys.movementID] = id.uuidString }
            content.userInfo = info
            let request = UNNotificationRequest(identifier: "insight.\(insight.id)", content: content, trigger: nil)
            try? await center.add(request)
        }
    }
}

/// Avisos programados, rehechos cada vez que cambia el libro y al arrancar (se quitan y se vuelven a poner con
/// identificadores fijos, así nunca se duplican): el resumen de los próximos 4 domingos a las 20:00 (el primero con
/// sus cifras; los demás, neutros, por si la app no vuelve a abrirse) y un recordatorio a las 10:00 del día antes de
/// cada cobro de suscripción en los próximos 30 días. Como mucho 20 pendientes (4 + 16).
/// Las reprogramaciones van en fila (`ScheduleQueue`): gana siempre la última y nunca se pisan entre sí.
enum AlertScheduler {
    static let weeklyCount = 4
    static var weeklyIDs: [String] { (0..<weeklyCount).map { "scheduled.weekly.\($0)" } }
    /// Identificador de la versión anterior (un solo domingo): se sigue quitando.
    static let legacyWeeklyID = "scheduled.weekly"
    static let subscriptionLimit = 16
    static var subscriptionIDs: [String] { (0..<19).map { "scheduled.subscription.\($0)" } }

    static func reschedule(for state: LedgerState, now: Date = Date(), calendar: Calendar = .current) async {
        await ScheduleQueue.shared.run(state: state, now: now, calendar: calendar)
    }

    /// Quita todos los identificadores fijos y añade los planeados. Solo la llama `ScheduleQueue`, de una en una.
    fileprivate static func apply(_ state: LedgerState, now: Date, calendar: Calendar) async {
        let requests = plannedRequests(for: state, now: now, calendar: calendar)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [legacyWeeklyID] + weeklyIDs + subscriptionIDs)
        for request in requests {
            try? await center.add(request)
        }
    }

    static func plannedRequests(for state: LedgerState, now: Date, calendar: Calendar) -> [UNNotificationRequest] {
        var out: [UNNotificationRequest] = []
        let settings = state.alertSettings

        if settings.weeklyDigest, let first = nextSunday8pm(after: now, calendar: calendar) {
            for week in 0..<weeklyCount {
                guard let fire = calendar.date(byAdding: .day, value: 7 * week, to: first) else { continue }
                if week == 0 {
                    // Esta semana: con sus cifras, y nada si no has gastado (ni esta ni la anterior).
                    let summary = weekSummary(movements: state.movements, weekContaining: fire, calendar: calendar)
                    guard summary.spentCents > 0 || summary.previousWeekSpentCents > 0 else { continue }
                    let text = weeklyDigestText(for: state, weekContaining: fire, calendar: calendar)
                    out.append(request(id: weeklyIDs[week], title: text.title, body: text.body, kind: .weeklyDigest,
                                       at: fire, calendar: calendar))
                } else {
                    // Semanas que aún no han pasado: sin cifras (se rehacen con datos en cuanto cambie el libro).
                    out.append(request(id: weeklyIDs[week], title: "Resumen semanal", body: "Tu resumen semanal está listo",
                                       kind: .weeklyDigest, at: fire, calendar: calendar))
                }
            }
        }

        if settings.subscriptions {
            let horizon = now.addingTimeInterval(30 * 86_400)
            let subs = activeSubscriptions(in: state, now: now, calendar: calendar)
                .filter { $0.nextDate > now && $0.nextDate <= horizon && !Ledger(state: state).isMuted(merchant: $0.merchant) }
            var index = 0
            for sub in subs where index < subscriptionLimit {
                let dayBefore = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: sub.nextDate))
                guard let dayBefore, let fire = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: dayBefore),
                      fire > now else { continue }
                out.append(request(id: subscriptionIDs[index],
                                   title: "Mañana se cobra \(sub.merchant): \(formatEUR(sub.amountCents))",
                                   body: "En \(sub.bank.displayName)", kind: .subscriptionUpcoming, at: fire, calendar: calendar))
                index += 1
            }
        }
        return out
    }

    /// Una reprogramación detrás de otra; si llegan varias mientras una corre, solo se aplica la última.
    private actor ScheduleQueue {
        static let shared = ScheduleQueue()
        private var running = false
        private var next: (state: LedgerState, now: Date, calendar: Calendar)?

        func run(state: LedgerState, now: Date, calendar: Calendar) async {
            next = (state, now, calendar)
            guard !running else { return }
            running = true
            while let job = next {
                next = nil
                await AlertScheduler.apply(job.state, now: job.now, calendar: job.calendar)
            }
            running = false
        }
    }

    /// El próximo domingo a las 20:00 (hoy si es domingo y aún no son las 20:00).
    static func nextSunday8pm(after now: Date, calendar: Calendar) -> Date? {
        calendar.nextDate(after: now, matching: DateComponents(hour: 20, minute: 0, second: 0, weekday: 1),
                          matchingPolicy: .nextTime)
    }

    private static func request(id: String, title: String, body: String, kind: InsightKind, at date: Date,
                                calendar: Calendar) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = InsightNotifier.category
        content.threadIdentifier = "insight.\(kind.rawValue)"
        content.interruptionLevel = .active
        content.userInfo = [AlertRoute.Keys.route: AlertRoute.Keys.insightRoute]
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }
}
