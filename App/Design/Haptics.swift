import SwiftUI

/// Las hápticas de Titanio, ligadas a un significado (nunca a cada toque). Se usan con `.sensoryFeedback`.
enum Haptics {
    /// Cada tope del carrusel y del segmentado.
    static var detent: SensoryFeedback { SensoryFeedback.selection }
    /// Tirar más allá del borde del carrusel.
    static var edge: SensoryFeedback { SensoryFeedback.impact(weight: .light) }
    /// Llega un pago.
    static var payment: SensoryFeedback { SensoryFeedback.impact(flexibility: .soft) }
    /// Llega dinero; guardar algo; un aviso de prueba enviado.
    static var success: SensoryFeedback { SensoryFeedback.success }
    /// Ojo (modo privado).
    static var toggle: SensoryFeedback { SensoryFeedback.selection }
    /// "No es mío" y errores leves.
    static var warning: SensoryFeedback { SensoryFeedback.warning }
    static var error: SensoryFeedback { SensoryFeedback.error }
    /// La tarjeta se voltea.
    static var flip: SensoryFeedback { SensoryFeedback.impact(weight: .light, intensity: 0.6) }
    /// Deslizar para borrar llega al final.
    static var confirm: SensoryFeedback { SensoryFeedback.impact(weight: .medium) }

    /// Las piezas de la marca encajan (arranque): un golpe seco.
    static var lock: SensoryFeedback { SensoryFeedback.impact(flexibility: .rigid) }

    static func arrival(isIncome: Bool) -> SensoryFeedback { isIncome ? success : payment }
}
