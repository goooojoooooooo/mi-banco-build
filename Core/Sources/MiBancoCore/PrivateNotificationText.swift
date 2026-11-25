import Foundation

// Avisos con el ojo cerrado (decisión del dueño: «Sí, ocultarlos»): si el modo privado está activado cuando la app
// compone un aviso, su texto plegado (pantalla de bloqueo, centro de avisos, alerta de la Live Activity) no lleva ningún
// importe ni saldo. Dice lo mínimo: qué ha pasado y dónde. Con el ojo abierto, el texto de siempre, sin cambiar una letra.
// Sin puntos de máscara dentro del texto del sistema: se quita la cifra y la frase que solo la llevaba a ella.

/// El aviso de un movimiento. Ojo abierto: `alertText` tal cual. Ojo cerrado: «Pago en Mercadona» / «Ingreso de
/// Nómina» (o «Pago» / «Ingreso» sin comercio) y, de cuerpo, solo el banco («Revolut»).
public func alertText(for m: Movement, balance: Int?, estimated: Bool, hidden: Bool) -> (title: String, body: String) {
    guard hidden else { return alertText(for: m, balance: balance, estimated: estimated) }
    let title: String
    switch m.kind {
    case .payment: title = m.merchant.map { "Pago en \($0)" } ?? "Pago"
    case .income: title = m.merchant.map { "Ingreso de \($0)" } ?? "Ingreso"
    }
    return (title, m.bank.displayName)
}

/// El aviso de una idea (`immediateAlerts`). Ojo abierto: su título y su detalle de siempre. Ojo cerrado: la misma idea
/// sin cifras (el detalle que solo daba la cifra desaparece).
public func notificationText(for insight: Insight, hidden: Bool) -> (title: String, body: String) {
    guard hidden else { return (insight.title, insight.detail ?? "") }
    let merchantIn = insight.merchant.map { " en \($0)" } ?? ""
    switch insight.kind {
    case .lowBalance:
        return (insight.bank.map { "Saldo bajo en \($0.displayName)" } ?? "Saldo bajo", "")
    case .largePayment:
        return ("Pago grande\(merchantIn)", "")
    case .unusualPayment:
        return ("Pago poco habitual\(merchantIn)", "")
    case .salary:
        return ("Has recibido tu nómina", "")
    case .largeIncome:
        return ("Ingreso grande\(insight.merchant.map { " de \($0)" } ?? "")", "")
    case .duplicateCharge:
        return ("Posible cobro duplicado\(merchantIn)", insight.detail.flatMap { $0.containsDigit ? nil : $0 } ?? "")
    case .subscriptionPriceChange:
        let up = insight.title.contains(" ha subido")
        return ("\(insight.merchant ?? "Una suscripción") ha \(up ? "subido" : "bajado") de precio", "")
    case .subscriptionUpcoming:
        // «Netflix se cobra mañana: 13,99 €» → «Netflix se cobra mañana».
        return (insight.title.beforeLastColon, "")
    case .spendingPace:
        let below = insight.title.contains(" por debajo ")
        return ("Vas por \(below ? "debajo" : "encima") del mes pasado", "")
    case .weeklyDigest:
        return weeklyDigestNeutralText
    case .budgetWarning:
        // «Llevas el 85 % de tu presupuesto del mes» → «Cerca del límite de tu presupuesto del mes».
        return ("Cerca del límite de tu presupuesto\(insight.title.after("de tu presupuesto"))", "")
    case .budgetExceeded:
        return (insight.title, "")
    }
}

/// El resumen semanal sin cifras (el mismo texto que ya llevan los domingos aún sin datos).
public let weeklyDigestNeutralText = (title: "Resumen semanal", body: "Tu resumen semanal está listo")

/// El recordatorio del día antes de cobrarse una suscripción. Ojo cerrado: sin el importe.
public func subscriptionReminderText(merchant: String, amountCents: Int, bank: BankID, hidden: Bool) -> (title: String, body: String) {
    let title = hidden ? "Mañana se cobra \(merchant)" : "Mañana se cobra \(merchant): \(formatEUR(amountCents))"
    return (title, "En \(bank.displayName)")
}

/// El resumen semanal programado: ojo abierto, sus cifras; ojo cerrado, el texto neutro.
public func weeklyDigestNotificationText(_ text: (title: String, body: String), hidden: Bool) -> (title: String, body: String) {
    hidden ? weeklyDigestNeutralText : text
}

private extension String {
    var containsDigit: Bool { contains { $0.isNumber } }

    /// Hasta los últimos «: » (sin ellos); el texto entero si no los hay.
    var beforeLastColon: String {
        guard let range = range(of: ": ", options: .backwards) else { return self }
        return String(self[..<range.lowerBound])
    }

    /// Lo que va detrás de `marker` (con su espacio delante); vacío si no está.
    func after(_ marker: String) -> String {
        guard let range = range(of: marker) else { return "" }
        return String(self[range.upperBound...])
    }
}
