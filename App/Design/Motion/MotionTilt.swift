import CoreMotion
import SwiftUI

/// La inclinación física del iPhone, para que la tarjeta de delante acompañe a la mano (±2°) y su brillo y su canto se
/// desplacen. `x` (izquierda–derecha) e `y` (adelante–atrás; 0 = el teléfono a unos 45°) van de −1 a 1, ya suavizados.
/// - CoreMotion a 30 Hz, y SOLO entre `start()` y `stop()`: Inicio lo arranca cuando está a la vista, con la app en
///   primer plano y con efectos ricos (ni Reducir movimiento ni Bajo consumo), y lo para en cuanto deja de cumplirse.
/// - Zona muerta: con el teléfono quieto no se publica nada, así que nada se redibuja.
/// - En el simulador no hay sensores: se queda en 0 y el brillo sigue solo al carrusel.
@MainActor @Observable final class MotionTilt {
    private(set) var x: Double = 0
    private(set) var y: Double = 0

    /// Se crea al empezar a leer (uno solo), no al crear este objeto.
    @ObservationIgnored private var manager: CMMotionManager?
    @ObservationIgnored private var running = false
    #if DEBUG
    @ObservationIgnored private var sweep: Task<Void, Never>?
    #endif

    /// Empieza a leer la inclinación (no hace nada si ya lee o si el aparato no tiene sensores).
    func start() {
        guard !running else { return }
        let manager = self.manager ?? CMMotionManager()
        self.manager = manager
        guard manager.isDeviceMotionAvailable else { return }
        running = true
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let gravity = motion?.gravity else { return }
            let gx = gravity.x, gy = gravity.y, gz = gravity.z
            // La cola es la principal: se entra en el actor principal sin saltar de hilo.
            MainActor.assumeIsolated { self.ingest(gx: gx, gy: gy, gz: gz) }
        }
    }

    /// Deja de leer y devuelve la tarjeta a su sitio.
    func stop() {
        if running {
            manager?.stopDeviceMotionUpdates()
            running = false
        }
        #if DEBUG
        sweep?.cancel()
        sweep = nil
        #endif
        if x != 0 { x = 0 }
        if y != 0 { y = 0 }
    }

    /// De la gravedad a dos ángulos: `gamma` (ladeo) y `beta` (0 tumbado boca arriba, 90 de pie). ±25° llenan el rango.
    private func ingest(gx: Double, gy: Double, gz: Double) {
        let gamma = asin(max(-1, min(1, gx))) * 180 / .pi
        let beta = atan2(-gy, -gz) * 180 / .pi
        aim(x: gamma / 25, y: (beta - 45) / 25)
    }

    private func aim(x targetX: Double, y targetY: Double) {
        let tx = max(-1, min(1, targetX))
        let ty = max(-1, min(1, targetY))
        let nx = x + (tx - x) * 0.22
        let ny = y + (ty - y) * 0.22
        if abs(nx - x) > 0.004 { x = nx }
        if abs(ny - y) > 0.004 { y = ny }
    }

    #if DEBUG
    /// Solo demo (`-MiBancoDemoCardMoment tilt`): barre la inclinación unos segundos y vuelve a 0, para poder verla en
    /// fotogramas sin giroscopio. Se para sola y también con `stop()`.
    func demoSweep(seconds: Double = 6) {
        sweep?.cancel()
        sweep = Task { [weak self] in
            let start = Date()
            while !Task.isCancelled {
                let t = Date().timeIntervalSince(start)
                guard t < seconds, let self else { break }
                self.x = sin(t * 2 * .pi / 3)
                self.y = 0.6 * sin(t * 2 * .pi / 4.5)
                try? await Task.sleep(for: .milliseconds(33))
            }
            guard !Task.isCancelled, let self else { return }
            self.x = 0
            self.y = 0
        }
    }
    #endif
}

extension EnvironmentValues {
    /// La inclinación que mueve la tarjeta de delante y su brillo; `nil` (por defecto) = todo quieto.
    @Entry var cardTilt: MotionTilt? = nil
}

/// Gira un poco la tarjeta con la inclinación: ±2° por eje (× el recorrido del nivel, con tope ×1,3). Solo esta pieza
/// lee la inclinación, así que 30 lecturas por segundo no vuelven a evaluar la tarjeta. Sin efectos ricos, quieta.
struct TiltedCard: ViewModifier {
    let active: Bool
    @Environment(\.cardTilt) private var tilt
    @Environment(\.motion) private var motion

    func body(content: Content) -> some View {
        let on = active && motion.richEffects
        let range = 2 * min(1.3, motion.level.distanceScale)
        let lean = TiltLean(x: on ? (tilt?.x ?? 0) : 0, y: on ? (tilt?.y ?? 0) : 0)
        content
            .rotation3DEffect(.degrees(lean.x * range), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .rotation3DEffect(.degrees(-lean.y * range), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            // Suaviza entre lecturas (30 por segundo en una pantalla de 120).
            .animation(.linear(duration: 0.08), value: lean)
    }
}

private struct TiltLean: Equatable {
    var x: Double
    var y: Double
}
