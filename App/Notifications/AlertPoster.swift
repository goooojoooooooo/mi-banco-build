import Foundation
import UserNotifications
import MiBancoCore

enum AlertPoster {
    static let category = "MOVEMENT"

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
        let text = alertText(for: m, balance: balance, estimated: estimated)
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        content.sound = .default
        content.categoryIdentifier = category
        content.threadIdentifier = m.bank.rawValue
        content.interruptionLevel = .active
        var info: [String: Any] = ["bank": m.bank.rawValue, "amountCents": m.amountCents, "balances": balances, "isShop": m.isShop]
        if let merchant = m.merchant { info["merchant"] = merchant }
        if let previousBalance { info["previousBalance"] = previousBalance }
        // Claves añadidas en Titanio (las anteriores no cambian): la vista ampliada y el toque en el aviso.
        info[AlertRoute.Keys.route] = AlertRoute.Keys.movementRoute
        info[AlertRoute.Keys.movementID] = m.id.uuidString
        info["estimated"] = estimated
        if let merchantMonth, merchantMonth.countThisMonth > 0 {
            info["monthCount"] = merchantMonth.countThisMonth
            info["monthCents"] = merchantMonth.totalThisMonthCents
        }
        if let todaySpentCents { info["todaySpent"] = todaySpentCents }
        content.userInfo = info
        await add(content, id: m.id.uuidString)
    }

    /// Sin importes ni texto del aviso.
    static func postUnread(bank: BankID) async {
        let content = UNMutableNotificationContent()
        content.title = "Aviso sin leer"
        content.body = "Mi Banco no ha entendido un aviso de \(bank.displayName). Ábrelo para revisarlo."
        content.interruptionLevel = .active
        await add(content, id: UUID().uuidString)
    }

    // Sin permiso el aviso simplemente no sale: el movimiento ya está guardado.
    private static func add(_ content: UNNotificationContent, id: String) async {
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}
