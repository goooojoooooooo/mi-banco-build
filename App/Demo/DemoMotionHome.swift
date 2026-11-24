#if DEBUG
import Foundation

// Banderas de demo de movimiento de Inicio. Dueño: la línea A «Inicio» (fase B). Nadie más edita este fichero.
// Cada bandera usa `DemoMode.arguments` o `DemoMode.value(after:)` (`DemoMode.swift` no se toca).
extension DemoMode {
    /// Un momento de la tarjeta de delante que no se puede provocar y fotografiar a la vez desde una prueba.
    enum CardMoment: String {
        /// La tarjeta se levanta unos segundos (como al mantenerla pulsada) y se suelta.
        case lift
        /// La inclinación del teléfono barre de un lado a otro (en el simulador no hay giroscopio).
        case tilt
        /// La pista del primer día: la tarjeta asoma unos grados, como si fuera a voltearse.
        case peek
    }

    /// `-MiBancoDemoCardMoment lift|tilt|peek` (solo con `-MiBancoDemo`): tocar el segmento que YA está elegido dispara
    /// ese momento en la tarjeta de delante, para sacarlo en una ráfaga de fotogramas.
    /// SONDA TEMPORAL: `-MiBancoDemoCarouselProbe <n>` apaga una pieza del carrusel.
    static var carouselProbe: Int { value(after: "-MiBancoDemoCarouselProbe").flatMap(Int.init) ?? 0 }

    static var cardMoment: CardMoment? {
        guard isActive else { return nil }
        return value(after: "-MiBancoDemoCardMoment").flatMap(CardMoment.init(rawValue:))
    }
}
#endif
