import XCTest

/// Toques reales sobre el marco y las hojas de la fase de animaciones (línea «Marco y hojas»): el arranque «logo en
/// piezas», el bloqueo, y los importes que ruedan en el detalle y en el resumen. Siempre en modo demo.
final class MotionShellTests: XCTestCase {
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

    private func launch(_ extra: [String] = []) {
        app.launchArguments = ["-MiBancoDemo"] + extra + ["-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func labelled(_ predicate: String, _ argument: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: predicate, argument)).firstMatch
    }

    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return condition()
    }

    private func moneyShaped(_ text: String) -> Bool {
        text.contains("€") || text.contains("euros") || text.range(of: #"\d,\d{2}"#, options: .regularExpression) != nil
    }

    /// Todas las etiquetas y valores con forma de importe que hay ahora en la app.
    private func moneyStrings() -> [String] {
        app.descendants(matching: .any).allElementsBoundByIndex.flatMap { el -> [String] in
            var found: [String] = []
            if moneyShaped(el.label) { found.append("label:\(el.label)") }
            if let value = el.value as? String, moneyShaped(value) { found.append("value:\(value)") }
            return found
        }
    }

    /// Lo que publica la app sobre su arranque (solo DEBUG): «arranques=1;estilo=piezas;saltos=0;libre=963;fin=1344;…».
    private func probe() -> [String: String] {
        let value = element("launch-probe").value as? String ?? ""
        var out: [String: String] = [:]
        for pair in value.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 { out[String(parts[0])] = String(parts[1]) }
        }
        return out
    }

    /// Espera a que la capa del arranque se haya quitado (mientras está, un toque la salta en vez de llegar a Inicio).
    private func waitForLaunchToEnd(_ timeout: TimeInterval = 20) {
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")
        XCTAssertTrue(waitUntil(timeout) { !self.element("launch-layer").exists }, "El arranque no terminó")
    }

