import Foundation

/// Estado VIVO de "se puede subir una hoja": bloqueo puesto y app en primer plano.
/// Es una clase para que los cierres que `RootView` reparte (que llevan una copia de la vista) lean el valor de ahora
/// y no el de cuando se pasaron: así una exportación que termina tarde no abre la hoja encima del bloqueo.
@MainActor final class PresentationGate {
    var isLocked = false
    var isActive = true
    var canPresent: Bool { !isLocked && isActive }
}
