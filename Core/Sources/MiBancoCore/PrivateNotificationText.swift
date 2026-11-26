import Foundation

// Avisos con el ojo cerrado (decisión del dueño: «Sí, ocultarlos»): si el modo privado está activado cuando la app
// compone un aviso, su texto plegado (pantalla de bloqueo, centro de avisos, alerta de la Live Activity) no lleva ningún
// importe ni saldo. Dice lo mínimo: qué ha pasado y dónde. Con el ojo abierto, el texto de siempre, sin cambiar una letra.
// Sin puntos de máscara dentro del texto del sistema: se quita la cifra y la frase que solo la llevaba a ella.

/// El aviso de un movimiento. Ojo abierto: `alertText` tal cual. Ojo cerrado: «Pago en Mercadona» / «Ingreso de
/// Nómina» (o «Pago» / «Ingreso» sin comercio) y, de cuerpo, solo el banco («Revolut»). Si el comercio lleva cifras (un
/// teléfono, una referencia), sale sin él.
public func alertText(for m: Movement, balance: Int?, estimated: Bool, hidden: Bool) -> (title: String, body: String) {
    guard hidden else { return alertText(for: m, balance: balance, estimated: estimated) }
    let neutral = m.kind == .payment ? "Pago" : "Ingreso"
    let title: String
    switch m.kind {
    case .payment: title = m.merchant.map { "Pago en \($0)" } ?? neutral
    case .income: title = m.merchant.map { "Ingreso de \($0)" } ?? neutral
    }
    return withoutDigits((title, m.bank.displayName), else: (neutral, m.bank.displayName))
}

/// El aviso de una idea (`immediateAlerts`). Ojo abierto: su título y su detalle de siempre. Ojo cerrado: la misma idea
/// sin cifras, compuesta desde sus campos (comercio, banco, `facts`), nunca analizando el título; el detalle que solo
/// daba la cifra desaparece. Última red: si aun así queda un dígito (un comercio con cifras), sale el texto neutro del
/// tipo, sin el comercio.
public func notificationText(for insight: Insight, hidden: Bool) -> (title: String, body: String) {
    guard hidden else { return (insight.title, insight.detail ?? "") }
    return withoutDigits(closedText(for: insight), else: neutralText(for: insight))
}

/// La idea sin cifras, con su comercio.
private func closedText(for insight: Insight) -> (title: String, body: String) {
    let merchantIn = insight.merchant.map { " en \($0)" } ?? ""
    let facts = insight.facts
    switch insight.kind {
    case .largePayment:
        return ("Pago grande\(merchantIn)", "")
    case .unusualPayment:
        return ("Pago poco habitual\(merchantIn)", "")
    case .largeIncome:
        return ("Ingreso grande\(insight.merchant.map { " de \($0)" } ?? "")", "")
    case .duplicateCharge:
        return ("Posible cobro duplicado\(merchantIn)", duplicateChargeDetail)
    case .subscriptionPriceChange:
        guard let up = facts.up, let merchant = insight.merchant else { return neutralText(for: insight) }
        return ("\(merchant) ha \(up ? "subido" : "bajado") de precio", "")
    case .subscriptionUpcoming:
        guard let when = facts.when, let merchant = insight.merchant else { return neutralText(for: insight) }
        return ("\(merchant) se cobra \(when)", "")
    case .lowBalance, .salary, .spendingPace, .weeklyDigest, .budgetWarning, .budgetExceeded:
        return neutralText(for: insight)
    }
}

/// El texto neutro de cada tipo: sin comercio y sin cifras (solo el banco y los campos sin importe de `facts`).
public func neutralText(for insight: Insight) -> (title: String, body: String) {
    let facts = insight.facts
    let scope = facts.budgetScope.map { " \($0)" } ?? ""
    switch insight.kind {
    case .lowBalance:
        return (insight.bank.map { "Saldo bajo en \($0.displayName)" } ?? "Saldo bajo", "")
    case .largePayment:
        return ("Pago grande", "")
    case .unusualPayment:
        return ("Pago poco habitual", "")
    case .salary:
        return ("Has recibido tu nómina", "")
    case .largeIncome:
        return ("Ingreso grande", "")
    case .duplicateCharge:
        return ("Posible cobro duplicado", duplicateChargeDetail)
    case .subscriptionPriceChange:
        return (facts.up.map { "Una suscripción ha \($0 ? "subido" : "bajado") de precio" }
                    ?? "Una suscripción ha cambiado de precio", "")
    case .subscriptionUpcoming:
        return (facts.when.map { "Una suscripción se cobra \($0)" } ?? "Una suscripción se cobra pronto", "")
    case .spendingPace:
        return (facts.up.map { "Vas por \($0 ? "encima" : "debajo") del mes pasado" } ?? "Tu ritmo de gasto ha cambiado", "")
    case .weeklyDigest:
        return weeklyDigestNeutralText
    case .budgetWarning:
        return ("Cerca del límite de tu presupuesto\(scope)", "")
    case .budgetExceeded:
        return ("Te has pasado del presupuesto\(scope)", "")
    }
}

/// La última red: `text` si no lleva ningún dígito; si no, `fallback` (y, si también lo llevara, un aviso genérico).
private func withoutDigits(
    _ text: (title: String, body: String), else fallback: (title: String, body: String)
) -> (title: String, body: String) {
    if !text.title.containsDigit, !text.body.containsDigit { return text }
    if !fallback.title.containsDigit, !fallback.body.containsDigit { return fallback }
    return ("Nuevo aviso", "")
}

/// El resumen semanal sin cifras (el mismo texto que ya llevan los domingos aún sin datos).
public let weeklyDigestNeutralText = (title: "Resumen semanal", body: "Tu resumen semanal está listo")

/// El recordatorio del día antes de cobrarse una suscripción. Ojo cerrado: sin el importe.
public func subscriptionReminderText(merchant: String, amountCents: Int, bank: BankID, hidden: Bool) -> (title: String, body: String) {
    let body = "En \(bank.displayName)"
    guard hidden else { return ("Mañana se cobra \(merchant): \(formatEUR(amountCents))", body) }
    return withoutDigits(("Mañana se cobra \(merchant)", body), else: ("Mañana se cobra una suscripción", body))
}

/// El resumen semanal programado: ojo abierto, sus cifras; ojo cerrado, el texto neutro.
public func weeklyDigestNotificationText(_ text: (title: String, body: String), hidden: Bool) -> (title: String, body: String) {
    hidden ? weeklyDigestNeutralText : text
}

private extension String {
    var containsDigit: Bool { contains { $0.isNumber } }
}
