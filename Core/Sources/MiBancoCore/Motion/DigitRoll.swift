import Foundation

/// Una columna del cuentakilómetros: de qué posición a cuál rueda y cuándo. Las posiciones están en unidades de
/// dígito (0…10 de la tira); `to - from` puede ser negativo (rueda hacia atrás) y pasar de 10 (vuelta extra).
public struct DigitColumn: Equatable, Sendable {
    public let place: Int
    public let from: Double
    public let to: Double
    public let delay: Double
    public let duration: Double

    public init(place: Int, from: Double, to: Double, delay: Double, duration: Double) {
        self.place = place
        self.from = from
        self.to = to
        self.delay = delay
        self.duration = duration
    }
}

/// El ritmo de una rodada: cuánto dura la primera columna (`base`), cuánto más cada columna siguiente (`perColumn`) y
/// cuánto se retrasa su salida (`stagger`). La última columna se asienta en `total(digitCount:)`.
public struct RollTiming: Equatable, Sendable {
    public var base: Double
    public var perColumn: Double
    public var stagger: Double

    public init(base: Double, perColumn: Double, stagger: Double) {
        self.base = base
        self.perColumn = perColumn
        self.stagger = stagger
    }

    /// Contar desde 0 (o de un importe a otro).
    public static let count = RollTiming(base: 0.56, perColumn: 0.038, stagger: 0.022)
    /// Abrir el ojo: del barajado a la cifra real.
    public static let reveal = RollTiming(base: 0.38, perColumn: 0.03, stagger: 0.014)

    /// Segundos hasta que la última de `digitCount` columnas queda quieta.
    public func total(digitCount: Int) -> Double {
        base + Double(max(0, digitCount - 1)) * (perColumn + stagger)
    }

    /// Todo multiplicado por `factor` (la intensidad, la cámara lenta de las grabaciones).
    public func scaled(_ factor: Double) -> RollTiming {
        RollTiming(base: base * factor, perColumn: perColumn * factor, stagger: stagger * factor)
    }

    /// Con la misma forma, dura exactamente `seconds` con `digitCount` columnas.
    public func lasting(_ seconds: Double, digitCount: Int) -> RollTiming {
        let natural = total(digitCount: digitCount)
        guard natural > 0, seconds > 0 else { return self }
        return scaled(seconds / natural)
    }

    /// Como mucho `seconds`: si dura más, se acorta entero (misma forma); si no, se queda como está.
    public func capped(at seconds: Double, digitCount: Int) -> RollTiming {
        total(digitCount: digitCount) > seconds ? lasting(seconds, digitCount: digitCount) : self
    }
}

/// Cuánto rueda una cifra (sin la cámara lenta de las grabaciones, que se aplica después).
/// - `lead`: la cifra protagonista. Su ritmo con la intensidad, pero quieta del todo en ≤ 0,8 s a cualquier nivel.
/// - `brief`: las cifras pequeñas (saldos, «Gastado en 7 días», totales de cabecera): ≤ 0,45 s, para que el
///   protagonista sea uno solo.
/// - `seconds(s)`: quien necesite otra duración (p. ej. Suscripciones): dura exactamente `s` × la intensidad (nunca
///   más de `s`).
public enum RollLength: Equatable, Sendable {
    case lead
    case brief
    case seconds(Double)

    public static let leadLimit = 0.8
    public static let briefLimit = 0.45

    /// El ritmo de `timing` para `digitCount` columnas a la intensidad `level`.
    public func timing(_ timing: RollTiming, digitCount: Int, level: MotionLevel) -> RollTiming {
        let paced = timing.scaled(level.timeScale)
        switch self {
        case .lead:
            return paced.capped(at: Self.leadLimit, digitCount: digitCount)
        case .brief:
            return paced.capped(at: Self.briefLimit, digitCount: digitCount)
        case .seconds(let s):
            return timing.lasting(s * min(1, level.timeScale), digitCount: digitCount)
        }
    }
}

