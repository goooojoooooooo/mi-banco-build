import Foundation

/// Descripción mínima de un aviso ya entregado en el Centro de Notificaciones para decidir si se retira al cerrar el ojo.
public struct DeliveredAlertDescriptor: Equatable, Sendable {
    public let identifier: String
    public let categoryIdentifier: String

    public init(identifier: String, categoryIdentifier: String) {
        self.identifier = identifier
        self.categoryIdentifier = categoryIdentifier
    }
}

/// Identificadores compartidos de categorías de avisos que pueden llevar importes o saldos (M-5).
/// Única fuente de verdad entre Core, `AlertPoster` y `InsightNotifier`.
public enum AlertCategoryID {
    public static let movement = "MOVEMENT"
    public static let insight = "INSIGHT"
}

/// Categorías de avisos locales que pueden llevar importes o saldos (`MOVEMENT` e `INSIGHT`).
/// `BRIEFING`, `BANK_CONSENT` y los avisos sin leer nunca llevan cifras y se conservan.
public let sensitiveAlertCategories: Set<String> = [AlertCategoryID.movement, AlertCategoryID.insight]

/// Identificadores de los avisos entregados que deben quitarse del Centro de Notificaciones al activar el modo privado.
public func deliveredAlertIdentifiersToRemoveForPrivacy(
    _ delivered: [DeliveredAlertDescriptor],
    sensitiveCategories: Set<String> = sensitiveAlertCategories
) -> [String] {
    delivered
        .filter { sensitiveCategories.contains($0.categoryIdentifier) }
        .map(\.identifier)
}

/// Construye el diccionario `userInfo` de un aviso de movimiento.
/// - Con `hidden == false` (ojo abierto): incluye los campos de siempre sin cambiar ni un byte.
/// - Con `hidden == true` (ojo cerrado): omite `amountCents`, `balances`, `previousBalance`, `monthCents` y `todaySpent`,
///   enviando solo indicadores booleanos de presencia/signo para que la vista ampliada pinte las máscaras correctamente.
public func movementNotificationUserInfo(
    movement m: Movement,
    balances: [String: Int],
    previousBalance: Int?,
    estimated: Bool,
    merchantMonth: MerchantHistory?,
    todaySpentCents: Int?,
    hidden: Bool,
    routeKey: String = "route",
    routeValue: String = "movement",
    movementIDKey: String = "movementID"
) -> [String: Any] {
    var info: [String: Any] = [
        "bank": m.bank.rawValue,
        "isShop": m.isShop,
        routeKey: routeValue,
        movementIDKey: m.id.uuidString,
        "estimated": estimated,
        SharedPrivacy.key: hidden,
    ]
    if let merchant = m.merchant { info["merchant"] = merchant }
    if let merchantMonth, merchantMonth.countThisMonth > 0 {
        info["monthCount"] = merchantMonth.countThisMonth
        if !hidden { info["monthCents"] = merchantMonth.totalThisMonthCents }
    }
    if hidden {
        info["isIncome"] = m.amountCents > 0
        info["isNegative"] = m.amountCents < 0
        info["hasBalance"] = balances[m.bank.rawValue] != nil
        info["hasTodaySpent"] = (todaySpentCents ?? 0) > 0
    } else {
        info["amountCents"] = m.amountCents
        info["balances"] = balances
        if let previousBalance { info["previousBalance"] = previousBalance }
        if let todaySpentCents { info["todaySpent"] = todaySpentCents }
    }
    return info
}

/// Campos monetarios de `MovementActivityAttributes.ContentState` según el ojo:
/// con el ojo cerrado no viaja ninguna cifra (`nil`), solo si existe saldo (`hasBalance`).
public struct LiveActivityMoneyFields: Equatable, Sendable {
    public var balanceCents: Int?
    public var lastAmountCents: Int?
    public var totalCents: Int?
    public var hasBalance: Bool?

    public init(balanceCents: Int?, lastAmountCents: Int?, totalCents: Int?, hasBalance: Bool?) {
        self.balanceCents = balanceCents
        self.lastAmountCents = lastAmountCents
        self.totalCents = totalCents
        self.hasBalance = hasBalance
    }

    public static func composed(balance: Int?, amountCents: Int, total: Int?, hidden: Bool) -> LiveActivityMoneyFields {
        if hidden {
            return LiveActivityMoneyFields(
                balanceCents: nil,
                lastAmountCents: nil,
                totalCents: nil,
                hasBalance: balance != nil
            )
        }
        return LiveActivityMoneyFields(
            balanceCents: balance,
            lastAmountCents: amountCents,
            totalCents: total,
            hasBalance: nil
        )
    }

    public static func redactedForClosedEye(balanceCents: Int?, hasBalance: Bool?) -> LiveActivityMoneyFields {
        LiveActivityMoneyFields(
            balanceCents: nil,
            lastAmountCents: nil,
            totalCents: nil,
            hasBalance: (balanceCents != nil) || (hasBalance ?? false)
        )
    }
}
