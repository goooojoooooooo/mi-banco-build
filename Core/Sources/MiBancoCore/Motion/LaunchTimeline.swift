import Foundation

/// Un fotograma del arranque «logo en piezas»: todo lo que hay que dibujar en un instante, en valores de 0 a 1.
public struct LaunchFrame: Equatable, Sendable {
    /// Cuánto han llegado las dos mitades de la ola: 0 = fuera de la pantalla, 1 = encajadas.
    public var piece: Double
    public var pieceOpacity: Double
    /// Velocidad de las piezas (recorridos por segundo del guion): de ella sale la longitud de su estela.
    public var pieceSpeed: Double
    /// Las dos mitades ya son una sola ola.
    public var joined: Bool
    /// Avance de las líneas de velocidad; nil = no se dibujan.
    public var lines: Double?
    /// Cuánto se ha dibujado el canto de la loseta.
    public var edge: Double
    /// La loseta: opacidad (y escala 0,82 → 1).
    public var body: Double
    /// El nombre: opacidad (y su interletraje se cierra de 0,42 a 0,18 em).
    public var name: Double
    /// Posición del brillo que cruza la marca; nil = sin brillo.
    public var sheen: Double?
    /// Las dos bandas de titanio: cuánto se ha trazado la línea fina y cuánto se ha ensanchado. Vacío = sin bandas.
    public var bandDraw: [Double]
    public var bandWiden: [Double]
    /// El vuelo de la marca a su ranura de la barra superior (muelle: puede pasarse un poco de 1).
    public var flight: Double
    /// Opacidad del negro que tapa Inicio.
    public var black: Double
    /// Opacidad de la marca y de su nombre.
    public var mark: Double

    /// La marca entera y quieta, sobre negro.
    static let assembled = LaunchFrame(
        piece: 1, pieceOpacity: 1, pieceSpeed: 0, joined: true, lines: nil, edge: 1, body: 1, name: 1, sheen: nil,
        bandDraw: [], bandWiden: [], flight: 0, black: 1, mark: 1)
}

/// El guion del arranque: tiempos puros (como `MarkTimeline`), sin SwiftUI, para poder probarlos en Linux.
///
/// Guion a nivel Equilibrado, en segundos: las dos mitades de la ola llegan 0–0,56 (muelle 0,5 / 0,88) entre líneas de
/// velocidad 0–0,62; la loseta aparece 0,40–0,70 y su canto se dibuja 0,42–0,80; el nombre 0,52–0,86; un brillo cruza
/// 0,64–0,98; a 0,78 Inicio empieza a montarse debajo; dos bandas barren 0,82–1,10; la marca vuela a la barra superior
/// 0,86–1,20 mientras el negro se aclara 0,86–1,18. Total 1,20 s; en Expresivo ×1,12 = 1,34 s.
/// En Sutil y con Reducir movimiento no hay nada de eso: solo un fundido.
/// Todos los tiempos que da este tipo son reales a velocidad normal; quien graba a cámara lenta los multiplica.
public struct LaunchTimeline: Equatable, Sendable {
    public enum Style: Equatable, Sendable {
        /// Las piezas llegan, encajan y la marca vuela.
        case pieces
        /// Solo un fundido (Sutil y Reducir movimiento).
        case fade
    }

    public let style: Style
    public let level: MotionLevel
    public let reduceMotion: Bool
    /// Líneas de velocidad, brillo y bandas: no con Bajo consumo.
    public let richEffects: Bool
    /// El muelle del vuelo (el de `fly` del kit).
    public let fly: SpringSpec

    public init(
        level: MotionLevel, reduceMotion: Bool, lowPower: Bool = false,
        fly: SpringSpec = SpringSpec(response: 0.50, dampingFraction: 0.84)
    ) {
        self.level = level
        self.reduceMotion = reduceMotion
        self.fly = fly
        style = reduceMotion || level == .subtle ? .fade : .pieces
        richEffects = !reduceMotion && !lowPower
    }

