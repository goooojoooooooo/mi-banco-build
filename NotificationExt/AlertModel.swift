import Observation
import UserNotifications
import MiBancoCore

/// Lee todo de `userInfo` (ver AlertPoster); no toca el almacén.
@MainActor @Observable
final class AlertModel {
    var title = ""
    var body = ""
    var bank: BankID?
    /// Firmado: negativo = pago.
    var amountCents = 0
    var merchant: String?
    /// Saldo de este banco antes y después del movimiento (nil = sin saldo configurado).
    var balanceBefore: Int?
    var balanceAfter: Int?
    /// El saldo es una estimación: "Te quedan unos…" y la etiqueta "estimado".
    var estimated = false
    /// Este mes en ese comercio (con este pago), si se sabe.
    var monthCount: Int?
    var monthCents: Int?
    /// Gastado hoy, si se sabe.
    var todaySpent: Int?
    /// Dominio del directorio si conoce al comercio: su logo va dentro de la extensión.
    var logoDomain: String?
    /// Sube en cada aviso recibido para relanzar el montaje.
    var revision = 0

    var isIncome: Bool { amountCents > 0 }

    func receive(_ content: UNNotificationContent) {
        title = content.title
        body = content.body
        let info = content.userInfo
        bank = (info["bank"] as? String).flatMap(BankID.init(rawValue:))
        amountCents = (info["amountCents"] as? Int) ?? 0
        merchant = info["merchant"] as? String
        let balances = (info["balances"] as? [String: Int]) ?? [:]
        balanceAfter = bank.flatMap { balances[$0.rawValue] }
        balanceBefore = (info["previousBalance"] as? Int) ?? balanceAfter
        // Avisos anteriores a Titanio no traen "estimated": se deduce del texto ("Te quedan unos…").
        estimated = (info["estimated"] as? Bool) ?? content.body.contains("unos ")
        monthCount = info["monthCount"] as? Int
        monthCents = info["monthCents"] as? Int
        todaySpent = info["todaySpent"] as? Int
        // `isShop` viaja en el aviso (AlertPoster); si falta (avisos antiguos) se asume que no es una tienda,
        // y los alias ambiguos no casan: mejor sin logo que con la marca equivocada.
        let isShop = (info["isShop"] as? Bool) ?? false
        logoDomain = MiBancoCore.logoDomain(merchant: merchant, isShop: isShop, isIncome: amountCents > 0)
        revision += 1
    }
}
