import Observation
import UserNotifications
import MiBancoCore

/// Lee todo de `userInfo` (ver AlertPoster); no toca el almacén.
@MainActor @Observable
final class AlertModel {
    var title = ""
    var body = ""
    var before: [BankID: Int] = [:]
    var after: [BankID: Int] = [:]
    /// Dominio del directorio si conoce al comercio: su logo va dentro de la extensión.
    var logoDomain: String?
    /// Sube en cada aviso recibido para relanzar la animación.
    var revision = 0

    func receive(_ content: UNNotificationContent) {
        title = content.title
        body = content.body
        let info = content.userInfo
        var now: [BankID: Int] = [:]
        for (key, value) in (info["balances"] as? [String: Int]) ?? [:] {
            if let bank = BankID(rawValue: key) { now[bank] = value }
        }
        var start = now
        if let raw = info["bank"] as? String, let bank = BankID(rawValue: raw),
           let previous = info["previousBalance"] as? Int {
            start[bank] = previous
        }
        // `isShop` viaja en el aviso (AlertPoster); si falta (avisos antiguos) se asume que no es una tienda,
        // y los alias ambiguos no casan: mejor sin logo que con la marca equivocada.
        let isShop = (info["isShop"] as? Bool) ?? false
        let income = (info["amountCents"] as? Int).map { $0 > 0 } ?? false
        logoDomain = MiBancoCore.logoDomain(merchant: info["merchant"] as? String, isShop: isShop, isIncome: income)
        before = start
        after = now
        revision += 1
    }
}
