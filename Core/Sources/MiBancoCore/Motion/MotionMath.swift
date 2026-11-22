import Foundation

/// Intensidad del movimiento (Ajustes › Animaciones): multiplica el tiempo, el recorrido y el rebote.
public enum MotionLevel: String, CaseIterable, Sendable, Codable {
    case subtle, balanced, expressive

    /// Sutil ×0,85 · Equilibrado ×1 · Expresivo ×1,12.
    public var timeScale: Double {
        switch self {
        case .subtle: 0.85
        case .balanced: 1
        case .expressive: 1.12
        }
    }

    /// Sutil ×0,6 · Equilibrado ×1 · Expresivo ×1,45.
    public var distanceScale: Double {
        switch self {
        case .subtle: 0.6
        case .balanced: 1
        case .expressive: 1.45
        }
    }

    /// Sutil ×0,45 · Equilibrado ×1 · Expresivo ×1,7.
    public var bounceScale: Double {
        switch self {
        case .subtle: 0.45
        case .balanced: 1
        case .expressive: 1.7
        }
    }
}

/// Un muelle como lo entiende SwiftUI: `response` (s) y `dampingFraction` (1 = sin rebote).
public struct SpringSpec: Equatable, Sendable {
    public var response: Double
    public var dampingFraction: Double

    public init(response: Double, dampingFraction: Double) {
        self.response = response
        self.dampingFraction = dampingFraction
    }
}

/// Las cuentas del movimiento, sin SwiftUI para poder probarlas en Linux.
public enum MotionMath {
    /// Rebote máximo tras escalar (rebote = 1 − dampingFraction).
    static let maxBounce = 0.62

    /// Aplica la intensidad: tiempo × `timeScale` × `timeMultiplier` y rebote × `bounceScale` (tope 0,62).
    public static func scaled(_ spec: SpringSpec, level: MotionLevel, timeMultiplier: Double = 1) -> SpringSpec {
        let bounce = min(maxBounce, max(0, 1 - spec.dampingFraction) * level.bounceScale)
        return SpringSpec(
            response: spec.response * level.timeScale * timeMultiplier,
            dampingFraction: 1 - bounce)
    }

    /// Retardo de cada pieza: acumulado de `firstGap × decayⁿ`; congelado desde la pieza `animatedLimit − 1`
    /// (como mucho `animatedLimit` piezas animadas; el resto aparece con la última).
    public static func staggerDelays(count: Int, firstGap: Double, decay: Double, animatedLimit: Int = 9) -> [Double] {
        guard count > 0 else { return [] }
        var delays = [Double](repeating: 0, count: count)
        var gap = firstGap
        let last = max(0, animatedLimit - 1)
        for i in 1..<max(count, 1) {
            if i > last {
                delays[i] = delays[last]
            } else {
                delays[i] = delays[i - 1] + gap
                gap *= decay
            }
        }
        return delays
    }

    /// Resistencia al pasarse del borde: crece cada vez más despacio y nunca supera `dimension / coefficient`.
    public static func rubberBand(_ overshoot: Double, dimension: Double, coefficient: Double = 0.55) -> Double {
        guard overshoot != 0, dimension > 0 else { return 0 }
        let x = abs(overshoot)
        let value = (1 - 1 / (x * coefficient / dimension + 1)) * dimension / coefficient
        return overshoot < 0 ? -value : value
    }

    /// Porcentaje entero de una fracción (0,954 → 95), sin trampas: lo que no es un número (gasto / presupuesto 0) es 0 y
    /// lo finito se acota a 0…999 antes de redondear.
    public static func percent(_ fraction: Double) -> Int {
        guard fraction.isFinite else { return 0 }
        return Int(min(999, max(0, fraction * 100)).rounded())
    }

    /// Una fracción para dibujar un relleno: 0…1, y 0 si no es un número.
    public static func unit(_ fraction: Double) -> Double {
        guard fraction.isFinite else { return 0 }
        return min(1, max(0, fraction))
    }

    /// La fracción limpia con la que se decide todo lo demás de una barra: lo que no es un número finito (gasto /
    /// presupuesto 0, 0 / 0) es 0, igual que en `percent` y `unit`.
    public static func finite(_ fraction: Double) -> Double {
        fraction.isFinite ? fraction : 0
    }

    /// Si una barra está pasada de su aviso (`warnAt`; nil = nunca avisa). Lee la fracción limpia: una barra que enseña
    /// «0 %» porque el presupuesto es 0 no se pone en ámbar, no parpadea y no vibra.
    public static func isOver(_ fraction: Double, warnAt: Double?) -> Bool {
        guard let warnAt else { return false }
        return finite(fraction) >= warnAt
    }

    /// Lo que usa un cambio de color u opacidad con Reducir movimiento: mismo tiempo, nunca rebota.
    public static func calm(_ spec: SpringSpec) -> SpringSpec {
        SpringSpec(response: spec.response, dampingFraction: 1)
    }
}
