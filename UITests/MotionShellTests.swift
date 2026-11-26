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

    /// Manda la app a segundo plano y la trae de vuelta, y comprueba CON LA PROPIA APP que el viaje ocurrió: su escena
    /// pasó por segundo plano (`fondos` sube) y ha vuelto a activa (`escena=activa`). Solo entonces sigue la prueba.
    ///
    /// Por qué así (runs 45429333172 y 45502319593, dos simuladores en paralelo): el gesto de Inicio
    /// (`XCUIDevice.press(.home)`) no mandó la app atrás en 4 s ninguna de las dos veces; se abrió Ajustes como plan B,
    /// la app volvió… y no había bloqueo. Un gesto de Inicio que llega tarde (después de traer la app de vuelta) la manda
    /// otra vez atrás, y desde fuera nada lo distinguía. Ahora el camino es Ajustes (sin gesto de Inicio que pueda llegar
    /// tarde) y, si aun así la app dice que no pasó por segundo plano o no está activa, el viaje se repite (hasta tres).
    private func sendToBackgroundAndReturn() {
        func inBackground() -> Bool {
            app.state == .runningBackground || app.state == .runningBackgroundSuspended
        }
        func backgrounds() -> Int { Int(probe()["fondos"] ?? "") ?? 0 }
        let before = backgrounds()
        var tries: [String] = []
        for attempt in 1...3 {
            let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
            settings.activate()
            _ = settings.wait(for: .runningForeground, timeout: 20)
            if !waitUntil(10, inBackground) {
                // Último recurso: el gesto de Inicio (y se espera a que surta efecto antes de volver).
                XCUIDevice.shared.press(.home)
                _ = waitUntil(10, inBackground)
            }
            Thread.sleep(forTimeInterval: 1.5)
            app.activate()
            // Un intento que no vuelve a primer plano no es aún un fallo (re-revisión, nota 5): lo dirá el último.
            guard app.wait(for: .runningForeground, timeout: 15) else {
                tries.append("intento \(attempt): no volvió a primer plano (estado \(app.state.rawValue))")
                continue
            }
            if waitUntil(10, { self.probe()["escena"] == "activa" && backgrounds() > before }) { return }
            tries.append("intento \(attempt): estado \(app.state.rawValue), \(probe())")
        }
        XCTFail("La app no pasó por segundo plano y de vuelta a activa en tres intentos: \(tries)")
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
        // Mientras vuela la marca del arranque, la barra de Inicio no dibuja la suya ni su nombre (nunca dos marcas).
        XCTAssertEqual(probe()["ranura"], "marcaYNombre", "La barra de Inicio dibuja su marca durante el arranque: \(probe())")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)).tap()
        // Tras el toque queda una décima de guion (unos 5 s a ×40): si no saltara, la capa seguiría medio minuto más.
        XCTAssertTrue(waitUntil(10) { !layer.exists }, "Un toque no saltó el arranque")
        let skipped = probe()
        XCTAssertEqual(skipped["saltos"], "1", "El toque no contó como salto: \(skipped)")
        XCTAssertEqual(skipped["arranques"], "1")
        XCTAssertEqual(skipped["ranura"], "-", "Terminado el arranque, la barra de Inicio no dibuja su marca: \(skipped)")
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
        // D-9: el bloqueo puesto SÍ está a la vista de VoiceOver (lo apunta el mismo modificador que lo esconde al irse).
        XCTAssertEqual(probe()["vozBloqueo"], "visible", "El bloqueo puesto no está a la vista de VoiceOver: \(probe())")
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
        // Con la marca volando (17 s a ×40), la barra de Inicio no dibuja la suya.
        XCTAssertEqual(probe()["ranura"], "marca", "La barra de Inicio dibuja su marca mientras la otra vuela: \(probe())")
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
        // La marca aterrizó en la ranura de la barra de Inicio y, ya en reposo, la ranura dibuja la suya.
        XCTAssertEqual(after["aterrizajes"], "1", "La marca no aterrizó en la ranura de Inicio: \(after)")
        XCTAssertEqual(after["ranura"], "-", "La marca de la barra se quedó escondida tras el vuelo: \(after)")
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

        // Con bloqueo (demo, 15 s: margen para que el re-bloqueo siga ahí aunque el viaje a segundo plano tenga que
        // repetirse): arranque en frío con piezas; al volver de segundo plano, marca quieta.
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "15"])
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
        // El desbloqueo templado también lleva la marca a su ranura (sin bandas) y la deja a la vista.
        XCTAssertTrue(waitUntil(8) { !self.element("launch-exit").exists }, "La marca no terminó de volar tras el re-bloqueo")
        let landed = probe()
        XCTAssertEqual(landed["salidas"], "2", "Tras el re-bloqueo la marca no voló a su ranura: \(landed)")
        XCTAssertEqual(landed["aterrizajes"], "2", "\(landed)")
        XCTAssertEqual(landed["ranura"], "-", "La marca de la barra se quedó escondida: \(landed)")
        XCTAssertEqual(landed["marcaAntes"], "fija", "\(landed)")
        XCTAssertEqual(landed["marcasDobles"], "0", "\(landed)")
    }

    /// D-10: un desbloqueo que llega con la app YA en segundo plano no se acepta (si se aceptara, la app se quedaría
    /// desbloqueada sin ningún paso posterior por segundo plano que la volviera a bloquear). Aquí el bloqueo de demo
    /// cumple su tiempo (10 s) mientras la app está detrás: la app apunta que rechazó ese desbloqueo; al volver, el
    /// bloqueo sigue delante con su botón, nada de Inicio se puede tocar e Inicio no ha recibido la orden de montarse.
    /// Después se quita por su cuenta (el «vuelve a pedirlo» de la demo: otros 10 s desde la vuelta) y todo responde.
    func testUnlockArrivingInTheBackgroundKeepsTheLock() throws {
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "10"])
        func inBackground() -> Bool {
            app.state == .runningBackground || app.state == .runningBackgroundSuspended
        }
        let unlock = app.buttons["Desbloquear"]
        // La app se manda atrás con el bloqueo aún delante: si ya se hubiera quitado, la prueba no diría nada.
        guard unlock.exists, probe()["montajes"] == "0" else {
            return XCTFail("El bloqueo de demo se quitó antes de mandar la app a segundo plano: prueba no concluyente (\(probe()))")
        }
        XCUIDevice.shared.press(.home)
        if !waitUntil(2, inBackground) {
            let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
            settings.activate()
            _ = settings.wait(for: .runningForeground, timeout: 20)
        }
        XCTAssertTrue(waitUntil(10, inBackground), "La app no llegó a segundo plano")
        // El temporizador del bloqueo de demo cumple (10 s desde que se montó) con la app detrás.
        Thread.sleep(forTimeInterval: 13)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "La app no volvió a primer plano")
        XCTAssertTrue(unlock.waitForExistence(timeout: 5), "Al volver, el bloqueo ya no está: se desbloqueó en segundo plano")
        let back = probe()
        XCTAssertNotEqual(back["rechazados"], "0",
                          "Ningún desbloqueo llegó con la app en segundo plano: prueba no concluyente (\(back))")
        XCTAssertEqual(back["montajes"], "0", "La app se desbloqueó estando en segundo plano: \(back)")
        XCTAssertEqual(back["salidas"], "0", "\(back)")
        XCTAssertEqual(back["fundido"], "0", "\(back)")
        XCTAssertTrue(unlock.isHittable, "El botón del bloqueo no está disponible al volver")
        let eye = app.buttons["Ocultar importes"]
        XCTAssertFalse(eye.exists && eye.isHittable, "Inicio se puede tocar con el bloqueo puesto")
        // Sigue bloqueado (el bloqueo de demo vuelve a durar 10 s desde la vuelta) y luego se va solo.
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(unlock.exists, "El bloqueo se quitó nada más volver")
        XCTAssertEqual(probe()["montajes"], "0", "\(probe())")
        XCTAssertTrue(waitUntil(25) { !unlock.exists }, "El bloqueo de demo no se quitó tras volver a primer plano")
        XCTAssertTrue(waitUntil(8) { !self.element("launch-exit").exists }, "La marca no terminó de volar")
        let after = probe()
        XCTAssertEqual(after["montajes"], "1", "Inicio no se montó exactamente una vez: \(after)")
        assertHomeResponds("Tras desbloquear al volver, Inicio no responde")
        // Y la regla de siempre sigue en pie: otra vez atrás, otra vez bloqueado.
        sendToBackgroundAndReturn()
        XCTAssertTrue(unlock.waitForExistence(timeout: 8), "Tras desbloquear y volver a salir, la app no se bloqueó")
    }

    /// A velocidad real y sin tocar nada: la capa del arranque deja tocar Inicio antes de 1,6 s (lo mide la propia app
    /// desde que empieza el arranque) y, cuando se quita, el carrusel está a mano y responde. Además, desde fuera: el
    /// cronómetro de la prueba, desde `app.launch()` hasta que el carrusel se puede tocar (incluye abrir la app en el
    /// simulador: la cota es holgada), y lo que tardó la capa en EMPEZAR desde que se creó la app (`previo`).
    func testLaunchNeverDelaysHome() throws {
        let began = Date()
        launch()
        let card = carousel()
        XCTAssertTrue(card.waitForExistence(timeout: 15), "No aparece el carrusel de tarjetas")
        XCTAssertTrue(waitUntil(15) { card.isHittable && !self.element("launch-layer").exists },
                      "El carrusel no llegó a poder tocarse")
        let outside = Date().timeIntervalSince(began)
        // Abrir la app en un simulador de CI tarda varios segundos por sí solo; en el iPhone es menos de uno.
        XCTAssertLessThanOrEqual(outside, 25, "Desde app.launch() hasta poder tocar el carrusel pasaron \(outside) s")
        XCTAssertTrue(waitUntil(10) { self.probe()["fin"] != "-" }, "El arranque no terminó solo")
        let result = probe()
        let before = try XCTUnwrap(Int(result["previo"] ?? ""), "La app no apuntó cuánto tardó en empezar el arranque: \(result)")
        XCTAssertLessThanOrEqual(before, 3_000, "El arranque tardó \(before) ms en empezar desde que se creó la app (\(outside) s desde fuera)")
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
    /// marca echa a volar una sola vez. La app apunta cómo estaba la marca del bloqueo en el instante del desbloqueo
    /// (`marcaAntes`: tiene que ser «piezas», o la prueba no ha desbloqueado a mitad del montaje y no dice nada) y cómo
    /// la deja el bloqueo al irse (`marcaAlIrse`: «completa»); el bloqueo que se funde (17 s a ×50) tiene que decir lo
    /// mismo, y la barra de Inicio no dibuja su marca mientras la otra vuela. Que no se ven piezas ni dos marcas lo
    /// enseñan las hojas `unlock-early` y `unlock-early-mitad`.
    func testUnlockBeforeThePiecesFinishHandsOverAFinishedMark() throws {
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "0.4", "-MiBancoMotionScale", "50"])
        let exit = element("launch-exit")
        XCTAssertTrue(exit.waitForExistence(timeout: 20), "Tras desbloquear a mitad de las piezas la marca no vuela")
        let result = probe()
        XCTAssertEqual(result["marcaAntes"], "piezas",
                       "El desbloqueo no llegó con la marca a medio montar: la prueba no dice nada (\(result))")
        XCTAssertEqual(result["marcaAlIrse"], "completa", "El bloqueo empezó a fundirse con la marca a medias: \(result)")
        // A ×50 el bloqueo tarda 17 s en fundirse: sigue ahí, y su marca tiene que estar terminada.
        // (XCUITest no ve una vista que se está quitando —lo comprobó el run 45473585871—, así que esta mirada solo
        // cuenta si llega a verla; el testigo firme es `marcaAlIrse`.)
        let mark = element("lock-mark")
        if mark.exists {
            XCTAssertEqual(mark.value as? String, "completa",
                           "El bloqueo se funde con la marca a medio montar mientras la marca entera ya vuela")
        }
        XCTAssertEqual(result["fundido"], "1", "El bloqueo no se está fundiendo: \(result)")
        XCTAssertEqual(result["ranura"], "marca", "La barra de Inicio dibuja su marca mientras la otra vuela: \(result)")
        // D-9: mientras se funde, VoiceOver ya no ve el bloqueo ni puede activar «Desbloquear». XCUITest no ve una vista
        // que se está quitando (así que mirar el botón no puede fallar): la app apunta el valor que el bloqueo da a su
        // `accessibilityHidden` en el instante del desbloqueo, y antes de desbloquear decía «visible».
        XCTAssertEqual(result["vozBloqueo"], "oculto", "VoiceOver aún ve el bloqueo que se funde: \(result)")
        let fadingButton = app.buttons["Desbloquear"]
        XCTAssertFalse(fadingButton.exists && fadingButton.isHittable, "El botón del bloqueo que se funde aún se puede tocar")
        XCTAssertFalse(element("launch-layer").exists, "Se montó la capa del arranque sin bloqueo")
        XCTAssertEqual(result["bloqueoPiezas"], "1", "El bloqueo no llegó a montar las piezas: \(result)")
        XCTAssertEqual(result["salidas"], "1", "La marca no voló exactamente una vez: \(result)")
        XCTAssertEqual(result["montajes"], "1", "Inicio no se montó exactamente una vez: \(result)")
        XCTAssertEqual(result["marcasDobles"], "0", "La marca echó a volar con el bloqueo aún dibujando la suya: \(result)")
        // El vuelo (21 s a ×50) dura más que el fundido del bloqueo (17 s): cuando acaba, el bloqueo ya no está.
        XCTAssertTrue(waitUntil(45) { !exit.exists }, "La marca no terminó de volar")
        XCTAssertFalse(app.buttons["Desbloquear"].exists, "El bloqueo sigue ahí después del vuelo")
        XCTAssertEqual(probe()["montajes"], "1", "Inicio se volvió a montar: \(probe())")
        XCTAssertEqual(probe()["ranura"], "-", "La marca de la barra se quedó escondida tras el vuelo: \(probe())")
        XCTAssertEqual(probe()["aterrizajes"], "1", "La marca no aterrizó en la ranura de Inicio: \(probe())")
        assertHomeResponds("Tras desbloquear a mitad de las piezas, Inicio no responde")
    }

    /// Lote 3 (0): en Sutil y con Reducir movimiento nada vuela al desbloquear; el bloqueo se funde con su marca grande.
    /// Mientras se funde, la ranura de la marca de la barra de Inicio no se dibuja (`ranuraBloqueo=1`) y la app no
    /// apunta ninguna vez «dos marcas»; al acabar el fundido la ranura vuelve. A ×20 el fundido dura 4–6 s.
    func testFadingUnlockShowsOneMark() throws {
        for arguments in [["-MiBancoMotionLevel", "subtle"], ["-MiBancoReduceMotion"]] {
            launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "3", "-MiBancoMotionScale", "20"] + arguments)
            let unlock = app.buttons["Desbloquear"]
            XCTAssertTrue(unlock.waitForExistence(timeout: 15), "\(arguments): falta el bloqueo")
            XCTAssertTrue(waitUntil(20) { self.probe()["fundido"] == "1" }, "\(arguments): el bloqueo no empezó a fundirse")
            let fading = probe()
            XCTAssertEqual(fading["salidas"], "0", "\(arguments): con solo fundidos la marca no debe volar: \(fading)")
            XCTAssertEqual(fading["ranuraBloqueo"], "1",
                           "\(arguments): la ranura de Inicio dibuja su marca mientras el bloqueo se funde con la suya: \(fading)")
            XCTAssertEqual(fading["marcasDobles"], "0", "\(arguments): dos marcas durante el fundido: \(fading)")
            XCTAssertTrue(waitUntil(20) { self.probe()["fundido"] == "0" }, "\(arguments): el fundido no terminó")
            let done = probe()
            XCTAssertEqual(done["ranuraBloqueo"], "0", "\(arguments): la ranura se quedó escondida: \(done)")
            XCTAssertEqual(done["ranura"], "-", "\(arguments): \(done)")
            XCTAssertEqual(done["marcasDobles"], "0", "\(arguments): \(done)")
            XCTAssertFalse(unlock.exists, "\(arguments): el bloqueo sigue ahí")
            app.terminate()
        }
    }

    /// I-1: el orden de Face ID en el iPhone — el éxito llega con la escena aún inactiva y solo después vuelve a activa
    /// (aquí lo simula la bandera de demo durante 10 s). Mientras está inactiva: la tapa del selector de apps está
    /// puesta (no antes, encima del bloqueo), Inicio YA ha recibido la orden de montarse (una vez, debajo de la tapa),
    /// no se puede tocar y la marca aún no vuela. Al volver a activa: la tapa se quita, la marca vuela e Inicio NO se
    /// vuelve a montar.
    func testUnlockWhileInactiveBuildsHomeUnderTheCover() throws {
        // A ×8: el vuelo de la marca dura 3,4 s, lo bastante para verlo desde fuera cuando la tapa se quita (la ventana
        // «inactiva» son segundos reales).
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "12", "-MiBancoDemoUnlockInactive", "10",
                "-MiBancoMotionScale", "8"])
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
        // Con la tapa puesta, del bloqueo no queda nada (se quitó de golpe: no se funde debajo) y la barra de Inicio
        // dibuja su marca (aún no vuela ninguna).
        XCTAssertFalse(unlock.exists, "El botón del bloqueo sigue debajo de la tapa")
        XCTAssertEqual(probe()["fundido"], "0", "Hay un bloqueo fundiéndose debajo de la tapa: \(probe())")
        XCTAssertEqual(probe()["ranura"], "-", "\(probe())")
        XCTAssertTrue(waitUntil(20) { !cover.exists }, "La tapa no se quitó al volver a primer plano")
        // La marca echa a volar AL quitarse la tapa, no antes: ahora sí existe (3,4 s a ×8) y la barra esconde la suya.
        let exit = element("launch-exit")
        XCTAssertTrue(exit.waitForExistence(timeout: 3), "Al volver a primer plano la marca no vuela")
        XCTAssertEqual(probe()["ranura"], "marca", "La barra de Inicio dibuja su marca mientras la otra vuela: \(probe())")
        XCTAssertTrue(waitUntil(5) { self.probe()["salidas"] == "1" }, "Al volver a primer plano la marca no voló: \(probe())")
        XCTAssertTrue(waitUntil(12) { !exit.exists }, "La marca no terminó de volar")
        XCTAssertEqual(probe()["ranura"], "-", "La marca de la barra se quedó escondida tras el vuelo: \(probe())")
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
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "8", "-MiBancoDemoUnlockInactive", "0.2",
                "-MiBancoMotionScale", "50"])
        let unlock = app.buttons["Desbloquear"]
        let exit = element("launch-exit")
        XCTAssertTrue(exit.waitForExistence(timeout: 25), "Tras desbloquear con la escena inactiva un instante la marca no vuela")
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
    /// pestaña. A ×50 (el tope de la cámara lenta) el fundido dura 17 s: se toca donde estaba el botón, sobre la pestaña Gasto y sobre el ojo de
    /// Inicio; ni cambia la pestaña ni se cierra el ojo. Cuando el fundido termina, Inicio responde.
    /// (En el simulador de CI la barra de pestañas no siempre toma un toque sintético, así que «la pestaña no cambió»
    /// podría pasar por eso; el ojo sí los toma siempre, y es el que hace de testigo.)
    func testLateTapDuringTheUnlockFadeDoesNotReachHome() throws {
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "14", "-MiBancoMotionScale", "50"])
        let unlock = app.buttons["Desbloquear"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 12), "Falta la pantalla de bloqueo")
        let button = unlock.frame
        XCTAssertTrue(button.width > 100 && button.height > 20, "No se sabe dónde está el botón del bloqueo: \(button)")
        XCTAssertTrue(waitUntil(25) { self.probe()["fundido"] == "1" }, "El bloqueo de demo no empezó a fundirse: \(probe())")
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
        // Cuando el fundido termina (y la marca acaba de volar: 21 s a ×50), Inicio vuelve a responder.
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
        // «Te quedaban» solo dice algo de su importe cuando el de arriba se ha posado (C4): se espera a que lo diga.
        XCTAssertTrue(labelled("label == %@", "Te quedaban importe oculto").waitForExistence(timeout: 10),
                      "«Te quedaban» no dice «importe oculto»")
    }

    /// B2 (ronda 1 del lote 3): al escuchar el resumen, la línea que suena se resalta y va cambiando con la voz (en la
    /// demo la voz es simulada: 1,6 s por línea; en el iPhone manda el progreso real). Con el ojo cerrado la voz no lee
    /// ninguna línea, así que no se resalta ninguna y la hoja no enseña ninguna cifra mientras «habla».
    func testSpokenLineIsHighlighted() throws {
        launch(["-MiBancoDemoBriefing", "busy"])
        let listen = app.buttons["briefing-listen"]
        XCTAssertTrue(listen.waitForExistence(timeout: 30), "Falta «Escuchar»")
        XCTAssertEqual(listen.value as? String, "-", "Antes de escuchar ya hay una línea resaltada")
        listen.tap()
        XCTAssertTrue(waitUntil(8) { (listen.value as? String) == "headline" },
                      "La primera línea leída no es la frase principal: «\(listen.value as? String ?? "nil")»")
        // Lote final: lo DIBUJADO (la vista que pinta el resalte), no solo el modelo.
        XCTAssertTrue(waitUntil(5) { (self.element("briefing-drawn-line").value as? String) == "headline" },
                      "La frase principal suena pero no se dibuja resaltada")
        XCTAssertTrue(waitUntil(8) { let v = listen.value as? String ?? "-"; return v != "headline" && v != "-" },
                      "La línea resaltada no avanza con la voz: «\(listen.value as? String ?? "nil")»")
        let next = listen.value as? String ?? "-"
        XCTAssertTrue(waitUntil(5) { (self.element("briefing-drawn-line").value as? String) == next || (self.element("briefing-drawn-line").value as? String) == listen.value as? String },
                      "La línea que suena («\(next)») no es la que se dibuja resaltada")
        listen.tap()
        XCTAssertTrue(waitUntil(5) { (listen.value as? String) == "-" }, "Al parar sigue resaltada una línea")
        XCTAssertTrue(waitUntil(5) { (self.element("briefing-drawn-line").value as? String) == "-" }, "Al parar sigue dibujado un resalte")
        app.terminate()

        launch(["-MiBancoDemoBriefing", "busy", "-MiBancoDemoPrivate"])
        let privateListen = app.buttons["briefing-listen"]
        XCTAssertTrue(privateListen.waitForExistence(timeout: 30), "Falta «Escuchar» con el ojo cerrado")
        privateListen.tap()
        let sheet = app.scrollViews["briefing-scroll"]
        for pass in 0..<6 {
            XCTAssertEqual(privateListen.value as? String, "-", "Pasada \(pass): con el ojo cerrado se resalta una línea")
            XCTAssertEqual((element("briefing-drawn-line").value as? String), "-", "Pasada \(pass): con el ojo cerrado se dibuja un resalte")
            let leaks = sheet.descendants(matching: .any)
                .matching(NSPredicate(format: "label MATCHES %@", #".*(\d,\d{2}|\d\.\d{3}|\d\s*€|\d\s*euros).*"#)).count
            XCTAssertEqual(leaks, 0, "Pasada \(pass): con el ojo cerrado la hoja enseña cifras mientras habla")
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    /// I-2 (ronda 1 del lote 3): el ojo de la app se copia en la suite compartida del grupo de apps al arrancar y al
    /// cambiar (para la extensión de avisos y la Live Activity), y el estado de la Live Activity se sigue leyendo sin la
    /// clave nueva. Que la extensión y la Live Activity dibujen máscaras solo lo confirma el iPhone.
    func testTheEyeIsSharedWithTheExtensions() throws {
        launch(["-MiBancoDemoPrivate"])
        waitForLaunchToEnd(30)
        XCTAssertTrue(waitUntil(10) { self.probe()["ojoCompartido"] == "cerrado" },
                      "Al arrancar con el ojo cerrado la suite compartida no lo dice: \(probe())")
        XCTAssertEqual(probe()["estadoViejo"], "ok", "El estado de la Live Activity no se lee sin la clave nueva: \(probe())")
        let show = app.buttons["Mostrar importes"]
        XCTAssertTrue(show.waitForExistence(timeout: 8), "Falta el ojo cerrado de Inicio")
        XCTAssertTrue(waitUntil(8) { show.isHittable }, "El ojo no se puede tocar")
        show.tap()
        XCTAssertTrue(waitUntil(10) { self.probe()["ojoCompartido"] == "abierto" },
                      "Al abrir el ojo la suite compartida no cambia: \(probe())")
        app.buttons["Ocultar importes"].tap()
        XCTAssertTrue(waitUntil(10) { self.probe()["ojoCompartido"] == "cerrado" },
                      "Al cerrar el ojo la suite compartida no cambia: \(probe())")
    }

    /// C6: el aviso dentro de la app. (a) Con el bloqueo delante llega un pago (la demo lo mete a los ~4 s): no aparece
    /// ningún aviso mientras dura el bloqueo, ni después (no se guarda). (b) Sin bloqueo, en Gasto: el aviso cae, se
    /// puede tocar y abre la hoja del movimiento (la única hoja), y nunca es una hoja él mismo. (c) Con el ojo cerrado,
    /// el aviso no tiene ningún texto con forma de importe. (d) Ir a segundo plano lo quita y no vuelve.
    func testInAppBannerNeverAboveLock() throws {
        let banner = element("in-app-banner")
        // (a)
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "18", "-MiBancoDemoArrival", "-MiBancoDemoScreen", "gasto"])
        let unlock = app.buttons["Desbloquear"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 15), "Falta el bloqueo")
        var looks = 0
        while unlock.exists && looks < 120 {
            XCTAssertFalse(banner.exists, "Mirada \(looks): el aviso dentro de la app está con el bloqueo delante")
            looks += 1
            Thread.sleep(forTimeInterval: 0.2)
        }
        // El pago llega a los ~4 s del arranque; el bloqueo dura 18 s: se mira bastante rato con el bloqueo puesto.
        XCTAssertGreaterThan(looks, 25, "El bloqueo se quitó antes de que llegara el pago: la prueba no dice nada")
        // Lote final: el pago llegó de verdad con el bloqueo delante (si no, la parte (a) no probaría nada).
        XCTAssertGreaterThanOrEqual(Int(probe()["llegadasBloqueo"] ?? "") ?? 0, 1,
                                    "El pago no llegó con el bloqueo delante: \(probe())")
        XCTAssertTrue(waitUntil(30) { !unlock.exists }, "El bloqueo de demo no se quitó")
        for look in 0..<15 {
            XCTAssertFalse(banner.exists, "Mirada \(look): el aviso pedido con el bloqueo apareció al desbloquear")
            Thread.sleep(forTimeInterval: 0.2)
        }
        app.terminate()

        // (b) y (d)
        launch(["-MiBancoDemoArrival", "-MiBancoDemoScreen", "gasto"])
        XCTAssertTrue(banner.waitForExistence(timeout: 20), "No apareció el aviso dentro de la app en Gasto")
        XCTAssertFalse(app.buttons["Cerrar"].exists, "El aviso no debe ser una hoja")
        let open = element("in-app-banner-open")
        XCTAssertTrue(open.waitForExistence(timeout: 3), "El aviso no se puede tocar")
        open.tap()
        XCTAssertTrue(app.buttons["Cerrar"].waitForExistence(timeout: 8), "Tocar el aviso no abrió la hoja del movimiento")
        XCTAssertTrue(waitUntil(5) { !banner.exists }, "El aviso sigue puesto con la hoja abierta")
        app.terminate()

        launch(["-MiBancoDemoArrival", "-MiBancoDemoScreen", "gasto", "-MiBancoMotionScale", "6"])
        XCTAssertTrue(banner.waitForExistence(timeout: 30), "No apareció el aviso dentro de la app (×6)")
        sendToBackgroundAndReturn()
        for look in 0..<10 {
            XCTAssertFalse(banner.exists, "Mirada \(look): el aviso sigue (o vuelve) tras pasar por segundo plano")
            Thread.sleep(forTimeInterval: 0.2)
        }
        app.terminate()

        // (c)
        // A ×12 el aviso dura ~44 s: las ocho miradas caben con él puesto (a ×6 se recogía a mitad de una mirada y la
        // lectura elemento a elemento fallaba, run 45623451092). Cada mirada es UNA consulta con predicado.
        launch(["-MiBancoDemoArrival", "-MiBancoDemoScreen", "gasto", "-MiBancoDemoPrivate", "-MiBancoMotionScale", "12"])
        XCTAssertTrue(banner.waitForExistence(timeout: 40), "No apareció el aviso con el ojo cerrado")
        let money = #".*(\d,\d{2}|\d\.\d{3}|\d\s*€|€\s*\d|\d\s*euros).*"#
        XCTAssertGreaterThan(banner.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "importe oculto")).count, 0,
                             "El aviso no dice «importe oculto»: ¿estaba vacío?")
        var looked = 0
        for pass in 0..<8 where banner.exists {
            let leaks = banner.descendants(matching: .any)
                .matching(NSPredicate(format: "label MATCHES %@ OR value MATCHES %@", money, money)).count
            XCTAssertEqual(leaks, 0, "Pasada \(pass): con el ojo cerrado el aviso tiene \(leaks) textos con cifras")
            looked += 1
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertGreaterThanOrEqual(looked, 6, "El aviso se fue antes de poder mirarlo: la prueba no dice nada")
    }

    /// Ronda 1 (I-1 carcasa): a todos los niveles (Expresivo, Sutil, Reducir) el fundido del bloqueo, que destapa
    /// Inicio, empieza cuando el nombre, el lema y el botón ya se han ido; y la barra de pestañas se destapa después
    /// (M-1). Sondas `textosFuera`, `fundidoBloqueo` y `barraDestapada` (s desde 1970). A ×20.
    func testLockTextsLeaveBeforeTheLockFades() throws {
        for extra in [[], ["-MiBancoMotionLevel", "subtle"], ["-MiBancoReduceMotion"]] {
            launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "3", "-MiBancoMotionScale", "20"] + extra)
            XCTAssertTrue(app.buttons["Desbloquear"].waitForExistence(timeout: 15), "\(extra): falta el bloqueo")
            XCTAssertTrue(waitUntil(60) { (self.probe()["textosFuera"] ?? "-") != "-" }, "\(extra): no se desbloqueó")
            let p = probe()
            let gone = Double(p["textosFuera"] ?? "") ?? 0
            let fade = Double(p["fundidoBloqueo"] ?? "") ?? 0
            XCTAssertGreaterThanOrEqual(fade, gone - 0.001,
                                        "\(extra): el bloqueo empieza a fundirse con los textos aún a la vista: \(p)")
            XCTAssertTrue(waitUntil(60) { (self.probe()["barraDestapada"] ?? "-") != "-" },
                          "\(extra): la barra no se destapó: \(probe())")
            let bar = Double(probe()["barraDestapada"] ?? "") ?? 0
            XCTAssertGreaterThanOrEqual(bar - gone, 0.05 * 20,
                                        "\(extra): la barra se destapa sin dar tiempo a que se vaya el botón: \(probe())")
            app.terminate()
        }
    }

    /// Ronda 1 (M-2): si «No es mío» desde el aviso no se puede guardar (`-MiBancoDemoNotMineFails`), el aviso se
    /// queda y avisa del error (sonda `noEsMioFallos`; VoiceOver dice «No se ha podido. Inténtalo otra vez.»).
    func testInAppBannerNotMineFailureIsNotSilent() throws {
        launch(["-MiBancoDemoArrival", "-MiBancoDemoScreen", "gasto", "-MiBancoMotionScale", "12", "-MiBancoDemoNotMineFails"])
        let banner = element("in-app-banner")
        XCTAssertTrue(banner.waitForExistence(timeout: 40), "No apareció el aviso dentro de la app")
        XCTAssertTrue(waitUntil(40) { self.probe()["accionesAviso"] == "1" }, "El aviso no terminó de desplegarse")
        XCTAssertEqual(probe()["noEsMioFallos"], "0")
        banner.buttons["No es mío"].tap()
        XCTAssertTrue(waitUntil(5) { self.probe()["noEsMioFallos"] == "1" }, "El fallo de «No es mío» no se avisa: \(probe())")
        XCTAssertTrue(banner.exists, "El aviso se fue como si «No es mío» se hubiera guardado")
    }

    /// Ronda 1 (I-3 carcasa): en Gasto, desplazado hasta abajo, la última categoría queda ENTERA por encima del negro
    /// de la barra de cristal (`tab-bar-fade`, solo en DEBUG).
    func testSpendingLastRowClearsTheTabBarFade() throws {
        launch(["-MiBancoDemoScreen", "gasto"])
        XCTAssertTrue(element("gasto.total").waitForExistence(timeout: 30), "No se ve Gasto")
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "gasto.fila."))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "Gasto no tiene categorías")
        for _ in 0..<12 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)),
                       withVelocity: 800, thenHoldForDuration: 0.1)
        }
        Thread.sleep(forTimeInterval: 1)
        let fade = element("tab-bar-fade")
        XCTAssertTrue(fade.exists, "Falta el negro de la barra en Gasto")
        let last = rows.allElementsBoundByIndex.max { $0.frame.maxY < $1.frame.maxY }
        let bottom = try XCTUnwrap(last).frame.maxY
        XCTAssertLessThanOrEqual(bottom, fade.frame.minY + 1,
                                 "La última categoría queda bajo el negro de la barra (\(bottom) > \(fade.frame.minY))")
    }

    /// Ronda 1 (kit I-6): al desconectar los auriculares (`-MiBancoDemoRouteChange`) la voz que lee el resumen se para
    /// y no vuelve sola.
    func testTheVoiceStopsWhenTheHeadphonesGo() throws {
        launch(["-MiBancoDemoBriefing", "busy", "-MiBancoDemoRouteChange", "3"])
        let listen = app.buttons["briefing-listen"]
        XCTAssertTrue(listen.waitForExistence(timeout: 30), "Falta «Escuchar»")
        listen.tap()
        XCTAssertTrue(waitUntil(5) { (listen.value as? String) != "-" }, "La voz no empezó")
        XCTAssertTrue(waitUntil(10) { (listen.value as? String) == "-" && listen.label == "Escuchar" },
                      "Con los auriculares desconectados la voz sigue: «\(listen.label)» «\(listen.value as? String ?? "")»")
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(listen.label, "Escuchar", "La voz volvió sola")
    }

    /// Ronda 1 (kit I-5 / m-13): si el resumen llega tarde (`-MiBancoDemoBriefingDelay`), la hoja abierta no enseña
    /// nada ni empieza su entrada hasta que llega; entonces la entrada empieza y sus bloques aparecen.
    func testBriefingEntranceStartsWhenTheBriefingArrives() throws {
        launch(["-MiBancoDemoBriefing", "busy", "-MiBancoDemoBriefingDelay", "5"])
        let entrance = element("briefing-entrance")
        XCTAssertTrue(entrance.waitForExistence(timeout: 30), "La hoja del resumen no se abrió")
        XCTAssertEqual(entrance.value as? String, "0", "La entrada empezó sin resumen")
        XCTAssertFalse(app.buttons["Vale"].exists, "Se ve el resumen antes de llegar")
        XCTAssertTrue(waitUntil(15) { (entrance.value as? String) == "1" }, "Al llegar el resumen no empezó la entrada")
        XCTAssertTrue(app.buttons["Vale"].waitForExistence(timeout: 10), "Llegó el resumen pero la hoja sigue en blanco")
    }

    /// Las coordenadas de la app (para tocar un punto exacto, no un elemento).
    private func at(_ point: CGPoint) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y))
    }

    /// N-2 (ronda 1 de avisos). Lo que SÍ se puede probar aquí: mientras el aviso se despliega sus botones no reciben
    /// toques (sonda `accionesAviso`, que refleja el `allowsHitTesting` de los botones) y, desplegado del todo, «Añadir
    /// nota» abre la hoja con un toque de verdad. Un toque A MITAD del despliegue no se puede dar con XCUITest: espera a
    /// que la app quede quieta antes de tocar (run 45725015309: al llegar el toque la sonda ya decía «desplegado»), así
    /// que ese caso va a la lista del iPhone. A ×12 el aviso cae en ~11 s y se despliega en ~6 s.
    func testInAppBannerActionsWaitForTheUnfold() throws {
        launch(["-MiBancoDemoArrival", "-MiBancoDemoScreen", "gasto", "-MiBancoMotionScale", "12"])
        let banner = element("in-app-banner")
        XCTAssertTrue(banner.waitForExistence(timeout: 40), "No apareció el aviso dentro de la app")
        XCTAssertTrue(waitUntil(40) { self.probe()["desplegandoAviso"] == "1" }, "El aviso no empezó a desplegarse")
        XCTAssertEqual(probe()["accionesAviso"], "0", "Los botones reciben toques mientras el aviso se despliega")
        XCTAssertTrue(waitUntil(20) { self.probe()["accionesAviso"] == "1" }, "El aviso no terminó de desplegarse")
        XCTAssertFalse(app.buttons["Cerrar"].exists, "Ya había una hoja abierta")
        banner.buttons["Añadir nota"].tap()
        XCTAssertTrue(app.buttons["Cerrar"].waitForExistence(timeout: 15), "Desplegado, «Añadir nota» no abrió la hoja")
    }

    /// N-1 (ronda 1 de avisos: un toque que falla si el defecto vuelve): desplegado, el aviso tapa el chevron «‹» de mes
    /// de Gasto. Un toque en un punto del chevron que queda bajo el relleno visible del aviso (fuera de sus botones) no
    /// cambia el mes ni abre nada. Control: cuando el aviso se ha ido solo, el MISMO punto sí cambia el mes (si el punto
    /// no cayera sobre el chevron, la prueba tampoco pasa).
    func testInAppBannerTakesOnlyVisibleTouches() throws {
        launch(["-MiBancoDemoArrival", "-MiBancoDemoScreen", "gasto", "-MiBancoMotionScale", "12"])
        let banner = element("in-app-banner")
        let month = element("gasto.mes")
        let previous = element("gasto.mesAnterior")
        XCTAssertTrue(month.waitForExistence(timeout: 30), "Falta el mes de Gasto")
        XCTAssertTrue(banner.waitForExistence(timeout: 40), "No apareció el aviso dentro de la app")
        let monthBefore = month.label
        XCTAssertTrue(waitUntil(40) { self.probe()["accionesAviso"] == "1" }, "El aviso no terminó de desplegarse")
        // El marco del elemento es la tarjeta. Se deja 5 pt dentro de su borde (un toque justo en el borde, x = 10 en
        // run 45729245328, puede caer fuera de la tarjeta y entonces SÍ debe pasar a Gasto).
        let bannerFrame = banner.frame.insetBy(dx: 5, dy: 2)
        let buttons = [banner.buttons["Añadir nota"].frame, banner.buttons["No es mío"].frame]
        let chevron = previous.frame
        let covered = stride(from: chevron.minX + 2, through: chevron.maxX - 2, by: 2)
            .map { CGPoint(x: $0, y: chevron.midY) }
            .first { p in bannerFrame.contains(p) && !buttons.contains { $0.insetBy(dx: -4, dy: -4).contains(p) } }
        guard let point = covered else {
            XCTFail("Ningún punto del chevron (\(chevron)) queda bajo el relleno del aviso (\(bannerFrame)), fuera de sus botones")
            return
        }
        at(point).tap()
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(month.label, monthBefore, "Un toque en el aviso atravesó hasta el chevron de mes de Gasto")
        XCTAssertFalse(app.buttons["Cerrar"].exists, "Un toque en el aviso abrió una hoja")
        XCTAssertTrue(banner.exists, "El toque en el aviso lo quitó")
        // Control: el aviso se va solo (a ×12, ~44 s desde que aparece); sin él, el mismo punto cambia el mes.
        XCTAssertTrue(waitUntil(60) { !banner.exists }, "El aviso no se fue")
        XCTAssertTrue(waitUntil(10) { previous.isHittable }, "El chevron de mes no se puede tocar")
        at(point).tap()
        XCTAssertTrue(waitUntil(10) { month.label != monthBefore },
                      "Sin aviso, el punto del chevron no cambia el mes: la prueba no probaba nada")
    }

    /// N-3 (ronda 1 de avisos): los avisos (texto y carga) y la Live Activity leen el ojo de la APP, no la copia de la
    /// suite compartida. Por qué falla si vuelve el defecto (N-B, re-revisión): en la demo la copia del ojo va a un
    /// dominio propio (`DemoSharedEye`) que solo lee la sonda `ojoCompartido`; la suite del grupo de apps de verdad, que
    /// es la que leería el código defectuoso, la demo no la escribe nunca, así que ahí no hay «cerrado» y el aviso
    /// saldría con el ojo abierto. `-MiBancoDemoSharedEyeOpposite` (copia al revés) solo sirve para comprobar que la
    /// sonda de la copia no es la que manda.
    func testAlertsReadTheAppEyeNotTheSharedCopy() throws {
        launch(["-MiBancoDemoPrivate", "-MiBancoDemoSharedEyeOpposite"])
        waitForLaunchToEnd(30)
        XCTAssertTrue(waitUntil(10) { self.probe()["ojoCompartido"] == "abierto" },
                      "La copia saboteada no dice lo contrario: la prueba no dice nada: \(probe())")
        XCTAssertEqual(probe()["ojoAviso"], "cerrado", "Un aviso con el ojo cerrado se compondría con cifras: \(probe())")
        XCTAssertEqual(probe()["ojoActividad"], "cerrado", "La Live Activity no sigue al ojo cerrado: \(probe())")
        let show = app.buttons["Mostrar importes"]
        XCTAssertTrue(show.waitForExistence(timeout: 8), "Falta el ojo cerrado de Inicio")
        XCTAssertTrue(waitUntil(8) { show.isHittable }, "El ojo no se puede tocar")
        show.tap()
        XCTAssertTrue(waitUntil(10) { self.probe()["ojoCompartido"] == "cerrado" }, "La copia no cambió: \(probe())")
        XCTAssertEqual(probe()["ojoAviso"], "abierto", "Con el ojo abierto un aviso saldría sin cifras: \(probe())")
        XCTAssertEqual(probe()["ojoActividad"], "abierto", "La Live Activity no sigue al ojo abierto: \(probe())")
    }

    /// Lote final (ojo de diseño 4.4, 5.1): la barra de pestañas cierra el montaje de Inicio. Se tapa en el mismo
    /// instante en que empieza el montaje y no empieza a destaparse hasta ~0,45 s después (× intensidad × cámara lenta;
    /// a ×10 en Expresivo, ~5 s): antes de eso ya han entrado la tarjeta, el selector y las primeras filas.
    func testTabBarEntersLast() throws {
        launch(["-MiBancoMotionScale", "10"])
        // M-1 (ronda 1): lo DIBUJADO del velo (que llegue hasta el borde y tape el canto) solo lo enseñan las hojas
        // (`launch`, `unlock*`): la barra de cristal se puede tocar por encima de cualquier capa de SwiftUI, así que su
        // «tocable» no dice si está tapada. Aquí: se tapa al empezar, se destapa después y entonces se puede tocar.
        XCTAssertTrue(waitUntil(60) { (self.probe()["barraTapada"] ?? "-") != "-" }, "La barra no se tapó: \(probe())")
        let homeTab = app.tabBars.buttons["Inicio"]
        XCTAssertTrue(waitUntil(90) { self.probe()["barraDestapada"] != "-" && self.probe()["barraDestapada"] != nil },
                      "La barra de pestañas no se destapó: \(probe())")
        XCTAssertTrue(waitUntil(15) { homeTab.isHittable }, "Destapada, la barra no se puede tocar")
        let p = probe()
        let covered = Double(p["barraTapada"] ?? "") ?? 0
        let uncovered = Double(p["barraDestapada"] ?? "") ?? 0
        XCTAssertGreaterThan(covered, 0, "La barra no se tapó al empezar el montaje: \(p)")
        XCTAssertGreaterThanOrEqual(uncovered - covered, 0.4 * 10, "La barra se destapa antes de que entre lo demás: \(p)")
    }

    /// Lote final (carcasa): con el abanico de tarjetas abierto, la barra de pestañas no queda encima; al cerrarlo, vuelve.
    func testTabBarHidesOverTheFan() throws {
        launch(["-MiBancoDemoCardElements", "-MiBancoDemoHomeProbes"])
        waitForLaunchToEnd(30)
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "Falta la barra de pestañas")
        XCTAssertTrue(waitUntil(10) { tabBar.isHittable }, "La barra de pestañas no se ve en Inicio")
        let carousel = app.descendants(matching: .any).matching(NSPredicate(format: "label ENDSWITH %@", " de 4")).firstMatch
        XCTAssertTrue(carousel.waitForExistence(timeout: 10), "Falta el carrusel")
        carousel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).press(forDuration: 1.6)
        XCTAssertTrue(app.staticTexts["Tus tarjetas"].waitForExistence(timeout: 8), "No se abrió el abanico")
        XCTAssertTrue(waitUntil(5) { !tabBar.exists || !tabBar.isHittable },
                      "La barra de pestañas sigue encima del abanico (\(tabBar.frame))")
        let close = app.buttons["wallet-fan-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "Falta «Cerrar» en el abanico")
        close.tap()
        XCTAssertTrue(waitUntil(8) { tabBar.exists && tabBar.isHittable }, "Al cerrar el abanico no vuelve la barra")
    }

    /// C4 (D1, decisión del dueño): «Te quedaban» empieza oculto y solo dice su cifra cuando el importe de arriba se ha
    /// posado. A ×20 el vuelo del importe dura varios segundos: justo al abrir la hoja, «Te quedaban» no tiene forma de
    /// importe; después sí (si no llegara nunca, la prueba tampoco pasa).
    func testTeQuedabanStartsHidden() throws {
        launch(["-MiBancoMotionScale", "20"])
        waitForLaunchToEnd(60)
        let row = app.buttons.matching(identifier: "movementRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "No hay filas de movimientos")
        XCTAssertTrue(waitUntil(60) { row.isHittable }, "La primera fila no se puede tocar")
        row.tap()
        let left = labelled("label BEGINSWITH %@", "Te quedaban")
        XCTAssertTrue(left.waitForExistence(timeout: 8), "La hoja no tiene «Te quedaban»")
        let early = left.label
        XCTAssertFalse(moneyShaped(early), "«Te quedaban» dice su cifra antes de que el importe se pose: «\(early)»")
        XCTAssertTrue(waitUntil(40) { self.moneyShaped(left.label) },
                      "«Te quedaban» nunca llegó a decir su cifra: «\(left.label)»")
    }

    /// Lote 2 (2.5): con el ojo cerrado, abrir el detalle de un movimiento no monta NINGÚN texto con forma de importe:
    /// ni el importe grande, ni «Te quedaban», ni el historial del comercio (que antes solo iba difuminado y las pruebas
    /// lo leían). Se mira solo DENTRO de la hoja (`movement-detail-scroll`), arriba y, tras deslizar, abajo: lo de
    /// Inicio, debajo, no cuenta ni puede tapar una fuga (antes se comparaban recuentos de toda la app, y una fuga con la
    /// misma cifra que una fila de Inicio que dejara de verse se anulaba).
    func testMovementDetailMountsNoAmountWithTheEyeClosed() throws {
        launch(["-MiBancoDemoPrivate"])
        waitForLaunchToEnd(30)
        let row = app.buttons.matching(identifier: "movementRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "No hay filas de movimientos")
        XCTAssertTrue(waitUntil(15) { row.isHittable }, "La primera fila no se puede tocar")
        row.tap()
        XCTAssertTrue(app.buttons["Cerrar"].waitForExistence(timeout: 8), "No se abrió la hoja de detalle")
        let sheet = app.scrollViews["movement-detail-scroll"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 8), "Falta la hoja de detalle")
        XCTAssertTrue(sheet.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Te quedaban importe oculto"))
            .firstMatch.waitForExistence(timeout: 8), "«Te quedaban» no dice «importe oculto» dentro de la hoja")
        // Una cifra de dinero de verdad: dígitos con su coma o su punto, o pegados al «€» (la máscara «•••,•• €» no
        // lleva dígitos; «4 compras este mes» tampoco es un importe).
        func leaks() -> [String] {
            sheet.descendants(matching: .any).allElementsBoundByIndex.flatMap { el -> [String] in
                [el.label, el.value as? String ?? ""].filter {
                    $0.range(of: #"\d,\d{2}|\d\.\d{3}|\d\s*€|€\s*\d|\d\s*euros"#, options: .regularExpression) != nil
                }
            }
        }
        XCTAssertGreaterThan(sheet.descendants(matching: .any).count, 3, "La hoja de detalle está vacía")
        XCTAssertEqual(leaks(), [], "Con el ojo cerrado el detalle monta importes (arriba)")
        // Lo de más abajo (el historial del comercio).
        sheet.swipeUp()
        XCTAssertEqual(leaks(), [], "Con el ojo cerrado el detalle monta importes (abajo, tras deslizar)")
        sheet.swipeUp()
        XCTAssertEqual(leaks(), [], "Con el ojo cerrado el detalle monta importes (al final)")
    }

    /// Lote 2 (2.5): la hoja de una posición con el ojo cerrado no monta ningún importe, precio ni número de acciones:
    /// dentro de la hoja ninguna etiqueta ni valor tiene forma de importe, y las acciones dicen «importe oculto».
    func testPositionSheetMountsNoAmountWithTheEyeClosed() throws {
        launch(["-MiBancoDemoPosition", "-MiBancoDemoPrivate"])
        XCTAssertTrue(app.buttons["Cerrar"].waitForExistence(timeout: 30), "No se abrió la hoja de la posición")
        let sheet = app.scrollViews["position-scroll"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 8), "Falta la hoja de la posición")
        func leaks() -> [String] {
            sheet.descendants(matching: .any).allElementsBoundByIndex.flatMap { el -> [String] in
                let texts = [el.label, el.value as? String ?? ""]
                return texts.filter { text in
                    moneyShaped(text) || text.contains("%")
                        || (text.contains("acc.") && text.range(of: #"\d"#, options: .regularExpression) != nil)
                }
            }
        }
        XCTAssertEqual(leaks(), [], "Con el ojo cerrado la hoja de la posición monta datos privados")
        XCTAssertTrue(sheet.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "importe oculto")).count > 0,
                      "Ningún dato de la hoja dice «importe oculto»: ¿está vacía?")
        sheet.swipeUp()
        XCTAssertEqual(leaks(), [], "Con el ojo cerrado la hoja de la posición monta datos privados (parte de abajo)")
    }

    /// Lote 2 (2.5): el resumen con el ojo cerrado no monta ninguna cifra de dinero en ninguna línea, y el botón del
    /// consejo no lleva importe.
    func testBriefingMountsNoAmountWithTheEyeClosed() throws {
        launch(["-MiBancoDemoBriefing", "busy", "-MiBancoDemoPrivate"])
        XCTAssertTrue(app.buttons["Vale"].waitForExistence(timeout: 20), "La hoja del resumen no se abrió")
        let sheet = app.scrollViews["briefing-scroll"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 8), "Falta la hoja del resumen")
        func leaks() -> [String] {
            sheet.descendants(matching: .any).allElementsBoundByIndex.flatMap { el -> [String] in
                [el.label, el.value as? String ?? ""].filter { moneyShaped($0) }
            }
        }
        XCTAssertTrue(sheet.descendants(matching: .any).count > 3, "El resumen está vacío")
        XCTAssertEqual(leaks(), [], "Con el ojo cerrado el resumen monta importes")
        sheet.swipeUp()
        XCTAssertEqual(leaks(), [], "Con el ojo cerrado el resumen monta importes (parte de abajo)")
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
