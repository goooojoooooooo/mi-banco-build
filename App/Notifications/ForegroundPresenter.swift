import UserNotifications

/// Sin delegado, iOS no muestra avisos con la app en primer plano. También recibe el toque en un aviso
/// y se lo pasa a `AlertRouter` (Inicio con la hoja del movimiento, o la pestaña Avisos).
final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    /// El centro guarda su delegado con referencia débil.
    static let shared = ForegroundPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        if notification.request.content.categoryIdentifier == NyxNotifier.category {
            return []
        }
        return [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let route = AlertRoute(userInfo: response.notification.request.content.userInfo)
        await MainActor.run { AlertRouter.shared.open(route) }
    }
}
