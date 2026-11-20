import SwiftUI
import MiBancoCore

/// Los muelles con nombre (nivel Equilibrado), tal cual los fija el diseño de Movimiento 2.
/// `response` en segundos y `dampingFraction` (1 = sin rebote). La intensidad los escala en `MotionContext`.
enum SpringToken: CaseIterable {
    /// Encaje de tarjeta, detent.
    case snap
    /// Levantar (entra firme) y soltar (rebota).
    case liftIn, liftOut
    /// Hoja.
    case sheet
    /// Elemento compartido que vuela.
    case fly
    /// Cristal: se hunde al tocar y rebota al soltar.
    case pressIn, release
    /// Entradas de piezas y de filas.
    case enter, row
    /// Interruptor (el pomo se estira a 34 pt).
    case toggle
    /// Indicadores (segmentado, pestañas): aplastamiento según la velocidad.
    case indicator

    var base: SpringSpec {
        switch self {
        case .snap: SpringSpec(response: 0.46, dampingFraction: 0.74)
        case .liftIn: SpringSpec(response: 0.30, dampingFraction: 0.90)
        case .liftOut: SpringSpec(response: 0.50, dampingFraction: 0.58)
        case .sheet: SpringSpec(response: 0.44, dampingFraction: 0.90)
        case .fly: SpringSpec(response: 0.50, dampingFraction: 0.84)
        case .pressIn: SpringSpec(response: 0.16, dampingFraction: 1.0)
        case .release: SpringSpec(response: 0.42, dampingFraction: 0.50)
        case .enter: SpringSpec(response: 0.50, dampingFraction: 0.82)
        case .row: SpringSpec(response: 0.48, dampingFraction: 0.84)
        case .toggle: SpringSpec(response: 0.36, dampingFraction: 0.68)
        case .indicator: SpringSpec(response: 0.42, dampingFraction: 0.78)
        }
    }
}

/// Todo lo que una vista necesita saber para moverse: intensidad, Reducir movimiento, Bajo consumo y, solo para
/// grabar a cámara lenta, un multiplicador de tiempo. Se lee con `@Environment(\.motion)`.
struct MotionContext: Equatable, Sendable {
    var level: MotionLevel = .balanced
    var reduce = false
    var lowPower = false
    var timeMultiplier = 1.0

    /// El muelle del token con la intensidad aplicada; con Reducir movimiento, un fundido.
    func animation(_ token: SpringToken) -> Animation {
        guard !reduce else { return fade }
        let spec = MotionMath.scaled(token.base, level: level, timeMultiplier: timeMultiplier)
        return .spring(response: spec.response, dampingFraction: spec.dampingFraction)
    }

    /// Para colores y opacidades: nunca rebota (con Reducir movimiento, el fundido).
    func calmAnimation(_ token: SpringToken) -> Animation {
        guard !reduce else { return fade }
        let spec = MotionMath.calm(MotionMath.scaled(token.base, level: level, timeMultiplier: timeMultiplier))
        return .spring(response: spec.response, dampingFraction: spec.dampingFraction)
    }

    /// Fundido tranquilo (Reducir movimiento).
    var fade: Animation { .easeOut(duration: 0.22 * timeMultiplier) }

    /// Recorrido en puntos según la intensidad; 0 con Reducir movimiento.
    func distance(_ pt: CGFloat) -> CGFloat {
        reduce ? 0 : pt * level.distanceScale
    }

    /// Una duración (s) según la intensidad.
    func seconds(_ s: Double) -> Double {
        s * level.timeScale * timeMultiplier
    }

    /// Retardo (s) de la pieza `index` en una entrada escalonada; 0 con Reducir movimiento.
    func stagger(_ index: Int, firstGap: Double, decay: Double) -> Double {
        guard !reduce, index >= 0 else { return 0 }
        let delays = MotionMath.staggerDelays(count: index + 1, firstGap: firstGap, decay: decay)
        return seconds(delays[index])
    }

    /// Brillos, halos, rayos y desenfoques de dígitos: nada de esto con Reducir movimiento ni Bajo consumo.
    var richEffects: Bool { !reduce && !lowPower }
}

extension EnvironmentValues {
    @Entry var motion = MotionContext()
}

/// Pone `\.motion` según Reducir movimiento del sistema, la intensidad elegida y Bajo consumo.
/// Va una sola vez en la raíz de la app (después de inyectar `AppPreferences`).
struct MotionEnvironment: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppPreferences.self) private var preferences
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    func body(content: Content) -> some View {
        content
            .environment(\.motion, MotionContext(level: preferences.motionLevel, reduce: reduceMotion, lowPower: lowPower))
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
    }
}

extension View {
    func motionEnvironment() -> some View { modifier(MotionEnvironment()) }
}
