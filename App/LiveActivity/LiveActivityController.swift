import ActivityKit
import Foundation
import MiBancoCore

/// Una sola Live Activity viva, solo local (sin push). Cualquier fallo se ignora: el aviso local ya salió.
enum LiveActivityController {
    private typealias Live = Activity<MovementActivityAttributes>
    private static let staleAfter: TimeInterval = 15 * 60

    /// Las que siguen en pantalla. Una actividad caducada (.stale) sigue siendo válida: actualizarla la reactiva.
    private static var live: [Live] {
        Live.activities.filter { $0.activityState == .active || $0.activityState == .stale }
    }

    /// `true` si tras la llamada hay una Live Activity mostrándose (actualizada o recién creada).
    @discardableResult
    static func show(movement: Movement, balance: Int?, estimated: Bool, total: Int?) async -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }

        // La alerta de la Live Activity usa el mismo texto que el aviso: con el ojo cerrado, sin cifras.
        let text = alertText(for: movement, balance: balance, estimated: estimated, hidden: AlertPoster.eyeClosed)
        let state = MovementActivityAttributes.ContentState(
            bank: movement.bank.rawValue, balanceCents: balance, estimated: estimated,
            lastAmountCents: movement.amountCents, merchant: movement.merchant, kind: movement.kind.rawValue,
            totalCents: total, title: text.title, logoDomain: movement.logoDomain,
            hidden: Self.eyeClosed)
        let content = ActivityContent(state: state, staleDate: Date.now.addingTimeInterval(staleAfter))

        let current = live
        if let first = current.first {
            let alert = AlertConfiguration(
                title: LocalizedStringResource(stringLiteral: text.title),
                body: LocalizedStringResource(stringLiteral: text.body),
                sound: .default)
            await first.update(content, alertConfiguration: alert)
            for extra in current.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
            // N-4: si el ojo cambió mientras se actualizaba, queda con el de ahora.
            await syncEye()
            return true
        } else {
            let created = (try? Live.request(attributes: MovementActivityAttributes(), content: content, pushType: nil)) != nil
            // N-4: si el ojo se cerró mientras se creaba (y el aviso del cambio ya pasó por las actividades), se corrige.
            if created { await syncEye() }
            return created
        }
    }

    /// Corrección del saldo sin movimiento nuevo (p. ej. un aviso duplicado que trae el saldo del banco):
    /// actualiza en silencio, sin alerta ni sonido, y sin alargar la caducidad.
    static func updateBalance(bank: BankID, balance: Int?, estimated: Bool, total: Int?) async {
        for activity in live {
            var state = activity.content.state
            if state.bank == bank.rawValue {
                state.balanceCents = balance
                state.estimated = estimated
            }
            state.totalCents = total
            state.hidden = Self.eyeClosed
            guard state != activity.content.state else { continue }
            await activity.update(ActivityContent(state: state, staleDate: activity.content.staleDate))
        }
    }

    /// Cierra la actividad de "Probar aviso" si sigue mostrando la prueba (no toca una real que llegara después).
    static func endTest(merchant: String, amountCents: Int) async {
        for activity in Live.activities {
            let state = activity.content.state
            if state.merchant == merchant && state.lastAmountCents == amountCents {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// I-2: el ojo de la app ahora mismo (el mismo que usan los avisos).
    private static var eyeClosed: Bool { AlertPoster.eyeClosed }

    /// I-2: el ojo ha cambiado: la Live Activity que esté en pantalla pasa a máscaras (o vuelve a cifras) en silencio,
    /// sin alerta ni sonido y sin alargar su caducidad. N-4: siempre con el ojo de AHORA (leído aquí, no el del momento
    /// en que se pidió): dos cambios rápidos, o un `show` a medias, acaban con el ojo vigente.
    static func syncEye() async {
        for activity in live {
            var state = activity.content.state
            guard let hidden = SharedPrivacy.reconciled(current: state.hidden, eyeNow: eyeClosed) else { continue }
            state.hidden = hidden
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
