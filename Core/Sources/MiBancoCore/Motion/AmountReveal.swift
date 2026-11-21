import Foundation

/// Lo que decide qué cifra se dibuja cuando un importe cambia o el ojo (modo privado) se abre y se cierra. Es una
/// máquina de estados pura: la vista solo guarda los temporizadores y dibuja lo que este tipo le dice, así la regla
/// «con el ojo cerrado no hay cifra real en pantalla y al abrir sale el importe de AHORA» se prueba en Linux.
///
/// Con el ojo cambiando (sin Reducir movimiento) hay un barajado de ~240 ms: `drawn == .scramble` y `scramblePending`.
/// Al acabar, `scrambleEnded` lo resuelve con el importe más reciente. Cada cambio de ojo sube `generation`: un
/// «barajado terminado» de un temporizador ya cancelado llega con una generación vieja y no hace nada.
public struct AmountReveal: Equatable, Sendable {
    /// Lo que está dibujado: la cifra real, dígitos al azar que no salen del importe, o los puntos de la máscara.
    public enum Drawn: Equatable, Sendable {
        case real, scramble, dots
    }

    public enum Event: Equatable, Sendable {
        /// Llega un importe nuevo (en céntimos).
        case valueChanged(Int)
        /// El ojo se cierra (`hidden == true`) o se abre.
        case eyeChanged(hidden: Bool)
        /// Acabó el barajado que empezó con esa generación.
        case scrambleEnded(generation: Int)
    }

    /// Lo que la vista tiene que hacer a continuación.
    public enum Action: Equatable, Sendable {
        case none
        /// Rodar los dígitos hasta este importe.
        case rollTo(Int)
        /// Fundir hasta este importe (Reducir movimiento): sin giro.
        case crossFadeTo(Int)
        /// Empezar el barajado de esta generación (y avisar con `scrambleEnded` al acabar).
        case startScramble(generation: Int)
        /// Enseñar los puntos.
        case showDots
    }

    public private(set) var drawn: Drawn
    /// El importe más reciente, también el que llegó con el ojo cambiando.
    public private(set) var latest: Int
    /// El importe que dibuja `.real` (el último al que se rodó o fundió).
    public private(set) var target: Int
    public private(set) var hidden: Bool
    public private(set) var generation = 0
    public private(set) var scramblePending = false

    public init(cents: Int, hidden: Bool) {
        self.drawn = hidden ? .dots : .real
        self.latest = cents
        self.target = cents
        self.hidden = hidden
    }

    /// Procesa un evento y devuelve lo que hay que hacer. `reduceMotion`: sin barajado ni giro, solo fundidos.
    @discardableResult
    public mutating func apply(_ event: Event, reduceMotion: Bool) -> Action {
        switch event {
        case .valueChanged(let cents):
            latest = cents
            // Con el ojo cerrado o cambiando no se toca nada visible: se resuelve al acabar con `latest`.
            guard !hidden, drawn == .real else { return .none }
            target = cents
            return reduceMotion ? .crossFadeTo(cents) : .rollTo(cents)

        case .eyeChanged(let nowHidden):
            guard nowHidden != hidden else { return .none }
            hidden = nowHidden
            generation += 1
            if reduceMotion {
                scramblePending = false
                if nowHidden {
                    drawn = .dots
                    return .showDots
                }
                drawn = .real
                target = latest
                return .crossFadeTo(latest)
            }
            scramblePending = true
            drawn = .scramble
            return .startScramble(generation: generation)

        case .scrambleEnded(let ended):
            guard scramblePending, ended == generation else { return .none }
            scramblePending = false
            if hidden {
                drawn = .dots
                return .showDots
            }
            drawn = .real
            target = latest
            return .rollTo(latest)
        }
    }

    /// Lo que se dibuja ahora mismo si la vista ya sabe que el ojo está cerrado (`hiddenInput`) pero el evento aún no
    /// ha llegado (el primer fotograma tras tocar el ojo): una cifra real no se dibuja nunca con el ojo cerrado.
    public func displayed(hiddenInput: Bool, reduceMotion: Bool) -> Drawn {
        if hiddenInput, drawn == .real { return reduceMotion ? .dots : .scramble }
        return drawn
    }
}
