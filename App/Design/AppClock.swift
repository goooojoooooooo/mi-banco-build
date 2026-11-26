import Foundation

/// El «ahora» de las pantallas. En la app de verdad es el reloj (`Date()`), sin más. En la demo (DEBUG) es `DemoMode.now`,
/// para que con `-MiBancoDemoToday` todas las pantallas cuenten desde el mismo día que el libro de la demo.
enum AppClock {
    static var now: Date {
        #if DEBUG
        if DemoMode.isActive { return DemoMode.now }
        #endif
        return Date()
    }
}
