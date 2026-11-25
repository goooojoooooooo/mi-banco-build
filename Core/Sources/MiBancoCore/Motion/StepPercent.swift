import Foundation

/// El porcentaje de un proceso por pasos (conectar un banco: Verificar › Conectar › Importar; importar un extracto:
/// Leer › Revisar › Importar). Nunca es un reloj inventado: sigue el paso REAL en el que está el trabajo.
///
/// - Cada paso tiene un tope (34, 67, 99). Mientras el paso sigue en marcha, la cifra se acerca a su tope cada vez más
///   despacio y NUNCA lo alcanza (como mucho, tope − 1): llegar al 34 % quiere decir que el primer paso terminó de verdad.
/// - Al entrar en el paso siguiente arranca exactamente en el tope del anterior.
/// - 100 solo con `succeed()` (el trabajo acabó bien). `fail(shown:)` deja la cifra congelada donde estaba.
/// - Nunca baja: dentro de un paso solo crece con el tiempo y un paso no vuelve atrás.
///
/// Es un valor puro: quien lo dibuja le pasa los segundos que lleva el paso en curso (ya divididos por la cámara lenta).
public struct StepPercent: Equatable, Sendable {
    /// Los topes aprobados en la maqueta («Conectando tu banco»).
    public static let defaultCaps = [34, 67, 99]
    /// Segundos en los que la cifra recorre el 63 % de lo que le falta hasta el tope (rápido al principio, luego frena).
    public static let timeConstant = 0.42

    public enum Outcome: Equatable, Sendable {
        case running
        case succeeded
        /// Congelado en esta cifra.
        case failed(Int)
    }

    public let caps: [Int]
    /// Índice del paso en curso (0 = el primero).
    public private(set) var step = 0
    public private(set) var outcome = Outcome.running

    /// `caps`: topes crecientes entre 1 y 99; si no lo son, se usan los aprobados.
    public init(caps: [Int] = StepPercent.defaultCaps) {
        let valid = !caps.isEmpty && caps.allSatisfy { (1...99).contains($0) } && zip(caps, caps.dropFirst()).allSatisfy { $0 < $1 }
        self.caps = valid ? caps : StepPercent.defaultCaps
    }

    /// Desde dónde cuenta el paso en curso: 0 en el primero y el tope del anterior en los demás.
    public var floor: Int { step == 0 ? 0 : caps[step - 1] }

    /// El tope del paso en curso.
    public var cap: Int { caps[step] }

    public var isRunning: Bool { outcome == .running }

    /// La cifra a los `elapsed` segundos de empezar el paso en curso. En marcha: de `floor` hacia `cap`, sin tocarlo.
    public func value(elapsed: Double) -> Int {
        switch outcome {
        case .succeeded: return 100
        case .failed(let frozen): return frozen
        case .running:
            let ceiling = cap - 1
            guard ceiling > floor else { return floor }
            guard elapsed.isFinite else { return elapsed == .infinity ? ceiling : floor }
            let t = max(0, elapsed)
            let fraction = 1 - exp(-t / StepPercent.timeConstant)
            let raw = Double(floor) + Double(ceiling - floor) * fraction
            // Al entero más cercano: así llega a tope − 1 en un par de segundos en vez de quedarse un punto por debajo.
            return min(ceiling, max(floor, Int(raw.rounded(.toNearestOrAwayFromZero))))
        }
    }

    /// Pasa al paso `index` (el anterior terminó de verdad). Solo hacia delante y solo en marcha; fuera de rango, el último.
    public mutating func enter(step index: Int) {
        guard isRunning else { return }
        let target = min(max(index, 0), caps.count - 1)
        guard target > step else { return }
        step = target
    }

    /// El trabajo acabó bien: 100.
    public mutating func succeed() {
        guard isRunning else { return }
        outcome = .succeeded
    }

    /// El trabajo falló: la cifra se queda en `shown` (lo que se veía), acotada a lo que el paso podía enseñar.
    public mutating func fail(shown: Int) {
        guard isRunning else { return }
        outcome = .failed(min(cap - 1, max(floor, shown)))
    }
}
