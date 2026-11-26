#if DEBUG
import Foundation
import MiBancoCore

// Banderas de demo de movimiento de Inicio. Dueño: la línea A «Inicio» (fase B). Nadie más edita este fichero.
// Cada bandera usa `DemoMode.arguments` o `DemoMode.value(after:)` (`DemoMode.swift` no se toca).
extension DemoMode {
    /// Un momento de Inicio que no se puede provocar y fotografiar a la vez desde una prueba.
    enum CardMoment: String {
        /// La tarjeta se levanta unos segundos (como al mantenerla pulsada) y se suelta.
        case lift
        /// La inclinación del teléfono barre de un lado a otro (en el simulador no hay giroscopio).
        case tilt
        /// La pista del primer día: la tarjeta asoma unos grados, como si fuera a voltearse.
        case peek
        /// Un deslizamiento programado a la tarjeta siguiente, 0,8 s después del toque (para fotografiarlo entero).
        case glide
        /// Lo mismo hasta la última tarjeta.
        case glideFar
        /// Llega un pago (el mismo camino que un aviso real: `Ledger.ingest`).
        case arrival
        /// Llega dinero.
        case arrivalIncome
        /// Las tarjetas se abren en abanico (como al mantener pulsada una tarjeta levantada).
        case fan
        /// Tirar para actualizar, sin dedo: el indicador se dibuja, brilla y dice «Al día».
        case refresh
        /// La primera fila se desliza y enseña sus acciones.
        case rowSwipe
        /// Se anuncia una llegada cuyo movimiento nunca se publica (como un aviso que sustituye a otro): tiene que
        /// caducar sin dejar la fila marcada como nueva.
        case staleArrival
        /// La búsqueda se abre 0,8 s después del toque y se cierra 3 s más tarde (XCUITest no devuelve el toque de la
        /// lupa hasta que la app está quieta: así la ráfaga ve el cambio entero).
        case search
    }

    /// `-MiBancoDemoCardMoment <momento>` (solo con `-MiBancoDemo`): tocar el segmento que YA está elegido dispara
    /// ese momento, para sacarlo en una ráfaga de fotogramas.
    static var cardMoment: CardMoment? {
        guard isActive else { return nil }
        return value(after: "-MiBancoDemoCardMoment").flatMap(CardMoment.init(rawValue:))
    }

    /// `-MiBancoDemoGlideWins` (solo con `-MiBancoDemo`): la regresión exacta que vigila la prueba de deslizar a medias.
    /// Solo cuando termina un deslizamiento PROGRAMADO que el dedo interrumpió, el carrusel vuelve a la tarjeta del
    /// programa en vez de quedarse donde lo dejó el dedo. Fuera de un deslizamiento programado el dedo manda como siempre.
    /// Con esta bandera la comprobación de la prueba tiene que ponerse roja (así se sabe que la prueba puede fallar).
    static var glideWinsOverFinger: Bool { isActive && arguments.contains("-MiBancoDemoGlideWins") }

    /// `-MiBancoDemoKeypadDelay <s>`: en el teclado de «Mover dinero» cada tecla hace efecto esos segundos después del
    /// toque (para fotografiar la entrada del dígito desde el principio). nil = al momento.
    static var keypadDelay: Double? {
        guard isActive, let seconds = value(after: "-MiBancoDemoKeypadDelay").flatMap(Double.init), seconds.isFinite,
              seconds > 0 else { return nil }
        return min(seconds, 5)
    }

    /// `-MiBancoDemoListBlanks` (solo con `-MiBancoDemo`): la regresión exacta que vigila la prueba del cambio de
    /// lista: la lista nueva parte de invisible (pantalla en negro bajo el selector). La sonda tiene que dar 0.
    static var listSwapBlanks: Bool { isActive && arguments.contains("-MiBancoDemoListBlanks") }

    /// `-MiBancoDemoEyeOpensMidBuild` (solo con `-MiBancoDemo`): con el ojo cerrado, se abre 0,3 s (× intensidad y
    /// cámara lenta) después de empezar el montaje de Inicio (para fotografiar el ojo abierto a mitad del montaje).
    static var eyeOpensMidBuild: Bool { isActive && arguments.contains("-MiBancoDemoEyeOpensMidBuild") }

    /// `-MiBancoDemoArrivalIncome` (con `-MiBancoDemoArrival`): lo que llega es dinero que entra, no un pago.
    static var arrivalIsIncome: Bool { arguments.contains("-MiBancoDemoArrivalIncome") }

    /// `-MiBancoDemoDrawnText` (solo con `-MiBancoDemo`): Inicio y «Mover dinero» publican, para las pruebas de toque,
    /// cuántos importes en texto han dibujado con el ojo cerrado y cuántos de ellos llevaban una cifra (tiene que ser 0).
    static var auditsDrawnText: Bool { isActive && arguments.contains("-MiBancoDemoDrawnText") }

    /// `-MiBancoDemoHomeProbes` (solo con `-MiBancoDemo`): Inicio publica contadores para las pruebas de toque (montajes
    /// por capas, lecturas de la inclinación, actualizaciones al tirar, estado del abanico).
    static var exposesHomeProbes: Bool { isActive && arguments.contains("-MiBancoDemoHomeProbes") }

    /// `-MiBancoDemoRefresh <fresh|consentExpired|budgetUsed>` (solo con `-MiBancoDemo`): lo que «responde» cada banco
    /// conectado al tirar para actualizar (la demo no consulta a nadie). Por defecto, que ya estaba reciente. El
    /// resultado pasa por `RefreshVerdict`, igual que en la app de verdad; sin `-MiBancoDemoBanks` no hay ningún banco
    /// conectado y por tanto nunca se dice «Al día».
    static var refreshSkipReason: SkipReason {
        switch value(after: "-MiBancoDemoRefresh") {
        case "consentExpired": .consentExpired
        case "budgetUsed": .budgetUsed(nextAt: Date().addingTimeInterval(3_600))
        default: .fresh
        }
    }
}
#endif
