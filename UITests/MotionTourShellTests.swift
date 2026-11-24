import XCTest

/// Ráfagas de movimiento del flujo «Marco y hojas» (lo rellena su flujo de trabajo; nadie más edita este fichero).
/// Por ahora solo una prueba de relleno que demuestra la tubería: abre la app y saca dos fotogramas.
final class MotionTourShellTests: MotionTourCase {
    func testPlaceholder() throws {
        launch()
        Thread.sleep(forTimeInterval: 2)
        burst("placeholder-shell", frames: 2, every: 0.5)
    }
}