    // MARK: El guion (segundos a nivel Equilibrado)

    static let piecesEnd = 0.56
    static let linesEnd = 0.62
    static let bodyWindow = (from: 0.40, to: 0.70)
    static let edgeWindow = (from: 0.42, to: 0.80)
    static let nameWindow = (from: 0.52, to: 0.86)
    static let sheenWindow = (from: 0.64, to: 0.98)
    static let assemble = 0.78
    static let bandsStart = 0.82
    static let flightStart = 0.86
    static let blackGone = 1.18
    static let markFadeStart = 1.10
    static let end = 1.20
    /// El muelle de las piezas.
    static let pieceSpring = SpringSpec(response: 0.50, dampingFraction: 0.88)
    /// Fundidos de Sutil y de Reducir movimiento.
    static let fadeOut = 0.28
    static let reduceFadeIn = 0.24
    /// Tras un toque, lo que queda corre a esta fracción de su tiempo.
    public static let skipRate = 0.3
    /// Margen para que un instante que cae justo en una frontera no quede a un lado u otro por un redondeo.
    static let epsilon = 1e-9

    /// Multiplicador de tiempo del nivel (solo con piezas; los fundidos duran lo mismo en todos los niveles).
    private var scale: Double { style == .pieces ? level.timeScale : 1 }

    // MARK: Momentos (segundos reales)

    /// Cuánto dura el arranque entero.
    public var duration: Double {
        switch style {
        case .pieces: Self.end * scale
        case .fade: reduceMotion ? Self.reduceFadeIn + Self.fadeOut : Self.fadeOut
        }
    }

    /// Cuándo empieza Inicio a montarse debajo.
    public var assembleAt: Double {
        switch style {
        case .pieces: Self.assemble * scale
        case .fade: reduceMotion ? Self.reduceFadeIn : 0
        }
    }

    /// Cuándo echa a volar la marca; nil si solo hay fundido.
    public var flightAt: Double? {
        style == .pieces ? Self.flightStart * scale : nil
    }

    /// Desde cuándo la capa deja pasar los toques a Inicio (antes, un toque la salta).
    public var interactiveAt: Double { flightAt ?? assembleAt }

    // MARK: El reloj y el salto

    /// Segundos del guion a partir del tiempo real transcurrido. Con un toque en `skippedAt`, el guion salta al vuelo
    /// (o, si solo hay fundido, al momento en que Inicio empieza a verse) y lo que queda corre a ×0,3.
    public func time(elapsed: Double, skippedAt: Double?) -> Double {
        guard let skippedAt, elapsed >= skippedAt else { return max(0, elapsed) }
        return max(skippedAt, interactiveAt) + (elapsed - skippedAt) / Self.skipRate
    }

    /// El tiempo real en que termina todo, con o sin salto.
    public func finishesAt(skippedAt: Double?) -> Double {
        guard let skippedAt, skippedAt < duration else { return duration }
        return skippedAt + (duration - max(skippedAt, interactiveAt)) * Self.skipRate
    }

    // MARK: Fotogramas

    /// El fotograma del arranque en el segundo `seconds` del guion. `skipped`: tras un toque no hay brillo ni bandas.
    public func frame(at seconds: Double, skipped: Bool = false) -> LaunchFrame {
        switch style {
        case .fade: fadeFrame(at: seconds)
        case .pieces: piecesFrame(at: seconds / scale, skipped: skipped)
        }
    }

    private func fadeFrame(at t: Double) -> LaunchFrame {
        var frame = LaunchFrame.assembled
        if reduceMotion {
            if t < Self.reduceFadeIn {
                frame.mark = Self.window(t, 0, Self.reduceFadeIn)
            } else {
                let gone = Self.window(t, Self.reduceFadeIn, Self.reduceFadeIn + Self.fadeOut)
                frame.mark = 1 - gone
                frame.black = 1 - gone
            }
        } else {
            let gone = Self.easeOut(Self.window(t, 0, Self.fadeOut))
            frame.mark = 1 - gone
            frame.black = 1 - gone
        }
        return frame
    }