    /// Manda la app a segundo plano y la trae de vuelta. Primero con el gesto de Inicio; si a los 4 s el sistema no dice
    /// que la app está en segundo plano (pasó dos veces con dos simuladores en paralelo: la app seguía delante y, claro,
    /// no se bloqueaba), se abre Ajustes, que la manda atrás seguro. Luego espera 1,5 s y la trae de vuelta.
    private func sendToBackgroundAndReturn() {
        func inBackground() -> Bool {
            app.state == .runningBackground || app.state == .runningBackgroundSuspended
        }
        XCUIDevice.shared.press(.home)
        if !waitUntil(4, inBackground) {
            let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
            settings.activate()
            _ = settings.wait(for: .runningForeground, timeout: 20)
            XCTAssertTrue(waitUntil(10, inBackground),
                          "La app no llegó a segundo plano ni con el gesto de Inicio ni abriendo Ajustes (estado \(app.state.rawValue))")
        }
        Thread.sleep(forTimeInterval: 1.5)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "La app no volvió a primer plano")
    }

    /// El carrusel es un único elemento de accesibilidad cuya etiqueta acaba en «N de 4».
    private func carousel() -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES %@", ".* [0-9] de 4$")).firstMatch
    }

    /// Un toque de verdad en Inicio: el ojo cambia de «Ocultar importes» a «Mostrar importes».
    private func assertHomeResponds(_ message: String) {
        // Mientras el bloqueo, ya desbloqueado, se funde (0,3 s a velocidad real), Inicio no recibe toques a propósito:
        // el toque se da cuando el fundido ha terminado, y tiene que terminar.
        XCTAssertTrue(waitUntil(8) { self.probe()["fundido"] != "1" }, "El fundido del bloqueo no termina: \(message)")
        let hide = app.buttons["Ocultar importes"]
        XCTAssertTrue(hide.waitForExistence(timeout: 8), "Falta el ojo: \(message)")
        hide.tap()
        XCTAssertTrue(app.buttons["Mostrar importes"].waitForExistence(timeout: 5), message)
    }

    /// Abre el detalle de la primera fila de Inicio y espera a que la hoja esté arriba.
    private func openFirstRowDetail() {
        waitForLaunchToEnd()
        let row = app.buttons.matching(identifier: "movementRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "No hay filas de movimientos")
        XCTAssertTrue(waitUntil(10) { row.isHittable }, "La primera fila no se puede tocar")
        row.tap()
        XCTAssertTrue(app.buttons["Cerrar"].waitForExistence(timeout: 8), "No se abrió la hoja de detalle")
    }

    // MARK: - C2 · Arranque «logo en piezas»

    /// (a) Sin bloqueo: un toque en cualquier parte salta el arranque y deja Inicio a mano. (b) Con bloqueo: las piezas
    /// se montan EN el bloqueo; mientras dure el bloqueo no existe ninguna capa del arranque ni se ve nada de Inicio, y un
    /// toque en la pantalla termina el dibujo de la marca pero no desbloquea. Al desbloquear, la marca vuela sin estorbar.
    func testLaunchSkippableAndNeverAboveLock() throws {
        // (a) A cámara lenta ×40 el arranque duraría casi un minuto y tardaría 38 s en dejar tocar Inicio.
        launch(["-MiBancoMotionScale", "40"])
        let layer = element("launch-layer")
        XCTAssertTrue(layer.waitForExistence(timeout: 15), "No aparece la capa del arranque")
        XCTAssertEqual(layer.value as? String, "piezas;tocable", "El arranque no es el de piezas o ya no recibe toques")
        XCTAssertEqual(probe()["saltos"], "0")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)).tap()
        // Tras el toque queda una décima de guion (unos 5 s a ×40): si no saltara, la capa seguiría medio minuto más.
        XCTAssertTrue(waitUntil(10) { !layer.exists }, "Un toque no saltó el arranque")
        let skipped = probe()
        XCTAssertEqual(skipped["saltos"], "1", "El toque no contó como salto: \(skipped)")
        XCTAssertEqual(skipped["arranques"], "1")
        assertHomeResponds("Tras saltar el arranque, Inicio no responde")
        app.terminate()

        // (b) Bloqueo de demo de 45 s, también a ×40 (las piezas tardarían 44 s en montarse).
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "45", "-MiBancoMotionScale", "40"])
        let unlock = app.buttons["Desbloquear"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 15), "Falta la pantalla de bloqueo")
        XCTAssertTrue(unlock.isHittable, "El botón de desbloquear no está disponible mientras la marca se monta")
        let mark = element("lock-mark")
        XCTAssertTrue(mark.waitForExistence(timeout: 5), "Falta la marca del bloqueo")
        XCTAssertEqual(mark.value as? String, "piezas", "En el arranque en frío el bloqueo debe montar las piezas")
        // (XCUITest ve los elementos de Inicio aunque estén ocultos a VoiceOver y tapados por el bloqueo; lo que se
        // comprueba es que no se pueden tocar y que ninguna capa del arranque existe.)
        let eye = app.buttons["Ocultar importes"]
        func assertNothingBesidesTheLock(_ moment: String) {
            XCTAssertFalse(element("launch-layer").exists, "\(moment): la capa del arranque existe con el bloqueo puesto")
            XCTAssertFalse(element("launch-exit").exists, "\(moment): la marca vuela con el bloqueo puesto")
            XCTAssertFalse(eye.exists && eye.isHittable, "\(moment): el ojo de Inicio se puede tocar con el bloqueo puesto")
            let title = app.staticTexts["Tu dinero"]
            XCTAssertFalse(title.exists && title.isHittable, "\(moment): Inicio se puede tocar con el bloqueo puesto")
        }
        assertNothingBesidesTheLock("Al aparecer el bloqueo")
        // Un toque de verdad justo donde está el ojo de Inicio (debajo del bloqueo, fuera del botón de desbloquear): la
        // marca del bloqueo queda terminada, el bloqueo sigue ahí y el toque no llega a Inicio (se comprueba al final).
        XCTAssertTrue(eye.exists, "No se encuentra el ojo de Inicio bajo el bloqueo para tocar encima")
        eye.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(waitUntil(5) { (mark.value as? String) == "completa" }, "Un toque no terminó la marca del bloqueo")
        var checks = 0
        while unlock.exists && checks < 10 {
            assertNothingBesidesTheLock("Tras el toque (mirada \(checks))")
            checks += 1
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertEqual(checks, 10, "El toque en la pantalla quitó el bloqueo")
        XCTAssertTrue(unlock.exists, "El toque en la pantalla quitó el bloqueo")
        XCTAssertEqual(probe()["arranques"], "0", "Con bloqueo no debe montarse la capa del arranque")

        // Al acabar el bloqueo de demo la marca echa a volar (a ×40 tarda 17 s) mientras el bloqueo se funde (13 s: su
        // fundido obedece la cámara lenta). Inicio vuelve y responde.
        let exit = element("launch-exit")
        XCTAssertTrue(exit.waitForExistence(timeout: 60), "Tras desbloquear en frío la marca no vuela")
        XCTAssertEqual(exit.value as? String, "frio")
        XCTAssertFalse(element("launch-layer").exists, "Tras desbloquear se montó la capa del arranque")
        // El vuelo (17 s a ×40) dura más que el fundido del bloqueo (13 s): cuando acaba, el bloqueo ya no está.
        XCTAssertTrue(waitUntil(45) { !exit.exists }, "La marca no terminó de volar")
        XCTAssertFalse(unlock.exists, "El bloqueo sigue ahí después del vuelo")
        // El toque de antes no atravesó el bloqueo: el ojo sigue sin haberse tocado.
        XCTAssertTrue(eye.exists, "El toque sobre el bloqueo llegó al ojo de Inicio")
        XCTAssertFalse(app.buttons["Mostrar importes"].exists, "El toque sobre el bloqueo llegó al ojo de Inicio")
        assertHomeResponds("Tras desbloquear, Inicio no responde")
        let after = probe()
        XCTAssertEqual(after["arranques"], "0", "Tras desbloquear se montó la capa del arranque: \(after)")
        XCTAssertEqual(after["salidas"], "1")
        XCTAssertEqual(after["bloqueoPiezas"], "1")
        XCTAssertEqual(after["marcasDobles"], "0", "La marca echó a volar con el bloqueo aún dibujando la suya: \(after)")
    }

    /// Volver de segundo plano no repite el arranque: ni sin bloqueo (no aparece ninguna capa) ni con él (el bloqueo sale
    /// con la marca quieta y, al quitarse, tampoco hay arranque).
    func testWarmResumeShowsNoLaunch() throws {
        launch()
        waitForLaunchToEnd()
        XCTAssertTrue(waitUntil(10) { self.probe()["fin"] != "-" }, "El arranque en frío no llegó a terminar")
        XCTAssertEqual(probe()["arranques"], "1")
        sendToBackgroundAndReturn()
        for look in 0..<12 {
            XCTAssertFalse(element("launch-layer").exists, "Mirada \(look): el arranque se repitió al volver de segundo plano")
            XCTAssertFalse(element("launch-exit").exists, "Mirada \(look): la marca voló al volver de segundo plano")
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertEqual(probe()["arranques"], "1", "El arranque se repitió al volver de segundo plano")
        assertHomeResponds("Al volver de segundo plano, Inicio no responde")
        app.terminate()

        // Con bloqueo (demo, 10 s): arranque en frío con piezas; al volver de segundo plano, marca quieta.
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "10"])
        let unlock = app.buttons["Desbloquear"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 15), "Falta la pantalla de bloqueo del arranque en frío")
        XCTAssertTrue(waitUntil(25) { !unlock.exists }, "El bloqueo de demo no se quitó")
        XCTAssertTrue(waitUntil(8) { !self.element("launch-exit").exists }, "La marca no terminó de volar tras desbloquear")
        let cold = probe()
        XCTAssertEqual(cold["bloqueoPiezas"], "1", "El bloqueo del arranque en frío no montó las piezas: \(cold)")
        XCTAssertEqual(cold["bloqueoQuieto"], "0")
        XCTAssertEqual(cold["salidas"], "1", "Tras desbloquear en frío la marca no voló: \(cold)")
        sendToBackgroundAndReturn()
        XCTAssertTrue(unlock.waitForExistence(timeout: 8), "No se mostró el bloqueo al volver de segundo plano")
        XCTAssertEqual(element("lock-mark").value as? String, "fija", "Al volver de segundo plano la marca del bloqueo debe estar quieta")
        XCTAssertFalse(element("launch-layer").exists, "El arranque se montó con el bloqueo puesto")
        XCTAssertFalse(element("launch-exit").exists, "La marca vuela con el bloqueo puesto")
        XCTAssertTrue(waitUntil(25) { !unlock.exists }, "El re-bloqueo de demo no se quitó")
        XCTAssertFalse(element("launch-layer").exists, "El arranque se repitió tras el re-bloqueo")
        assertHomeResponds("Tras el re-bloqueo, Inicio no responde")
        let warm = probe()
        XCTAssertEqual(warm["arranques"], "0", "El arranque se repitió tras el re-bloqueo: \(warm)")
        XCTAssertEqual(warm["bloqueoPiezas"], "1", "Las piezas se repitieron en el re-bloqueo: \(warm)")
        XCTAssertEqual(warm["bloqueoQuieto"], "1")
    }

    /// A velocidad real y sin tocar nada: la capa del arranque deja tocar Inicio antes de 1,6 s (lo mide la propia app
    /// desde que empieza el arranque) y, cuando se quita, el carrusel está a mano y responde.
    func testLaunchNeverDelaysHome() throws {
        launch()
        let card = carousel()
        XCTAssertTrue(card.waitForExistence(timeout: 15), "No aparece el carrusel de tarjetas")
        XCTAssertTrue(waitUntil(10) { self.probe()["fin"] != "-" }, "El arranque no terminó solo")
        let result = probe()
        XCTAssertEqual(result["arranques"], "1")
        XCTAssertEqual(result["estilo"], "piezas", "El arranque por defecto (Expresivo) debe ser el de piezas: \(result)")
        XCTAssertEqual(result["saltos"], "0")
        let free = try XCTUnwrap(Int(result["libre"] ?? ""), "La app no apuntó cuándo dejó tocar Inicio: \(result)")
        let finished = try XCTUnwrap(Int(result["fin"] ?? ""), "La app no apuntó cuándo se quitó el arranque: \(result)")
        XCTAssertLessThanOrEqual(free, 1_600, "El arranque tardó \(free) ms en dejar tocar Inicio (máximo 1600)")
        XCTAssertGreaterThanOrEqual(free, 700, "El arranque dejó tocar Inicio a los \(free) ms: ¿se saltó solo?")
        // Guion: 1344 ms. El margen es para un simulador de CI cargado, no para el iPhone.
        XCTAssertLessThanOrEqual(finished, 2_000, "El arranque tardó \(finished) ms en quitarse (guion: 1344)")
        XCTAssertFalse(element("launch-layer").exists, "La capa del arranque sigue montada")
        XCTAssertTrue(card.isHittable, "El carrusel no se puede tocar tras el arranque")
        assertHomeResponds("Tras el arranque, Inicio no responde")
    }

    /// En Sutil y con Reducir movimiento el arranque es solo un fundido (sin piezas) y también deja Inicio a mano.
    func testSubtleAndReduceMotionLaunchOnlyFade() throws {
        for arguments in [["-MiBancoMotionLevel", "subtle"], ["-MiBancoReduceMotion"]] {
            launch(arguments)
            waitForLaunchToEnd()
            XCTAssertTrue(waitUntil(10) { self.probe()["fin"] != "-" }, "\(arguments): el arranque no terminó")
            let result = probe()
            XCTAssertEqual(result["estilo"], "fundido", "\(arguments): el arranque debe ser solo un fundido: \(result)")
            let finished = try XCTUnwrap(Int(result["fin"] ?? ""), "\(arguments): sin tiempo de fin: \(result)")
            XCTAssertLessThanOrEqual(finished, 1_200, "\(arguments): el fundido tardó \(finished) ms")
            assertHomeResponds("\(arguments): Inicio no responde tras el fundido")
            app.terminate()
        }
    }

    /// I-2: Face ID suele ser más rápido que las piezas. Si el desbloqueo llega con la marca del bloqueo a medio montar
    /// (aquí a los 0,4 s; a ×50 las piezas tardarían 55 s), el bloqueo empieza a fundirse con la marca ya TERMINADA y la
    /// marca echa a volar una sola vez. Cómo estaba la marca del bloqueo en ese instante lo apunta la propia app
    /// (`marcaAlDesbloquear`); si además XCUITest alcanza a ver el bloqueo mientras se funde (17 s a ×50), su marca
    /// tiene que decir lo mismo. Que no se ven piezas ni dos marcas lo enseñan las hojas `unlock-early` y
    /// `unlock-early-mitad`.
    func testUnlockBeforeThePiecesFinishHandsOverAFinishedMark() throws {
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "0.4", "-MiBancoMotionScale", "50"])
        let exit = element("launch-exit")
        XCTAssertTrue(exit.waitForExistence(timeout: 20), "Tras desbloquear a mitad de las piezas la marca no vuela")
        let result = probe()
        XCTAssertEqual(result["marcaAlDesbloquear"], "completa", "El bloqueo empezó a fundirse con la marca a medias: \(result)")
        let mark = element("lock-mark")
        if mark.exists {
            XCTAssertEqual(mark.value as? String, "completa",
                           "El bloqueo se funde con la marca a medio montar mientras la marca entera ya vuela")
        }
        XCTAssertFalse(element("launch-layer").exists, "Se montó la capa del arranque sin bloqueo")
        XCTAssertEqual(result["bloqueoPiezas"], "1", "El bloqueo no llegó a montar las piezas: \(result)")
        XCTAssertEqual(result["salidas"], "1", "La marca no voló exactamente una vez: \(result)")
        XCTAssertEqual(result["montajes"], "1", "Inicio no se montó exactamente una vez: \(result)")
        XCTAssertEqual(result["marcasDobles"], "0", "La marca echó a volar con el bloqueo aún dibujando la suya: \(result)")
        // El vuelo (21 s a ×50) dura más que el fundido del bloqueo (17 s): cuando acaba, el bloqueo ya no está.
        XCTAssertTrue(waitUntil(45) { !exit.exists }, "La marca no terminó de volar")
        XCTAssertFalse(app.buttons["Desbloquear"].exists, "El bloqueo sigue ahí después del vuelo")
        XCTAssertEqual(probe()["montajes"], "1", "Inicio se volvió a montar: \(probe())")
        assertHomeResponds("Tras desbloquear a mitad de las piezas, Inicio no responde")
    }

    /// I-1: el orden de Face ID en el iPhone — el éxito llega con la escena aún inactiva y solo después vuelve a activa
    /// (aquí lo simula la bandera de demo durante 10 s). Mientras está inactiva: la tapa del selector de apps está
    /// puesta (no antes, encima del bloqueo), Inicio YA ha recibido la orden de montarse (una vez, debajo de la tapa),
    /// no se puede tocar y la marca aún no vuela. Al volver a activa: la tapa se quita, la marca vuela e Inicio NO se
    /// vuelve a montar.
    func testUnlockWhileInactiveBuildsHomeUnderTheCover() throws {
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "12", "-MiBancoDemoUnlockInactive", "10"])
        let unlock = app.buttons["Desbloquear"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 15), "Falta la pantalla de bloqueo")
        let cover = element("privacy-cover")
        XCTAssertFalse(cover.exists, "La tapa del selector de apps está puesta encima del bloqueo")
        XCTAssertEqual(probe()["montajes"], "0", "Inicio se montó antes de desbloquear")
        XCTAssertTrue(cover.waitForExistence(timeout: 15), "Tras desbloquear con la escena inactiva no aparece la tapa")
        let under = probe()
        XCTAssertEqual(under["montajes"], "1", "Con la tapa puesta Inicio aún no ha recibido la orden de montarse: \(under)")
        XCTAssertEqual(under["salidas"], "0", "La marca voló con la escena inactiva: \(under)")
        XCTAssertFalse(element("launch-exit").exists, "La marca vuela con la tapa puesta")
        // Un toque de verdad justo donde está el ojo de Inicio, con la tapa puesta: no puede llegarle (se comprueba
        // cuando la tapa se quita).
        let eye = app.buttons["Ocultar importes"]
        XCTAssertTrue(eye.exists, "No se encuentra el ojo de Inicio bajo la tapa para tocar encima")
        eye.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(cover.exists, "La tapa se quitó con un toque")
        XCTAssertTrue(waitUntil(20) { !cover.exists }, "La tapa no se quitó al volver a primer plano")
        XCTAssertTrue(waitUntil(5) { self.probe()["salidas"] == "1" }, "Al volver a primer plano la marca no voló: \(probe())")
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(probe()["montajes"], "1", "Inicio se volvió a montar al volver a primer plano: \(probe())")
        XCTAssertEqual(probe()["marcasDobles"], "0", "La marca echó a volar con el bloqueo aún dibujando la suya: \(probe())")
        XCTAssertFalse(cover.exists, "La tapa volvió a aparecer")
        XCTAssertTrue(eye.exists, "El toque sobre la tapa llegó al ojo de Inicio")
        XCTAssertFalse(app.buttons["Mostrar importes"].exists, "El toque sobre la tapa llegó al ojo de Inicio")
        assertHomeResponds("Tras volver a primer plano, Inicio no responde")
    }

    /// N-1: el orden más probable en el iPhone — el éxito de Face ID llega con la escena aún inactiva y la escena vuelve a
    /// activa un instante después, ANTES de lo que duraría el fundido del bloqueo (aquí 0,2 s reales; a ×50 el fundido
    /// duraría 17 s). El bloqueo no se queda fundiéndose debajo de la tapa: cuando la marca echa a volar no queda nada
    /// suyo (ni marca, ni lema, ni botón). Lo dice el estado de la app (`fundido`, `marcasDobles`); que no se VEN dos
    /// marcas lo enseña la hoja `unlock-inactive-corto`. (Las comprobaciones de que el botón y la marca del bloqueo no
    /// existen valen poco por sí solas: XCUITest no siempre ve una vista que se está quitando.)
    func testUnlockInactiveForAnInstantNeverShowsTwoMarks() throws {
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "3", "-MiBancoDemoUnlockInactive", "0.2",
                "-MiBancoMotionScale", "50"])
        let unlock = app.buttons["Desbloquear"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 15), "Falta la pantalla de bloqueo")
        let exit = element("launch-exit")
        XCTAssertTrue(exit.waitForExistence(timeout: 20), "Tras desbloquear con la escena inactiva un instante la marca no vuela")
        // La marca acaba de echar a volar: del fundido que habría quedado faltarían unos 17 s.
        let flying = probe()
        XCTAssertEqual(flying["marcasDobles"], "0", "La marca echó a volar con el bloqueo aún fundiéndose con la suya: \(flying)")
        XCTAssertEqual(flying["fundido"], "0", "Queda un bloqueo fundiéndose debajo de la marca que vuela: \(flying)")
        XCTAssertFalse(unlock.exists, "El botón del bloqueo sigue ahí con la marca volando")
        XCTAssertFalse(element("lock-mark").exists, "La marca del bloqueo sigue ahí con la otra volando")
        XCTAssertFalse(element("privacy-cover").exists, "La tapa sigue puesta con la marca volando")
        XCTAssertEqual(flying["salidas"], "1", "La marca no voló exactamente una vez: \(flying)")
        XCTAssertEqual(flying["montajes"], "1", "Inicio no se montó exactamente una vez: \(flying)")
        XCTAssertTrue(waitUntil(45) { !exit.exists }, "La marca no terminó de volar")
        let after = probe()
        XCTAssertEqual(after["marcasDobles"], "0", "\(after)")
        XCTAssertEqual(after["montajes"], "1", "Inicio se volvió a montar: \(after)")
        assertHomeResponds("Tras desbloquear con la escena inactiva un instante, Inicio no responde")
    }

    /// Toque tardío: mientras el bloqueo, ya desbloqueado, se funde, un toque no llega a Inicio. El botón «Desbloquear»
    /// ocupa todo el ancho justo encima de la barra de pestañas: un segundo toque sobre él, ya tarde, cambiaba de
    /// pestaña. A ×80 el fundido dura 27 s: se toca donde estaba el botón, sobre la pestaña Gasto y sobre el ojo de
    /// Inicio; ni cambia la pestaña ni se cierra el ojo. Cuando el fundido termina, Inicio responde.
    /// (En el simulador de CI la barra de pestañas no siempre toma un toque sintético, así que «la pestaña no cambió»
    /// podría pasar por eso; el ojo sí los toma siempre, y es el que hace de testigo.)
    func testLateTapDuringTheUnlockFadeDoesNotReachHome() throws {
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "5", "-MiBancoMotionScale", "80"])
        let unlock = app.buttons["Desbloquear"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 15), "Falta la pantalla de bloqueo")
        let button = unlock.frame
        XCTAssertTrue(button.width > 100 && button.height > 20, "No se sabe dónde está el botón del bloqueo: \(button)")
        XCTAssertTrue(waitUntil(20) { self.probe()["fundido"] == "1" }, "El bloqueo de demo no empezó a fundirse: \(probe())")
        // Ya desbloqueado: Inicio está debajo del bloqueo que se funde.
        let home = app.tabBars.buttons["Inicio"]
        let spending = app.tabBars.buttons["Gasto"]
        let eye = app.buttons["Ocultar importes"]
        XCTAssertTrue(spending.exists && eye.exists, "No se encuentran la barra de pestañas y el ojo de Inicio")
        let tab = spending.frame
        let eyeFrame = eye.frame
        func tap(_ x: CGFloat, _ y: CGFloat) {
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y)).tap()
        }
        // Donde estaba el botón; sobre la pestaña Gasto a la altura del botón; en el centro de la pestaña; en el ojo.
        tap(button.midX, button.midY)
        tap(tab.midX, min(max(tab.midY, button.minY + 2), button.maxY - 2))
        tap(tab.midX, tab.midY)
        tap(eyeFrame.midX, eyeFrame.midY)
        let during = probe()
        XCTAssertEqual(during["fundido"], "1",
                       "Los toques llegaron con el fundido ya terminado: la prueba no dice nada (\(during))")
        XCTAssertTrue(home.isSelected, "Un toque durante el fundido del bloqueo cambió de pestaña")
        XCTAssertFalse(spending.isSelected, "Un toque durante el fundido del bloqueo abrió Gasto")
        XCTAssertTrue(eye.exists, "Un toque durante el fundido del bloqueo llegó al ojo de Inicio")
        XCTAssertFalse(app.buttons["Mostrar importes"].exists, "Un toque durante el fundido del bloqueo llegó al ojo de Inicio")
        // Cuando el fundido termina (y la marca acaba de volar: 34 s a ×80), Inicio vuelve a responder.
        XCTAssertTrue(waitUntil(40) { self.probe()["fundido"] == "0" }, "El fundido del bloqueo no terminó: \(probe())")
        XCTAssertTrue(waitUntil(45) { !self.element("launch-exit").exists }, "La marca no terminó de volar")
        XCTAssertTrue(home.isSelected, "La pestaña cambió sola")
        assertHomeResponds("Terminado el fundido del bloqueo, Inicio no responde")
    }

    // MARK: - C1 · Importes que ruedan en las hojas

    /// El detalle de un movimiento: el importe grande y «Te quedaban» se leen como siempre (una etiqueta cada uno) aunque
    /// ahora rueden, y «Cerrar» sigue cerrando la hoja.
    func testDetailAmountsKeepTheirSpokenLabels() throws {
        launch()
        openFirstRowDetail()
        let amount = labelled("label BEGINSWITH %@", "Pago de ")
        XCTAssertTrue(amount.waitForExistence(timeout: 5), "Falta la etiqueta «Pago de …» del importe")
        XCTAssertTrue(amount.label.hasSuffix(" euros"), "El importe no se lee en euros: «\(amount.label)»")
        let left = labelled("label BEGINSWITH %@", "Te quedaban ")
        XCTAssertTrue(left.waitForExistence(timeout: 5), "Falta «Te quedaban»")
        XCTAssertTrue(left.label.hasSuffix(" euros"), "«Te quedaban» no se lee en euros: «\(left.label)»")
        app.buttons["Cerrar"].tap()
        XCTAssertTrue(waitUntil(8) { !self.app.buttons["Cerrar"].exists }, "La hoja no se cerró")
    }

    /// Con el ojo cerrado, los dos importes del detalle que ahora ruedan (el del movimiento y «Te quedaban») nunca se
    /// leen: sus etiquetas dicen «importe oculto» y ninguna etiqueta ni valor nuevo dice sus cifras («12,50 euros»), ni
    /// mientras la hoja entra (a cámara lenta ×3: el importe rueda y «Te quedaban» se destapa) ni cuando ya está quieta.
    /// Primero se leen las cifras con el ojo abierto. Que tampoco se VEAN lo enseña la hoja de fotogramas
    /// `detail-amount-ojo` (las cifras que ruedan se pintan en un lienzo, sin texto que XCUITest pueda leer).
    /// (XCUITest sí ve los textos que el modo privado difumina y oculta a VoiceOver, como el historial del comercio,
    /// que repite el importe; por eso no se buscan las cifras sueltas.)
    func testDetailAmountsObeyTheEye() throws {
        launch()
        openFirstRowDetail()
        let amount = labelled("label BEGINSWITH %@", "Pago de ")
        XCTAssertTrue(amount.waitForExistence(timeout: 5), "Falta la etiqueta «Pago de …» del importe")
        let left = labelled("label BEGINSWITH %@", "Te quedaban ")
        XCTAssertTrue(left.waitForExistence(timeout: 5), "Falta «Te quedaban»")
        func figure(_ label: String, after prefix: String) -> String {
            String(label.dropFirst(prefix.count)).replacingOccurrences(of: " euros", with: "")
        }
        let figures = [figure(amount.label, after: "Pago de "), figure(left.label, after: "Te quedaban ")]
        for text in figures {
            XCTAssertNotNil(text.range(of: #"^\d[\d.]*,\d{2}$"#, options: .regularExpression), "No es una cifra: «\(text)»")
        }
        app.terminate()

        launch(["-MiBancoDemoPrivate", "-MiBancoMotionScale", "3"])
        waitForLaunchToEnd(30)
        let row = app.buttons.matching(identifier: "movementRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "No hay filas de movimientos")
        XCTAssertTrue(waitUntil(15) { row.isHittable }, "La primera fila no se puede tocar")
        // Lo que dirían los dos importes si se leyeran («12,50 euros»), en etiqueta o en valor.
        func count(_ text: String) -> Int {
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)).count
        }
        let spokenFigures = figures.map { "\($0) euros" }
        let before = spokenFigures.map(count)
        // Las etiquetas del importe y de «Te quedaban» que NO digan «importe oculto».
        let readable = app.descendants(matching: .any).matching(NSPredicate(
            format: "(label BEGINSWITH %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@) AND NOT (label ENDSWITH %@)",
            "Pago de ", "Ingreso de ", "Te quedaban ", "importe oculto"))
        row.tap()
        for pass in 0..<10 {
            XCTAssertEqual(readable.count, 0, "Pasada \(pass): con el ojo cerrado un importe del detalle se lee: «\(readable.firstMatch.label)»")
            for (index, text) in spokenFigures.enumerated() {
                let now = count(text)
                XCTAssertLessThanOrEqual(
                    now, before[index], "Pasada \(pass): con el ojo cerrado el detalle dice «\(text)» (\(now) veces, antes \(before[index]))")
            }
        }
        XCTAssertTrue(app.buttons["Cerrar"].waitForExistence(timeout: 8), "No se abrió la hoja de detalle")
        XCTAssertTrue(labelled("label == %@", "Pago de importe oculto").waitForExistence(timeout: 5),
                      "El importe del detalle no dice «importe oculto»")
        XCTAssertTrue(labelled("label == %@", "Te quedaban importe oculto").exists,
                      "«Te quedaban» no dice «importe oculto»")
    }

    /// La línea del total del resumen sigue leyéndose como UNA frase entera con su importe, aunque el importe ruede
    /// dentro, y es texto (no un botón nuevo ni nada tocable de más).
    func testBriefingTotalIsOneSentence() throws {
        launch(["-MiBancoDemoBriefing", "busy"])
        XCTAssertTrue(app.buttons["Vale"].waitForExistence(timeout: 20), "La hoja del resumen no se abrió")
        let total = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "En total, ", "Sigues con ")).firstMatch
        XCTAssertTrue(total.waitForExistence(timeout: 8), "Falta la frase del total")
        XCTAssertNotNil(total.label.range(of: #"\d,\d{2}\s€"#, options: .regularExpression),
                        "La frase del total no lleva su importe entero: «\(total.label)»")
        app.buttons["Vale"].tap()
        XCTAssertTrue(waitUntil(8) { !self.app.buttons["Vale"].exists }, "La hoja del resumen no se cerró")
    }
}
