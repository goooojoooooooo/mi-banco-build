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

    /// Dígitos al azar (deterministas por semilla y paso) para barajar mientras el ojo cambia. Nunca salen del importe.
    public static func scrambledDigits(count: Int, step: Int, seed: Int) -> [Int] {
        (0..<max(0, count)).map { i in
            var x = UInt64(truncatingIfNeeded: seed) &* 0x9E37_79B9_7F4A_7C15
            x ^= UInt64(truncatingIfNeeded: step &* 7919 &+ i &* 104_729 &+ 1) &* 0xBF58_476D_1CE4_E5B9
            x ^= x >> 31
            x = x &* 0x94D0_49BB_1331_11EB
            x ^= x >> 29
            return Int(x % 10)
        }
    }
}