    /// `n`: segundos del guion a nivel Equilibrado.
    private func piecesFrame(at n: Double, skipped: Bool) -> LaunchFrame {
        var frame = LaunchFrame.assembled
        let rich = richEffects && !skipped

        if n < Self.piecesEnd - Self.epsilon, !skipped {
            let damping = MotionMath.scaled(Self.pieceSpring, level: level).dampingFraction
            let response = Self.pieceSpring.response
            let raw = Self.spring(n, response: response, dampingFraction: damping)
            // El muelle no llega exactamente a 1 en 0,56 s: lo que falta se reparte suave para que encajen sin salto.
            let rest = 1 - Self.spring(Self.piecesEnd, response: response, dampingFraction: damping)
            let x = max(0, n / Self.piecesEnd)
            frame.piece = raw + rest * x * x * (3 - 2 * x)
            frame.pieceOpacity = min(1, max(0, frame.piece * 5))
            frame.pieceSpeed = Self.springSpeed(n, response: response, dampingFraction: damping)
            frame.joined = false
        }
        if rich, n < Self.linesEnd - Self.epsilon {
            frame.lines = max(0, n / Self.linesEnd)
        }
        if !skipped {
            frame.body = Self.easeOut(Self.window(n, Self.bodyWindow.from, Self.bodyWindow.to))
            frame.edge = Self.easeOut(Self.window(n, Self.edgeWindow.from, Self.edgeWindow.to))
            frame.name = Self.easeOut(Self.window(n, Self.nameWindow.from, Self.nameWindow.to))
        }
        if rich, n > Self.sheenWindow.from, n < Self.sheenWindow.to - Self.epsilon {
            frame.sheen = Self.inOut(Self.window(n, Self.sheenWindow.from, Self.sheenWindow.to))
        }
        if rich {
            // Dos bandas, la segunda un poco después: la línea fina se traza (0,14 s) y luego se ensancha (0,16 s).
            frame.bandDraw = (0..<2).map { band in
                let from = Self.bandsStart + 0.03 * Double(band)
                return Self.inOut(Self.window(n, from, from + 0.14))
            }
            frame.bandWiden = (0..<2).map { band in
                let from = 0.92 + 0.02 * Double(band)
                return Self.inOut(Self.window(n, from, from + 0.16))
            }
        }
        if n > Self.flightStart {
            let damping = MotionMath.scaled(fly, level: level).dampingFraction
            frame.flight = Self.spring(n - Self.flightStart, response: fly.response, dampingFraction: damping)
        }
        frame.black = 1 - Self.easeOut(Self.window(n, Self.flightStart, Self.blackGone))
        frame.mark = 1 - Self.window(n, Self.markFadeStart, Self.end)
        return frame
    }

    // MARK: En el bloqueo (arranque en frío)

    /// Cuánto tarda la marca del bloqueo en quedar montada: con piezas, hasta que pasa el brillo; en Sutil, un fundido;
    /// con Reducir movimiento, nada (la marca está quieta desde el principio).
    public var lockDuration: Double {
        switch style {
        case .pieces: Self.sheenWindow.to * scale
        case .fade: reduceMotion ? 0 : Self.fadeOut
        }
    }

    /// La marca del bloqueo en el segundo `seconds`: las piezas se montan igual, pero nada vuela, nada destapa lo que hay
    /// debajo y no hay bandas. Pasada `lockDuration`, siempre el mismo fotograma (marca entera, quieta).
    public func lockFrame(at seconds: Double) -> LaunchFrame {
        switch style {
        case .fade:
            var frame = LaunchFrame.assembled
            if !reduceMotion { frame.mark = Self.window(seconds, 0, Self.fadeOut) }
            return frame
        case .pieces:
            var frame = piecesFrame(at: min(max(0, seconds), lockDuration) / scale, skipped: false)
            frame.bandDraw = []
            frame.bandWiden = []
            frame.flight = 0
            frame.black = 1
            frame.mark = 1
            return frame
        }
    }

