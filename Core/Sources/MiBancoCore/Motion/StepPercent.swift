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

    /// Segundos (del kit) en los que, al acabar bien, la cifra corre desde la que se veía hasta 100 (maqueta: el remate).
    public static let finishSeconds = 0.25

    public let caps: [Int]
    /// Índice del paso en curso (0 = el primero).
    public private(set) var step = 0
    public private(set) var outcome = Outcome.running
    /// Desde qué cifra corre hasta 100 al acabar bien: la que se veía (100 si no se dijo, es decir, de golpe).
    public private(set) var finishFrom = 100

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

    /// El trabajo acabó bien y en pantalla se veía `shown`: la cifra corre de ahí a 100 en `finishSeconds` (ver
    /// `drawn`). Es la cifra REAL que se veía, acotada a lo que el paso podía enseñar; nunca un paso inventado.
    public mutating func succeed(shown: Int) {
        guard isRunning else { return }
        finishFrom = min(cap - 1, max(floor, shown))
        outcome = .succeeded
    }

    /// Lo que se DIBUJA. `elapsed`: segundos (ya divididos por la cámara lenta) desde que empezó el paso en curso o, si
    /// ya acabó bien, desde que acabó.
    /// - En marcha: `value(elapsed:)`; con Reducir movimiento no cuenta y enseña el suelo del paso.
    /// - Acabado bien: de `finishFrom` a 100 en `finishSeconds`, frenando, y 100 justo al final (con Reducir, 100).
    /// - Fallo: la cifra congelada.
    public func drawn(elapsed: Double, reduce: Bool) -> Int {
        switch outcome {
        case .failed(let frozen):
            return frozen
        case .running:
            return reduce ? floor : value(elapsed: elapsed)
        case .succeeded:
            guard !reduce, finishFrom < 100 else { return 100 }
            guard elapsed.isFinite else { return elapsed == .infinity ? 100 : finishFrom }
            let x = min(1, max(0, elapsed / StepPercent.finishSeconds))
            let eased = 1 - pow(1 - x, 3)
            // Hacia abajo: 100 solo cuando el remate ha terminado (a la vez que el ✓ del último paso).
            return min(100, finishFrom + Int((Double(100 - finishFrom) * eased).rounded(.down)))
        }
    }

    /// El trabajo falló: la cifra se queda en `shown` (lo que se veía), acotada a lo que el paso podía enseñar.
    public mutating func fail(shown: Int) {
        guard isRunning else { return }
        outcome = .failed(min(cap - 1, max(floor, shown)))
    }
}
