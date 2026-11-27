import ActivityKit
import Foundation
import MiBancoCore

/// Una sola Live Activity viva, solo local (sin push). Cualquier fallo se ignora: el aviso local ya salió.
enum LiveActivityController {
    private typealias Live = Activity<MovementActivityAttributes>
    private static let staleAfter: TimeInterval = 15 * 60

    /// Recuerda en memoria la última actividad mostrada por esta instancia (M-14) para que `endTest`
    /// con el ojo cerrado solo cierre la actividad de prueba y nunca una real del mismo comercio.
    private final class LastShownTracker: @unchecked Sendable {
        private let lock = NSLock()
        private var last: (activityID: String, merchant: String?, amountCents: Int)?

        func record(activityID: String, merchant: String?, amountCents: Int) {
            lock.lock()
            defer { lock.unlock() }
            last = (activityID, merchant, amountCents)
        }

        func matches(activityID: String, merchant: String, amountCents: Int) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard let last else { return false }
            return last.activityID == activityID && last.merchant == merchant && last.amountCents == amountCents
        }
    }

    private static let lastShown = LastShownTracker()

    /// Las que siguen en pantalla. Una actividad caducada (.stale) sigue siendo válida: actualizarla la reactiva.
    private static var live: [Live] {
        Live.activities.filter { $0.activityState == .active || $0.activityState == .stale }
    }

    /// `true` si tras la llamada hay una Live Activity mostrándose (actualizada o recién creada).
    @discardableResult
    static func show(movement: Movement, balance: Int?, estimated: Bool, total: Int?) async -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }

        // La alerta de la Live Activity usa el mismo texto que el aviso: con el ojo cerrado, sin cifras. El texto, el
        // estado y la alerta salen de UNA lectura del ojo.
        let staleDate = Date.now.addingTimeInterval(staleAfter)
        typealias Composed = (text: (title: String, body: String), content: ActivityContent<MovementActivityAttributes.ContentState>)
        func compose(_ hidden: Bool) -> Composed {
            let text = alertText(for: movement, balance: balance, estimated: estimated, hidden: hidden)
            let money = LiveActivityMoneyFields.composed(
                balance: balance, amountCents: movement.amountCents, total: total, hidden: hidden)
            let state = MovementActivityAttributes.ContentState(
                bank: movement.bank.rawValue, balanceCents: money.balanceCents, estimated: estimated,
                lastAmountCents: money.lastAmountCents, merchant: movement.merchant, kind: movement.kind.rawValue,
                totalCents: money.totalCents, title: text.title, logoDomain: movement.logoDomain,
                hidden: hidden, hasBalance: money.hasBalance)
            return (text, ActivityContent(state: state, staleDate: staleDate))
        }
        var hidden = Self.eyeClosed
        var (text, content) = compose(hidden)
        // M-2: justo antes de mandarla se vuelve a leer el ojo; si cambió mientras se componía, se recompone.
        func refreshed() {
            let now = Self.eyeClosed
            guard now != hidden else { return }
            hidden = now
            (text, content) = compose(now)
        }

        let current = live
        if let first = current.first {
            refreshed()
            let alert = AlertConfiguration(
                title: LocalizedStringResource(stringLiteral: text.title),
                body: LocalizedStringResource(stringLiteral: text.body),
                sound: .default)
            await first.update(content, alertConfiguration: alert)
            lastShown.record(activityID: first.id, merchant: movement.merchant, amountCents: movement.amountCents)
            for extra in current.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
            // N-4: si el ojo cambió mientras se actualizaba, queda con el de ahora.
            await syncEye()
            return true
        } else {
            refreshed()
            guard let created = try? Live.request(attributes: MovementActivityAttributes(), content: content, pushType: nil) else {
                return false
            }
            lastShown.record(activityID: created.id, merchant: movement.merchant, amountCents: movement.amountCents)
            // N-4: si el ojo se cerró mientras se creaba (y el aviso del cambio ya pasó por las actividades), se corrige.
            await syncEye()
            return true
        }
    }

    /// Corrección del saldo sin movimiento nuevo (p. ej. un aviso duplicado que trae el saldo del banco):
    /// actualiza en silencio, sin alerta ni sonido, y sin alargar la caducidad. Con el ojo cerrado, nunca guarda cifras.
    static func updateBalance(bank: BankID, balance: Int?, estimated: Bool, total: Int?) async {
        let hidden = Self.eyeClosed
        for activity in live {
            var state = activity.content.state
            if hidden {
                if state.bank == bank.rawValue {
                    state.estimated = estimated
                }
                let redacted = LiveActivityMoneyFields.redactedForClosedEye(
                    balanceCents: state.bank == bank.rawValue ? balance : state.balanceCents,
                    hasBalance: state.bank == bank.rawValue ? (balance != nil) : state.hasBalance
                )
                state.balanceCents = redacted.balanceCents
                state.lastAmountCents = redacted.lastAmountCents
                state.totalCents = redacted.totalCents
                state.hasBalance = redacted.hasBalance
                state.hidden = true
                if let title = title(of: state, hidden: true) { state.title = title }
            } else {
                if state.bank == bank.rawValue {
                    state.balanceCents = balance
                    state.estimated = estimated
                    state.hasBalance = nil
                }
                state.totalCents = total
                state.hidden = false
            }
            guard state != activity.content.state else { continue }
            await activity.update(ActivityContent(state: state, staleDate: activity.content.staleDate))
        }
    }

    /// Cierra la actividad de "Probar aviso" si sigue mostrando la prueba (no toca una real que llegara después).
    static func endTest(merchant: String, amountCents: Int) async {
        for activity in Live.activities {
            let state = activity.content.state
            let matchesOpen = state.merchant == merchant && state.lastAmountCents == amountCents
            let matchesClosedTest = state.merchant == merchant
                && state.lastAmountCents == nil
                && state.hidden == true
                && lastShown.matches(activityID: activity.id, merchant: merchant, amountCents: amountCents)
            if matchesOpen || matchesClosedTest {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// I-2: el ojo de la app ahora mismo (el mismo que usan los avisos). Interno solo para la sonda DEBUG.
    static var eyeClosed: Bool { AlertPoster.eyeClosed }

    /// M-2: el título del estado con el ojo `hidden` (el mismo texto que el aviso), recompuesto desde el propio estado.
    /// nil si el estado no se puede leer como movimiento o si con ojo abierto ya no quedan cifras en el estado.
    private static func title(of state: MovementActivityAttributes.ContentState, hidden: Bool) -> String? {
        guard let bank = BankID(rawValue: state.bank), let kind = MovementKind(rawValue: state.kind) else { return nil }
        if !hidden, state.lastAmountCents == nil { return nil }
        let amount = state.lastAmountCents ?? (kind == .payment ? -1 : 1)
        let movement = Movement(bank: bank, amountCents: amount, merchant: state.merchant, kind: kind,
                                source: .notification, date: .now)
        return alertText(for: movement, balance: state.balanceCents, estimated: state.estimated, hidden: hidden).title
    }

    /// I-2: el ojo ha cambiado: la Live Activity que esté en pantalla pasa a máscaras (o vuelve a cifras) en silencio,
    /// sin alerta ni sonido y sin alargar su caducidad. Al cerrar el ojo borra también las cifras del estado (SEC-06).
    /// N-4: siempre con el ojo de AHORA (leído aquí, no el del momento en que se pidió).
    static func syncEye() async {
        for activity in live {
            var state = activity.content.state
            let eyeNow = eyeClosed
            let needsScrub = eyeNow && (state.balanceCents != nil || state.lastAmountCents != nil || state.totalCents != nil)
            let reconciled = SharedPrivacy.reconciled(current: state.hidden, eyeNow: eyeNow)
            guard reconciled != nil || needsScrub else { continue }
            let hidden = reconciled ?? eyeNow
            state.hidden = hidden
            if hidden {
                let redacted = LiveActivityMoneyFields.redactedForClosedEye(
                    balanceCents: state.balanceCents, hasBalance: state.hasBalance)
                state.balanceCents = redacted.balanceCents
                state.lastAmountCents = redacted.lastAmountCents
                state.totalCents = redacted.totalCents
                state.hasBalance = redacted.hasBalance
            }
            // M-2: el título sigue al ojo (al abrirlo vuelve «Has pagado…» si hay cifra; al cerrarlo, «Pago en…»).
            if let title = title(of: state, hidden: hidden) { state.title = title }
            await activity.update(ActivityContent(state: state, staleDate: activity.content.staleDate))
        }
    }

    /// Cierra las actividades caducadas: las que el sistema ya marcó .stale y las .active con staleDate pasada.
    static func endStale() async {
        let now = Date.now
        for activity in Live.activities {
            let expired: Bool
            switch activity.activityState {
            case .stale: expired = true
            case .active: expired = activity.content.staleDate.map { $0 < now } ?? false
            default: expired = false
            }
            if expired { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