/// Las cuentas del cuentakilómetros (sin SwiftUI, para probarlas en Linux).
public enum DigitRoll {
    /// Columnas de izquierda a derecha (`place` = potencia de 10). Cada una rueda hacia el dígito nuevo en el sentido
    /// del cambio de su parte alta, más una vuelta (10) si ese cambio es de 10 o más, con tope `maxExtraTurns`.
    /// `positions` (una por columna) es donde está ahora cada tira, con decimales si se interrumpe una rodada.
    /// Una columna cuyo cambio es 0 se asienta en su dígito por el camino más corto (si ya está en él, no se mueve; si
    /// una rodada interrumpida la dejó entre dos dígitos, recorre la fracción que le falta). La duración de cada columna crece `perColumn` y su salida se retrasa `stagger`.
    public static func columns(
        from old: Int, to new: Int, digitCount: Int, startingAt positions: [Double]? = nil,
        maxExtraTurns: Int = 1, base: Double = 0.56, perColumn: Double = 0.038, stagger: Double = 0.022
    ) -> [DigitColumn] {
        guard digitCount > 0 else { return [] }
        let oldValue = abs(old), newValue = abs(new)
        return (0..<digitCount).map { index in
            let place = digitCount - 1 - index
            let unit = power10(place)
            let delta = newValue / unit - oldValue / unit
            let target = Double((newValue / unit) % 10)
            let from: Double
            if let positions, index < positions.count {
                from = positions[index]
            } else {
                from = Double((oldValue / unit) % 10)
            }
            let current = mod10(from)
            let turns = Double(10 * min(maxExtraTurns, abs(delta) / 10))
            var distance: Double
            if delta > 0 {
                distance = mod10(target - current) + turns
            } else if delta < 0 {
                distance = -mod10(current - target) - turns
            } else {
                // Sin cambio de dígito: si la tira va por un punto intermedio (se interrumpió una rodada), se asienta
                // en su dígito por el camino más corto (con signo); si ya está en él, no se mueve.
                let d = mod10(target - current)
                distance = d > 5 ? d - 10 : d
            }
            var to = from + distance
            if abs(to - to.rounded()) < 1e-9 { to = to.rounded() }
            return DigitColumn(
                place: place, from: from, to: to,
                delay: Double(index) * stagger, duration: base + Double(index) * perColumn)
        }
    }

    /// Posición de la tira en `time` s desde que empezó el cambio: desaceleración cúbica hasta `to + overshoot` (en el
    /// sentido del giro) al 78 % de la duración y, después, un rebote que se apaga hasta `to`.
    public static func position(_ column: DigitColumn, at time: Double, overshoot: Double) -> Double {
        let k = (time - column.delay) / column.duration
        if k <= 0 { return column.from }
        if k >= 1 { return column.to }
        let distance = column.to - column.from
        // Un asentamiento más corto que un dígito se pasa proporcionalmente menos (9,08 → 9 no baja hasta 8,83).
        let over = distance == 0 ? 0 : overshoot * (distance > 0 ? 1 : -1) * min(1, abs(distance))
        if k < 0.78 {
            let u = k / 0.78
            return column.from + (distance + over) * (1 - pow(1 - u, 3))
        }
        let u = (k - 0.78) / 0.22
        return column.to + over * exp(-4 * u) * cos(1.5 * Double.pi * u)
    }

    /// Velocidad de la tira (dígitos por segundo, siempre ≥ 0): decide cuánto se ve la copia desenfocada.
    public static func speed(_ column: DigitColumn, at time: Double, overshoot: Double) -> Double {
        let end = column.delay + column.duration
        guard time > column.delay, time < end else { return 0 }
        let h = 1.0 / 240
        let lo = max(column.delay, time - h), hi = min(end, time + h)
        guard hi > lo else { return 0 }
        return abs(position(column, at: hi, overshoot: overshoot) - position(column, at: lo, overshoot: overshoot)) / (hi - lo)
    }

