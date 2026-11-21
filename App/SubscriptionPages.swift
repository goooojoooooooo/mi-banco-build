import Foundation
import MiBancoCore

extension LedgerSnapshot {
    /// Una suscripción con sus textos ya redactados (el cuerpo de la vista no formatea nada).
    struct SubscriptionRow: Equatable, Sendable, Identifiable {
        /// "banco|clave": el id que guarda `dismissedSubscriptions`.
        let id: String
        let merchant: String
        let bank: BankID
        let amountCents: Int
        /// "Próximo cobro: hoy" / "mañana" / "domingo, 22 nov".
        let nextCharge: String
        /// "Sube 1,00 €" / "Baja 1,00 €"; nil si el precio no ha cambiado.
        let priceChange: String?
        let priceWentUp: Bool
        /// Dominio del directorio de comercios (su logo va en la app).
        let logoDomain: String?
    }

    /// Lo que añade la pantalla de suscripciones al snapshot.
    struct SubscriptionExtras: Sendable {
        var subscriptions: [SubscriptionRow] = []
        var hidden: [SubscriptionRow] = []
        var monthlyCents = 0
        var yearlyCents = 0
        /// "2 · 24,98 € al mes" (la fila de Gasto).
        var summary = "Ninguna todavía"
    }

    /// Las activas y las ocultas llegan ya detectadas (una sola vez por reconstrucción).
    static func subscriptionExtras(state: LedgerState, now: Date, calendar: Calendar,
                                   subscriptions: [Subscription], hidden: [Subscription]) -> SubscriptionExtras {
        var out = SubscriptionExtras()
        out.subscriptions = subscriptions.map { subscriptionRow($0, now: now, calendar: calendar) }
        let totals = subscriptionTotals(subscriptions)
        out.monthlyCents = totals.monthlyCents
        out.yearlyCents = totals.yearlyCents
        out.hidden = hidden.map { subscriptionRow($0, now: now, calendar: calendar) }
        if !subscriptions.isEmpty {
            out.summary = "\(subscriptions.count) · \(formatEUR(totals.monthlyCents)) al mes"
        }
        return out
    }

    static func subscriptionRow(_ s: Subscription, now: Date, calendar: Calendar) -> SubscriptionRow {
        var change: String?
        var up = false
        if let previous = s.previousAmountCents, previous != s.amountCents {
            up = s.amountCents > previous
            change = "\(up ? "Sube" : "Baja") \(formatEUR(abs(s.amountCents - previous)))"
        }
        return SubscriptionRow(
            id: "\(s.bank.rawValue)|\(s.id)", merchant: s.merchant, bank: s.bank, amountCents: s.amountCents,
            nextCharge: nextChargeText(s.nextDate, now: now, calendar: calendar), priceChange: change, priceWentUp: up,
            logoDomain: MiBancoCore.logoDomain(merchant: s.merchant, isShop: true, isIncome: false))
    }

    /// "Próximo cobro: hoy", "…: mañana", "…: domingo, 22 nov". Si la fecha ya pasó (el cobro se retrasa): "Cobro esperado el 18 nov".
    static func nextChargeText(_ next: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: next)).day ?? 0
        let month = next.formatted(Date.FormatStyle(locale: spanish).month(.abbreviated)).replacing(".", with: "")
        let dayNumber = calendar.component(.day, from: next)
        if days < 0 { return "Cobro esperado el \(dayNumber) \(month)" }
        if days == 0 { return "Próximo cobro: hoy" }
        if days == 1 { return "Próximo cobro: mañana" }
        let weekday = next.formatted(Date.FormatStyle(locale: spanish).weekday(.wide)).lowercased()
        return "Próximo cobro: \(weekday), \(dayNumber) \(month)"
    }
}
