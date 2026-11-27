import Foundation
import UserNotifications
import MiBancoCore

enum AlertPoster {
    static let category = AlertCategoryID.movement

    /// Una vez al arrancar: permiso y categoría (sin acciones) para la vista expandida.
    static func setup() async {
        let center = UNUserNotificationCenter.current()
        center.delegate = ForegroundPresenter.shared
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: category, actions: [], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: InsightNotifier.category, actions: [], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: MorningBriefingNotifier.category, actions: [], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: BankReminders.category, actions: [], intentIdentifiers: [], options: []),
        ])
    }

    /// `balances`: saldo de cada banco con saldo, DESPUÉS del movimiento. `previousBalance`: saldo de este banco antes.
    /// `estimated`: el saldo de este banco es una estimación; el cuerpo dice "Te quedan unos".
    /// `merchantMonth`: compras y gasto de este mes en ese comercio (con este pago). `todaySpentCents`: gastado hoy.
    static func post(movement m: Movement, balance: Int?, estimated: Bool, balances: [String: Int], previousBalance: Int?,
                     merchantMonth: MerchantHistory? = nil, todaySpentCents: Int? = nil) async {
        // Ojo cerrado al componerlo: ni importe ni saldo en el texto plegado ni en `userInfo` (SEC-06).
        let hidden = eyeClosed
        let text = alertText(for: m, balance: balance, estimated: estimated, hidden: hidden)
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        content.sound = .default
        content.categoryIdentifier = category
        content.threadIdentifier = m.bank.rawValue
        content.interruptionLevel = .active
        content.userInfo = movementNotificationUserInfo(
            movement: m,
            balances: balances,
            previousBalance: previousBalance,
            estimated: estimated,
            merchantMonth: merchantMonth,
            todaySpentCents: todaySpentCents,
            hidden: hidden,
            routeKey: AlertRoute.Keys.route,
            routeValue: AlertRoute.Keys.movementRoute,
            movementIDKey: AlertRoute.Keys.movementID
        )
        await add(content, id: m.id.uuidString)
    }

    /// Retira del Centro de Notificaciones los avisos ya entregados que pueden llevar cifras (`MOVEMENT` e `INSIGHT`),
    /// dejando intactos los demás (`BRIEFING`, `BANK_CONSENT`, avisos sin leer).
    static func removeDeliveredSensitiveNotifications() async {
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
        let descriptors = delivered.map {
            DeliveredAlertDescriptor(
                identifier: $0.request.identifier,
                categoryIdentifier: $0.request.content.categoryIdentifier
            )
        }
        let ids = deliveredAlertIdentifiersToRemoveForPrivacy(
            descriptors,
            sensitiveCategories: [AlertPoster.category, InsightNotifier.category]
        )
        guard !ids.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    /// El ojo de la app ahora mismo (la fuente de verdad: el almacén de `AppPreferences`), para componer avisos.
    static var eyeClosed: Bool {
        // N-3: la fuente de verdad de la app (no la copia de la suite). M-4: con la misma lectura que la app.
        AppPreferences.storedPrivateMode
    }

    /// Sin importes ni texto del aviso.
    static func postUnread(bank: BankID) async {
        let content = UNMutableNotificationContent()
        content.title = "Aviso sin leer"
        content.body = "\(AppIdentity.displayName) no ha entendido un aviso de \(bank.displayName). Ábrelo para revisarlo."
        content.interruptionLevel = .active
        await add(content, id: UUID().uuidString)
    }

    // Sin permiso el aviso simplemente no sale: el movimiento ya está guardado.
    private static func add(_ content: UNNotificationContent, id: String) async {
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}
