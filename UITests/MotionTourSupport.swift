import XCTest

/// Base de los recorridos de movimiento (workflow `motion-video`). Cada animación se juzga con una HOJA DE CONTACTO de
/// fotogramas, nunca con una captura fija: `launch` abre la app a cámara lenta (`-MiBancoMotionScale`, por defecto ×4) y
/// `burst` saca una ráfaga de capturas que el workflow convierte en `build/sheets/<nombre>.png`.
///
/// Uso en una prueba nueva (cada flujo trabaja en su propia subclase, en su propio fichero):
///
///     func testMiMomento() throws {
///         launch(["-MiBancoDemoLock"])            // argumentos extra además de los de la demo
///         // … toca lo que dispara la animación …
///         burst("mi-momento", frames: 16, every: 0.4)
///     }
///
/// Con la escala ×4 una animación de 0,5 s dura 2 s: 16 fotogramas cada 0,4 s (6,4 s) la cubren entera. El nombre de la
/// ráfaga es el de la hoja; usa letras minúsculas, números y guiones.
class MotionTourCase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "Alerta del sistema") { alert in
            for name in ["Permitir", "Allow", "OK", "Aceptar", "Not Now", "Ahora no"] {
                let b = alert.buttons[name]
                if b.exists { b.tap(); return true }
            }
            return false
        }
        app = XCUIApplication()
    }

    /// Abre la app con los argumentos de demo de las demás pruebas de interfaz, `-MiBancoMotionScale <scale>` y los `extra`.
    func launch(_ extra: [String] = [], scale: Double = 4) {
        app.launchArguments = [
            "-MiBancoDemo", "-AppleLanguages", "(es)", "-AppleLocale", "es_ES",
            "-MiBancoMotionScale", String(scale),
        ] + extra
        app.launch()
    }

    /// Saca `frames` capturas, una cada `every` segundos (contadas desde la primera, así que el tiempo que tarda cada
    /// captura no estira el intervalo), y las adjunta a la prueba como «<name>-NN» (NN con dos cifras, desde 01) con
    /// `.keepAlways`: el workflow las exporta del `.xcresult`.
    func burst(_ name: String, frames: Int, every: TimeInterval) {
        XCTAssertGreaterThan(frames, 0, "Una ráfaga necesita al menos un fotograma")
        let start = Date()
        for index in 0..<max(frames, 0) {
            let due = start.addingTimeInterval(Double(index) * every)
            let wait = due.timeIntervalSinceNow
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            let attachment = XCTAttachment(screenshot: app.screenshot(), quality: .original)
            attachment.name = "\(name)-" + String(format: "%02d", index + 1)
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
