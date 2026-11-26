import Foundation

/// Cuándo empieza la bienvenida de la primera vez y cuándo se dibuja su marca, según lo que la tapa (el arranque o el
/// bloqueo). Valor puro: la pantalla le cuenta lo que pasa y hace lo que dice.
///
/// - La bienvenida empieza (bandas, piezas) cuando lo de debajo queda a la vista: el arranque deja ver sin bloqueo, o el
///   bloqueo se abre.
/// - Su marca no se dibuja mientras la del arranque o la del bloqueo sigue en pantalla volando: aparece cuando el arranque
///   ha terminado sin bloqueo delante, o cuando ha aterrizado el vuelo de la marca del bloqueo al abrirse.
/// - Nunca se queda escondida: si el bloqueo entra mientras se espera al final del arranque, al abrirse se programa la
///   marca igual (antes se perdía).
public struct WelcomeReveal: Equatable, Sendable {
    /// La bienvenida está a la vista: bandas y piezas en marcha.
    public private(set) var welcomed = false
    /// La marca propia se dibuja.
    public private(set) var markShown = false
    /// La marca del bloqueo está volando tras abrirse: la propia espera a que aterrice.
    public private(set) var awaitingUnlockFlight = false

    public init() {}

    public enum Event: Equatable, Sendable {
        /// El arranque empieza a dejar ver lo de debajo; `locked`: el bloqueo está delante.
        case launchRevealsBelow(locked: Bool)
        /// El arranque ha terminado del todo (su marca ya se fue); `locked`: el bloqueo está delante.
        case launchFinished(locked: Bool)
        /// El bloqueo se acaba de abrir.
        case unlocked
        /// La marca del bloqueo ha terminado de volar tras abrirse.
        case unlockFlightLanded
    }

    /// Lo que la pantalla tiene que hacer después.
    public enum Effect: Equatable, Sendable {
        case none
        /// Esperar a que la marca del bloqueo termine su vuelo y mandar `unlockFlightLanded`.
        case waitForUnlockFlight
    }

    @discardableResult
    public mutating func handle(_ event: Event) -> Effect {
        switch event {
        case .launchRevealsBelow(let locked):
            if !locked { welcomed = true }
            return .none
        case .launchFinished(let locked):
            if welcomed && !locked && !awaitingUnlockFlight { markShown = true }
            return .none
        case .unlocked:
            welcomed = true
            guard !markShown else { return .none }
            awaitingUnlockFlight = true
            return .waitForUnlockFlight
        case .unlockFlightLanded:
            awaitingUnlockFlight = false
            if welcomed { markShown = true }
            return .none
        }
    }
}
