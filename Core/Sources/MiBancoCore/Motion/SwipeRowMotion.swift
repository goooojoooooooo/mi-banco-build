import Foundation

/// Reglas puras de la fila deslizada (N-1 y N-2): opacidades disjuntas del importe y las acciones (nunca a la vez, ni
/// al abrir ni al cerrar) y desplazamiento del contenido (con texto de accesibilidad la primera letra del nombre no
/// entra nunca en el borde izquierdo).
public enum SwipeRowMotion {
    /// El importe se apaga por completo en los primeros 25 pt de apertura.
    public static let amountFadeDistance = 25.0
    /// Las acciones solo empiezan a verse a partir de 25 pt (cuando el importe ya es 0) y llegan al 100 % en 75 pt.
    public static let actionsFadeStart = 25.0
    public static let actionsFadeSpan = 50.0
    /// En tamaño normal el contenido solo se aparta un 40 % para mantener el nombre a la vista.
    public static let normalContentShare = 0.4

    /// Opacidad del importe (1 cerrada, 0 a partir de −25 pt).
    public static func amountOpacity(offset: Double) -> Double {
        guard offset.isFinite else { return 1 }
        return 1 - min(max(-offset / amountFadeDistance, 0), 1)
    }

    /// Opacidad de las cápsulas de acción (0 hasta −25 pt, 1 a partir de −75 pt): estrictamente disjunta de `amountOpacity`.
    public static func actionsOpacity(offset: Double) -> Double {
        guard offset.isFinite else { return 0 }
        return min(max((-offset - actionsFadeStart) / actionsFadeSpan, 0), 1)
    }

    /// Desplazamiento horizontal del contenido de la fila para un `offset` dado.
    /// - Con `leadingShiftLimit == nil` (tamaño normal): `offset * normalShare`.
    /// - Con `leadingShiftLimit != nil` (texto de accesibilidad, donde la losa y su hueco miden `leadingShiftLimit`):
    ///   escala la apertura para que, al abrir del todo (`-span`), el contenido se aparte como mucho `min(span, limit)`,
    ///   dejando el inicio del nombre en el margen izquierdo (nunca fundido ni recortado).
    public static func contentShift(
        offset: Double,
        span: Double,
        leadingShiftLimit: Double?,
        normalShare: Double = normalContentShare
    ) -> Double {
        guard offset.isFinite, span.isFinite, span > 0 else { return 0 }
        guard let limit = leadingShiftLimit, limit.isFinite else {
            return offset * normalShare
        }
        let share = min(1, max(0, limit) / span)
        return offset * share
    }
}
