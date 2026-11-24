import XCTest

/// Ráfagas de movimiento del flujo «Marco y hojas» (nadie más edita este fichero): el arranque «logo en piezas» fotograma
/// a fotograma (entero, saltado con un toque, en Sutil, con Reducir movimiento y con el ojo cerrado), las piezas sobre el
/// bloqueo, la salida al desbloquear y los importes que ruedan en las hojas.
///
/// El arranque empieza en cuanto se abre la app, antes de que una prueba pueda hacer su primera captura. Por eso las
/// ráfagas del arranque piden a la app que espere unos segundos en negro (`-MiBancoDemoLaunchHold`, solo DEBUG) y leen
/// de ella cuándo empieza (`launch-probe` → `empieza=`), para capturar desde justo antes del primer fotograma.
final class MotionTourShellTests: MotionTourCase {

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func probe() -> [String: String] {
        let value = element("launch-probe").value as? String ?? ""
        var out: [String: String] = [:]
        for pair in value.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 { out[String(parts[0])] = String(parts[1]) }
        }
        return out
    }

    private func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return condition()
    }

    /// Duerme hasta `lead` segundos antes (o `-lead` después) de que empiece el arranque que la app tiene en espera
    /// (o las piezas del bloqueo).
    private func sleepUntilLaunchStarts(lead: TimeInterval) throws {
        var startsAt: Double?
        XCTAssertTrue(waitUntil(20) {
            startsAt = Double(self.probe()["empieza"] ?? "")
            return startsAt != nil
        }, "La app no publicó cuándo empieza el arranque")
        let start = try XCTUnwrap(startsAt)
        let wait = start - lead - Date().timeIntervalSince1970
        XCTAssertGreaterThan(wait, 0, "La espera del arranque se quedó corta: ya había empezado (\(wait) s)")
        if wait > 0 { Thread.sleep(forTimeInterval: wait) }
    }

    private func waitForLaunchToEnd() {
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 20), "Inicio no aparece")
        XCTAssertTrue(waitUntil(30) { !self.element("launch-layer").exists }, "El arranque no terminó")
    }

    // MARK: - Arranque

    /// El arranque entero a ×4 (5,4 s): piezas y líneas, loseta y nombre, brillo, bandas, vuelo e Inicio montándose.
    func testLaunch() throws {
        launch(["-MiBancoDemoLaunchHold", "25"])
        try sleepUntilLaunchStarts(lead: 0.3)
        burst("launch", frames: 24, every: 0.25)
    }

    /// Lo mismo con el ojo cerrado: Inicio se monta debajo sin enseñar una cifra.
    func testLaunchWithTheEyeClosed() throws {
        launch(["-MiBancoDemoLaunchHold", "25", "-MiBancoDemoPrivate"])
        try sleepUntilLaunchStarts(lead: 0.3)
        burst("launch-ojo", frames: 24, every: 0.25)
    }

    /// Un toque a mitad de las piezas (a ×16, para que el salto dure lo bastante para verlo): tres fotogramas antes del
    /// toque y, después, la marca ya entera volando a su sitio.
    func testLaunchSkip() throws {
        launch(["-MiBancoDemoLaunchHold", "25"], scale: 16)
        try sleepUntilLaunchStarts(lead: -3.5)
        burst("launch-skip-antes", frames: 3, every: 0.3)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).tap()
        burst("launch-skip", frames: 12, every: 0.2)
    }

    /// Nivel Sutil: solo un fundido (0,28 s; a ×4, 1,1 s).
    func testLaunchSubtle() throws {
        launch(["-MiBancoDemoLaunchHold", "25", "-MiBancoMotionLevel", "subtle"])
        try sleepUntilLaunchStarts(lead: 0.3)
        burst("launch-sutil", frames: 10, every: 0.18)
    }

    /// Reducir movimiento: la marca aparece con un fundido e Inicio se funde (0,52 s; a ×4, 2,1 s).
    func testLaunchReduceMotion() throws {
        launch(["-MiBancoDemoLaunchHold", "25", "-MiBancoReduceMotion"])
        try sleepUntilLaunchStarts(lead: 0.3)
        burst("launch-reducir", frames: 12, every: 0.25)
    }

    // MARK: - Bloqueo

    /// Arranque en frío con bloqueo: las piezas se montan sobre la marca del bloqueo (a ×4, 4,4 s); el botón está desde
    /// el primer fotograma.
    func testLockAssembles() throws {
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "60", "-MiBancoDemoLaunchHold", "25"])
        try sleepUntilLaunchStarts(lead: 0.3)
        burst("lock", frames: 24, every: 0.22)
    }

    /// Al desbloquear en frío (a ×8, 3,4 s): el bloqueo se funde, las bandas cruzan, la marca vuela hacia la barra
    /// superior e Inicio se monta. Desbloquea el temporizador del bloqueo de demo (el botón pediría el código del iPhone).
    func testUnlockFlight() throws {
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "14"], scale: 8)
        // El bloqueo de demo se quita a los 14 s de montarse, o algo después (las piezas, a ×8, tardan 8,8 s): se
        // empieza a capturar justo antes y se cubren 6 s.
        try sleepUntilLaunchStarts(lead: -13.7)
        burst("unlock", frames: 30, every: 0.2)
    }

    /// Re-bloqueo (volver de segundo plano): la marca sale quieta y entera, sin piezas.
    func testRelockIsStatic() throws {
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "10"])
        let unlock = app.buttons["Desbloquear"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 20), "Falta la pantalla de bloqueo")
        XCTAssertTrue(waitUntil(30) { !unlock.exists }, "El bloqueo de demo no se quitó")
        Thread.sleep(forTimeInterval: 3)
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(waitUntil(15) { self.app.state == .runningBackground || self.app.state == .runningBackgroundSuspended },
                      "La app no llegó a segundo plano")
        Thread.sleep(forTimeInterval: 1.5)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "La app no volvió a primer plano")
        burst("lock-rebloqueo", frames: 6, every: 0.3)
    }

    // MARK: - Importes que ruedan en las hojas

    /// Fila → detalle a ×4: el importe grande entra y rueda; «Te quedaban» empieza oculto y rueda cuando el importe se posa.
    func testDetailAmounts() throws {
        launch()
        waitForLaunchToEnd()
        let row = app.buttons.matching(identifier: "movementRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "No hay filas de movimientos")
        row.tap()
        burst("detail-amount", frames: 24, every: 0.33)
        // «No es mío»: la raya sobre el importe.
        app.swipeUp()
        let flag = app.buttons["No es mío"]
        XCTAssertTrue(flag.waitForExistence(timeout: 5), "Falta la acción «No es mío»")
        flag.tap()
        app.swipeDown()
        burst("detail-flagged", frames: 3, every: 0.5)
    }

    /// Lo mismo con el ojo cerrado: ni una cifra en ningún fotograma.
    func testDetailAmountsWithTheEyeClosed() throws {
        launch(["-MiBancoDemoPrivate"])
        waitForLaunchToEnd()
        let row = app.buttons.matching(identifier: "movementRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "No hay filas de movimientos")
        row.tap()
        burst("detail-amount-ojo", frames: 24, every: 0.33)
    }

    /// El valor de una posición rueda al abrir su hoja.
    func testPositionAmount() throws {
        launch(["-MiBancoDemoPosition"])
        XCTAssertTrue(app.buttons["Cerrar"].waitForExistence(timeout: 30), "No se abrió la hoja de la posición")
        burst("position-amount", frames: 12, every: 0.3)
    }

    /// El total del resumen rueda dentro de su frase.
    func testBriefingTotal() throws {
        launch(["-MiBancoDemoBriefing", "busy"])
        XCTAssertTrue(app.buttons["Vale"].waitForExistence(timeout: 30), "La hoja del resumen no se abrió")
        burst("briefing-total", frames: 12, every: 0.3)
    }
}
