import SwiftUI
import Observation

/// Estado VIVO de "se puede subir una hoja": bloqueo puesto y app en primer plano.
/// Es una clase para que los cierres que `RootView` reparte (que llevan una copia de la vista) lean el valor de ahora
/// y no el de cuando se pasaron: así una exportación o una tarea aplazada no abre nada encima del bloqueo.
@MainActor @Observable final class PresentationGate {
    var isLocked = false
    var isActive = true
    var canPresent: Bool { !isLocked && isActive }
    /// Sube cada vez que se cierra todo (bloqueo o salir de primer plano): lo que se pidió antes de ese momento
    /// y termina después se descarta, aunque la app ya se haya desbloqueado otra vez.
    var generation = 0
}

private struct PresentationGateKey: EnvironmentKey {
    static let defaultValue: PresentationGate? = nil
}

extension EnvironmentValues {
    var presentationGate: PresentationGate? {
        get { self[PresentationGateKey.self] }
        set { self[PresentationGateKey.self] = newValue }
    }
}