    // MARK: La salida tras desbloquear

    /// Tras desbloquear, la marca (ya montada) vuela a su ranura; en el arranque en frío, además, cruzan las bandas.
    /// Es el tramo final del guion (0,82–1,20). nil si solo hay fundido: entonces el bloqueo se funde y ya está.
    public var exitDuration: Double? {
        style == .pieces ? (Self.end - Self.bandsStart) * scale : nil
    }

    /// El fotograma de la salida a los `seconds` de desbloquear. `black` sirve de opacidad del parche que tapa la marca
    /// del bloqueo mientras este se funde.
    public func exitFrame(at seconds: Double, bands: Bool) -> LaunchFrame {
        guard style == .pieces else {
            var frame = LaunchFrame.assembled
            frame.black = 0
            frame.mark = 0
            return frame
        }
        var frame = piecesFrame(at: Self.bandsStart + max(0, seconds) / scale, skipped: false)
        frame.piece = 1
        frame.pieceOpacity = 1
        frame.pieceSpeed = 0
        frame.joined = true
        frame.lines = nil
        frame.edge = 1
        frame.body = 1
        frame.name = 1
        frame.sheen = nil
        if !bands {
            frame.bandDraw = []
            frame.bandWiden = []
        }
        return frame
    }

    // MARK: Cuentas

    /// Avance de 0 a 1 dentro de una ventana de tiempo; exactamente 0 antes y exactamente 1 al final.
    static func window(_ t: Double, _ from: Double, _ to: Double) -> Double {
        if t <= from { return 0 }
        if t >= to - epsilon { return 1 }
        return (t - from) / (to - from)
    }

    /// Respuesta al escalón (de 0 a 1) de un muelle como los de SwiftUI: `response` en segundos y `dampingFraction`
    /// (1 = sin rebote).
    static func spring(_ t: Double, response: Double, dampingFraction: Double) -> Double {
        guard t > 0 else { return 0 }
        guard response > 0 else { return 1 }
        let omega = 2 * Double.pi / response
        let zeta = max(0, dampingFraction)
        if zeta < 1 {
            let damped = omega * (1 - zeta * zeta).squareRoot()
            let decay = exp(-zeta * omega * t)
            return 1 - decay * (cos(damped * t) + zeta * omega / damped * sin(damped * t))
        }
        return 1 - exp(-omega * t) * (1 + omega * t)
    }

    /// Velocidad del mismo muelle (por segundo).
    static func springSpeed(_ t: Double, response: Double, dampingFraction: Double) -> Double {
        guard t > 0, response > 0 else { return 0 }
        let omega = 2 * Double.pi / response
        let zeta = max(0, dampingFraction)
        if zeta < 1 {
            let damped = omega * (1 - zeta * zeta).squareRoot()
            return exp(-zeta * omega * t) * omega * omega / damped * sin(damped * t)
        }
        return omega * omega * t * exp(-omega * t)
    }

    /// Las curvas del prototipo: salida suave (0,22; 1; 0,36; 1) y entrada-salida (0,77; 0; 0,175; 1).
    static func easeOut(_ t: Double) -> Double { bezier(t, 0.22, 1, 0.36, 1) }
    static func inOut(_ t: Double) -> Double { bezier(t, 0.77, 0, 0.175, 1) }

    /// Curva cúbica de Bézier como las de CSS: el valor en el instante `t` (0…1).
    static func bezier(_ t: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        func coordinate(_ u: Double, _ a: Double, _ b: Double) -> Double {
            3 * (1 - u) * (1 - u) * u * a + 3 * (1 - u) * u * u * b + u * u * u
        }
        // Se busca el parámetro u con x(u) = t por bisección.
        var low = 0.0, high = 1.0, u = t
        for _ in 0..<32 {
            u = (low + high) / 2
            if coordinate(u, x1, x2) < t { low = u } else { high = u }
        }
        return coordinate(u, y1, y2)
    }
}