    /// Cuánto se ve cada columna (0…1) mientras rueda, para que un grupo de millares nunca aparezca como un cero a la
    /// izquierda («0.145,19 €» al abrir el ojo, «0.000,00 €» al empezar a contar): una columna a la izquierda de las
    /// `alwaysShown` últimas (unidades y céntimos: 3; euros enteros: 1) no se dibuja mientras ella y todas las de su
    /// izquierda están en el cero o saliendo de él, y aparece cuando su tira ya enseña sobre todo la cifra siguiente
    /// (de 0,5 a 0,9 dígitos de distancia del cero): así tampoco asoma un «0» tenue al empezar a rodar, ni los ceros de
    /// las columnas de su derecha que aún no han salido. El punto de millar que la sigue lleva su misma opacidad.
    /// Asentado en una cifra de verdad (que no empieza por cero) todo vale 1.
    public static func leadingVisibility(positions: [Double], alwaysShown: Int) -> [Double] {
        let free = max(0, positions.count - max(0, alwaysShown))
        var shown = 0.0
        return positions.enumerated().map { index, position in
            guard index < free else { return 1 }
            let place = mod10(position)
            let away = min(place, 10 - place)
            shown = max(shown, min(1, max(0, (away - 0.5) / 0.4)))
            return shown
        }
    }

    private static func power10(_ n: Int) -> Int {
        var v = 1
        for _ in 0..<n { v *= 10 }
        return v
    }

    private static func mod10(_ x: Double) -> Double {
        let r = x.truncatingRemainder(dividingBy: 10)
        return r < 0 ? r + 10 : r
    }
}

/// Lo que se enseña de un importe oculto. Nada de aquí depende de las cifras del importe: con el modo privado
/// activo no existe ningún camino que dibuje un dígito real.
public enum AmountMask {
    /// «•••,•• €» (con «−» o «+» delante si se pide).
    public static func text(negative: Bool, showsPlus: Bool) -> String {
        (negative ? "−" : (showsPlus ? "+" : "")) + "•••,••\u{00A0}€"
    }

    /// La máscara de un importe en euros enteros: «••• €» (sin decimales, como la cifra a la que sustituye).
    public static func wholeText(negative: Bool, showsPlus: Bool) -> String {
        (negative ? "−" : (showsPlus ? "+" : "")) + "•••\u{00A0}€"
    }

    /// Dígitos al azar (deterministas por semilla y paso) para barajar mientras el ojo cambia. Nunca salen del importe.
    /// El primero es de 1 a 9: un fotograma barajado nunca empieza por un cero suelto («027,44 €»).
    public static func scrambledDigits(count: Int, step: Int, seed: Int) -> [Int] {
        (0..<max(0, count)).map { i in
            var x = UInt64(truncatingIfNeeded: seed) &* 0x9E37_79B9_7F4A_7C15
            x ^= UInt64(truncatingIfNeeded: step &* 7919 &+ i &* 104_729 &+ 1) &* 0xBF58_476D_1CE4_E5B9
            x ^= x >> 31
            x = x &* 0x94D0_49BB_1331_11EB
            x ^= x >> 29
            return i == 0 ? 1 + Int(x % 9) : Int(x % 10)
        }
    }

    /// Al cerrar el ojo, los puntos salen encima del último fotograma del barajado, columna a columna: cada casilla
    /// enseña su punto si ya ha salido (`popped`) y, si no, el dígito al azar del último paso del barajado. Nunca hay
    /// una casilla vacía (el «, €» suelto de antes) ni un dígito del importe. nil = punto.
    public static func closingCells(count: Int, popped: Int, seed: Int, lastStep: Int = 6) -> [Int?] {
        let random = scrambledDigits(count: count, step: lastStep, seed: seed)
        return random.enumerated().map { index, digit in index < popped ? nil : digit }
    }
}
