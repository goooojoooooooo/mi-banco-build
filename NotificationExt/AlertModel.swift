import Observation
import UserNotifications
import MiBancoCore

/// Lee todo de `userInfo` (ver AlertPoster); no toca el almacén.
@MainActor @Observable
final class AlertModel {
    var title = ""
    var body = ""
    var bank: BankID?
    /// Firmado: negativo = pago. Con ojo cerrado en `userInfo` no llega cifra (se queda en 0 y mandan `isIncome`/`isNegative`).
    var amountCents = 0
    var isIncome = false
    var isNegative = false
    var merchant: String?
    /// Saldo de este banco antes y después del movimiento (nil = sin saldo configurado u omitido con el ojo cerrado).
    var balanceBefore: Int?
    var balanceAfter: Int?
    /// true si hay saldo que mostrar (o enmascarar cuando el ojo estaba cerrado y `balances` no viajó).
    var hasBalance = false
    /// El saldo es una estimación: "Te quedan unos…" y la etiqueta "estimado".
    var estimated = false
    /// Este mes en ese comercio (con este pago), si se sabe.
    var monthCount: Int?
    var monthCents: Int?
    /// Gastado hoy, si se sabe.
    var todaySpent: Int?
    /// true si hoy hubo gasto (aunque `todaySpent` se omitiera por ojo cerrado).
    var hasTodaySpent = false
    /// Dominio del directorio si conoce al comercio: su logo va dentro de la extensión.
    var logoDomain: String?
    /// Sube en cada aviso recibido para relanzar el montaje.
    var revision = 0
    /// I-2: el ojo de la app estaba cerrado (la carga del aviso lo dice O la suite compartida lo dice): se dibujan
    /// máscaras, nunca cifras.
    var hidden = false

    func receive(_ content: UNNotificationContent) {
        title = content.title
        body = content.body
        let info = content.userInfo
        bank = (info["bank"] as? String).flatMap(BankID.init(rawValue:))
        let rawAmount = info["amountCents"] as? Int
        amountCents = rawAmount ?? 0
        isIncome = (info["isIncome"] as? Bool) ?? (amountCents > 0)
        isNegative = (info["isNegative"] as? Bool) ?? (amountCents < 0)
        merchant = info["merchant"] as? String
        let balances = (info["balances"] as? [String: Int]) ?? [:]
        balanceAfter = bank.flatMap { balances[$0.rawValue] }
        balanceBefore = (info["previousBalance"] as? Int) ?? balanceAfter
        hasBalance = balanceAfter != nil || ((info["hasBalance"] as? Bool) ?? false)
        // Avisos anteriores a Titanio no traen "estimated": se deduce del texto ("Te quedan unos…").
        estimated = (info["estimated"] as? Bool) ?? content.body.contains("unos ")
        monthCount = info["monthCount"] as? Int
        monthCents = info["monthCents"] as? Int
        todaySpent = info["todaySpent"] as? Int
        hasTodaySpent = ((todaySpent ?? 0) > 0) || ((info["hasTodaySpent"] as? Bool) ?? false)
        // `isShop` viaja en el aviso (AlertPoster); si falta (avisos antiguos) se asume que no es una tienda,
        // y los alias ambiguos no casan: mejor sin logo que con la marca equivocada.
        let isShop = (info["isShop"] as? Bool) ?? false
        logoDomain = MiBancoCore.logoDomain(merchant: merchant, isShop: isShop, isIncome: isIncome)
        let masked = SharedPrivacy.masks(
            payload: info[SharedPrivacy.key],
            shared: SharedPrivacy.read(from: SharedPrivacy.suite(infoDictionary: Bundle.main.infoDictionary)))
        hidden = masked || rawAmount == nil
        revision += 1
    }
}
