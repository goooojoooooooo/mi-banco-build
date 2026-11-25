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

        let text = alertText(for: movement, balance: balance, estimated: estimated)
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
            return true
        } else {
            return (try? Live.request(attributes: MovementActivityAttributes(), content: content, pushType: nil)) != nil
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

    /// I-2: el ojo de la app, tal cual lo copia en la suite compartida (`SharedPrivacy`). Sin suite, abierto.
    private static var eyeClosed: Bool {
        SharedPrivacy.read(from: SharedPrivacy.suite(infoDictionary: Bundle.main.infoDictionary)) ?? false
    }

    /// I-2: el ojo ha cambiado: la Live Activity que esté en pantalla pasa a máscaras (o vuelve a cifras) en silencio,
    /// sin alerta ni sonido y sin alargar su caducidad.
    static func setHidden(_ hidden: Bool) async {
        for activity in live {
            var state = activity.content.state
            guard state.hidden != hidden else { continue }
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
