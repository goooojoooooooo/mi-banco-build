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

    /// Lote 3 (0): desbloquear en Sutil (a ×8: el fundido dura 2,4 s). Nada vuela: el bloqueo se funde con su marca
    /// grande e Inicio aparece debajo SIN la marca de su barra, que sale de una vez al acabar el fundido. Una marca
    /// por fotograma.
    func testUnlockSubtle() throws {
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "8", "-MiBancoMotionLevel", "subtle"], scale: 8)
        try sleepUntilLaunchStarts(lead: -7.7)
        burst("unlock-sutil", frames: 18, every: 0.2)
    }

    /// Lo mismo con Reducir movimiento (a ×8: el fundido dura 1,8 s).
    func testUnlockReduceMotion() throws {
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "8", "-MiBancoReduceMotion"], scale: 8)
        try sleepUntilLaunchStarts(lead: -7.7)
        burst("unlock-reducir", frames: 18, every: 0.2)
    }

    /// I-2, como pide la revisión: el bloqueo de demo se quita a los 0,4 s de empezar las piezas (a ×8 apenas han
    /// asomado). El bloqueo se funde (2,7 s a ×8) ya sin piezas ni líneas y la marca entera vuela: nunca dos marcas.
    func testUnlockEarly() throws {
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "0.4", "-MiBancoDemoLaunchHold", "25"], scale: 8)
        try sleepUntilLaunchStarts(lead: 0.3)
        burst("unlock-early", frames: 36, every: 0.2)
    }

    /// I-2 en su peor momento: el desbloqueo llega con las dos mitades en el aire entre las líneas (2,4 s a ×8 = 0,27 s
    /// del guion).
    func testUnlockMidFlight() throws {
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "2.4", "-MiBancoDemoLaunchHold", "25"], scale: 8)
        try sleepUntilLaunchStarts(lead: 0.3)
        burst("unlock-early-mitad", frames: 44, every: 0.2)
    }

    /// I-1: el éxito de Face ID llega con la escena aún inactiva (la bandera lo simula durante 2 s). El bloqueo deja
    /// paso a la tapa de golpe (nunca los dos a medias), Inicio se monta debajo y, al volver a activa, la tapa se quita
    /// de golpe y la marca vuela sobre un Inicio que no vuelve a empezar de cero.
    func testUnlockWhileInactive() throws {
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "12", "-MiBancoDemoUnlockInactive", "2"])
        try sleepUntilLaunchStarts(lead: -11.6)
        burst("unlock-inactive", frames: 30, every: 0.2)
    }

    /// N-1: lo mismo, pero la escena vuelve a activa a los 0,2 s reales del desbloqueo, mucho antes de lo que duraría el
    /// fundido del bloqueo (2,7 s a ×8; la bandera no va a cámara lenta). El bloqueo no se funde debajo de la tapa: al
    /// quitarse la tapa no queda nada suyo y solo hay una marca, la que vuela.
    func testUnlockInactiveForAnInstant() throws {
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "14", "-MiBancoDemoUnlockInactive", "0.2"], scale: 8)
        try sleepUntilLaunchStarts(lead: -13.7)
        burst("unlock-inactive-corto", frames: 30, every: 0.2)
    }

    /// Re-bloqueo (volver de segundo plano): la marca sale quieta y entera, sin piezas (`lock-rebloqueo`, con el bloqueo
    /// en reposo: si el bloqueo de demo cumple su tiempo con la app detrás, no se acepta y vuelve a durar 10 s desde la
    /// vuelta). Después, el desbloqueo templado a ×8 (`unlock-templado`): el bloqueo se funde y la marca vuela, sin
    /// bandas, hasta la ranura de la barra de Inicio.
    func testRelockIsStatic() throws {
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "10"], scale: 8)
        let unlock = app.buttons["Desbloquear"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 20), "Falta la pantalla de bloqueo")
        XCTAssertTrue(waitUntil(30) { !unlock.exists }, "El bloqueo de demo no se quitó")
        // El vuelo en frío (3,4 s a ×8) termina antes de salir.
        Thread.sleep(forTimeInterval: 6)
        XCUIDevice.shared.press(.home)
        if !waitUntil(4, { self.app.state == .runningBackground || self.app.state == .runningBackgroundSuspended }) {
            // Con el simulador cargado el gesto de Inicio a veces no saca la app: Ajustes la manda atrás seguro.
            let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
            settings.activate()
            _ = settings.wait(for: .runningForeground, timeout: 20)
        }
        Thread.sleep(forTimeInterval: 1.5)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "La app no volvió a primer plano")
        XCTAssertTrue(unlock.waitForExistence(timeout: 8), "No se mostró el bloqueo al volver de segundo plano")
        burst("lock-rebloqueo", frames: 6, every: 0.3)
        XCTAssertTrue(unlock.exists, "El bloqueo se quitó durante la ráfaga: no estaba en reposo")
        // El bloqueo de demo se quita solo: se captura desde que empieza a fundirse.
        XCTAssertTrue(waitUntil(25) { self.probe()["fundido"] == "1" }, "El re-bloqueo de demo no se quitó")
        burst("unlock-templado", frames: 24, every: 0.2)
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
        // Más abajo, el historial del comercio: con el ojo cerrado sus importes son máscaras, no cifras difuminadas.
        app.swipeUp()
        burst("detail-ojo-historial", frames: 2, every: 0.5)
    }

    /// El valor de una posición rueda al abrir su hoja.
    func testPositionAmount() throws {
        launch(["-MiBancoDemoPosition"])
        XCTAssertTrue(app.buttons["Cerrar"].waitForExistence(timeout: 30), "No se abrió la hoja de la posición")
        burst("position-amount", frames: 12, every: 0.3)
    }

    /// La hoja de una posición con el ojo cerrado: el valor es la máscara y, más abajo, los datos y las operaciones
    /// también (máscaras, no texto difuminado).
    func testPositionWithTheEyeClosed() throws {
        launch(["-MiBancoDemoPosition", "-MiBancoDemoPrivate"])
        XCTAssertTrue(app.buttons["Cerrar"].waitForExistence(timeout: 30), "No se abrió la hoja de la posición")
        burst("position-amount-ojo", frames: 6, every: 0.3)
        app.swipeUp()
        burst("position-ojo-abajo", frames: 2, every: 0.5)
    }

    /// El resumen con el ojo cerrado: ninguna cifra en ninguna línea.
    func testBriefingWithTheEyeClosed() throws {
        launch(["-MiBancoDemoBriefing", "busy", "-MiBancoDemoPrivate"])
        XCTAssertTrue(app.buttons["Vale"].waitForExistence(timeout: 30), "La hoja del resumen no se abrió")
        burst("briefing-total-ojo", frames: 8, every: 0.3)
    }

    /// El total del resumen rueda dentro de su frase.
    func testBriefingTotal() throws {
        launch(["-MiBancoDemoBriefing", "busy"])
        XCTAssertTrue(app.buttons["Vale"].waitForExistence(timeout: 30), "La hoja del resumen no se abrió")
        burst("briefing-total", frames: 12, every: 0.3)
    }
}
