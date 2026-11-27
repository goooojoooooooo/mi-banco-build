import XCTest

/// Pruebas de interfaz de Nyx Fase 2 — N12 (voz de Nyx, cambio de salida de audio, foco/respuesta y privacidad con ojo cerrado).
final class NyxVoiceUITests: XCTestCase {
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
        app = XCUIApplication()
        app.launchArguments = ["-MiBancoDemo"] + extra + ["-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func waitUntil(_ timeout: TimeInterval = 12, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.15)
        }
        return condition()
    }

    private func scrollTo(_ target: XCUIElement, swipes: Int = 10) {
        let scroller = app.scrollViews["briefing-scroll"].exists ? app.scrollViews["briefing-scroll"] : app.scrollViews.firstMatch
        for _ in 0..<swipes where !(target.exists && target.isHittable) {
            scroller.swipeUp()
        }
        for _ in 0..<swipes where !(target.exists && target.isHittable) {
            scroller.swipeDown()
        }
    }

    private func spokenTextValue() -> String {
        let probe = element("nyx-spoken-text")
        guard probe.exists else { return "" }
        return (probe.value as? String) ?? ""
    }

    /// N12: «Escuchar» en la cabecera lee la puesta al día de Nyx (apertura + resumen + foco) y «Parar» la detiene.
    func testEscucharLeeLaPuestaAlDiaYSePara() throws {
        launch(["-MiBancoDemoBriefing", "busy", "-MiBancoDemoNyx", "daily-focus"])
        let listen = app.buttons["briefing-listen"]
        XCTAssertTrue(listen.waitForExistence(timeout: 20), "Falta briefing-listen")
        XCTAssertEqual(listen.label, "Escuchar")

        listen.tap()
        XCTAssertTrue(waitUntil(6) { listen.label == "Parar" }, "briefing-listen no pasó a Parar")

        let probe = element("nyx-spoken-text")
        XCTAssertTrue(probe.waitForExistence(timeout: 6), "Falta la sonda DEBUG nyx-spoken-text")
        let spoken = spokenTextValue()
        XCTAssertFalse(spoken.isEmpty, "El texto hablado de la puesta al día está vacío")
        XCTAssertTrue(spoken.localizedCaseInsensitiveContains("Netflix"),
                      "La puesta al día hablada no incluye la cosa a tener en cuenta (Netflix): \(spoken)")

        listen.tap()
        XCTAssertTrue(waitUntil(6) { listen.label == "Escuchar" }, "briefing-listen no volvió a Escuchar tras Parar")
    }

    /// N12: un cambio de salida de audio detiene la voz y devuelve «briefing-listen» a «Escuchar».
    func testCambioDeSalidaParaLaVoz() throws {
        launch(["-MiBancoDemoBriefing", "busy", "-MiBancoDemoNyx", "daily-focus", "-MiBancoDemoRouteChange", "2"])
        let listen = app.buttons["briefing-listen"]
        XCTAssertTrue(listen.waitForExistence(timeout: 20), "Falta briefing-listen")

        listen.tap()
        XCTAssertTrue(waitUntil(6) { listen.label == "Parar" }, "briefing-listen no empezó a leer")
        XCTAssertTrue(element("nyx-spoken-text").waitForExistence(timeout: 4), "Falta la sonda nyx-spoken-text")
        XCTAssertFalse(spokenTextValue().isEmpty, "No hay texto hablado activo")

        XCTAssertTrue(waitUntil(10) { listen.label == "Escuchar" },
                      "El cambio de salida de audio no detuvo la voz")
    }

    /// N12: el foco («Para tener en cuenta») y las respuestas de «Pregúntame» tienen su propio botón «Escuchar».
    func testEscucharEnFocoYRespuesta() throws {
        launch(["-MiBancoDemoBriefing", "busy", "-MiBancoDemoNyx", "daily-focus"])
        XCTAssertTrue(element("nyx-sheet-title").waitForExistence(timeout: 20), "No se abrió la hoja de Nyx")

        let focusListen = app.buttons["nyx-listen-focus"]
        scrollTo(focusListen)
        XCTAssertTrue(focusListen.waitForExistence(timeout: 8), "Falta nyx-listen-focus")
        XCTAssertEqual(focusListen.label, "Escuchar")
        focusListen.tap()
        XCTAssertTrue(waitUntil(6) { focusListen.label == "Parar" }, "nyx-listen-focus no pasó a Parar")
        XCTAssertTrue(spokenTextValue().localizedCaseInsensitiveContains("Netflix"),
                      "El foco hablado no menciona Netflix: \(spokenTextValue())")
        focusListen.tap()
        XCTAssertTrue(waitUntil(6) { focusListen.label == "Escuchar" }, "nyx-listen-focus no volvió a Escuchar")

        let field = app.textFields["assistant-question-field"]
        scrollTo(field)
        XCTAssertTrue(field.waitForExistence(timeout: 8), "Falta assistant-question-field")
        field.tap()
        field.typeText("¿Cuánto llevo en Mercadona?")
        let send = app.buttons["assistant-send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5), "Falta assistant-send")
        send.tap()

        let answerListen = app.buttons["nyx-listen-answer"]
        XCTAssertTrue(answerListen.waitForExistence(timeout: 10), "Falta nyx-listen-answer")
        scrollTo(answerListen)
        answerListen.tap()
        XCTAssertTrue(waitUntil(6) { answerListen.label == "Parar" }, "nyx-listen-answer no pasó a Parar")
        XCTAssertTrue(spokenTextValue().localizedCaseInsensitiveContains("Mercadona"),
                      "La respuesta hablada no menciona Mercadona: \(spokenTextValue())")
        answerListen.tap()
        XCTAssertTrue(waitUntil(6) { answerListen.label == "Escuchar" }, "nyx-listen-answer no volvió a Escuchar")
    }

    /// N12: con el ojo cerrado, la voz nunca lee importes, «€», «euros» ni «%» (ni en la puesta al día, ni en el foco ni en una respuesta).
    func testConElOjoCerradoLaVozNoLeeImportes() throws {
        launch(["-MiBancoDemoBriefing", "busy", "-MiBancoDemoNyx", "daily-focus", "-MiBancoDemoPrivate"])
        let listen = app.buttons["briefing-listen"]
        XCTAssertTrue(listen.waitForExistence(timeout: 20), "Falta briefing-listen")

        // 1. Puesta al día con el ojo cerrado: nunca importes ni símbolos de dinero.
        listen.tap()
        XCTAssertTrue(waitUntil(6) { listen.label == "Parar" }, "briefing-listen no empezó en privado")
        let updateSpoken = spokenTextValue()
        XCTAssertFalse(updateSpoken.isEmpty, "El texto hablado privado está vacío")
        XCTAssertTrue(updateSpoken.localizedCaseInsensitiveContains("modo privado"),
                      "La puesta al día privada no avisa del modo privado: \(updateSpoken)")
        XCTAssertFalse(updateSpoken.contains("€"), "La puesta al día privada contiene €: \(updateSpoken)")
        XCTAssertFalse(updateSpoken.localizedCaseInsensitiveContains("euros"),
                       "La puesta al día privada contiene 'euros': \(updateSpoken)")
        XCTAssertFalse(updateSpoken.contains("%"), "La puesta al día privada contiene %: \(updateSpoken)")
        for forbidden in ["13,99", "9,20", "340,20", "1.284", "1284", "2.150", "49,95", "12,50"] {
            XCTAssertFalse(updateSpoken.contains(forbidden),
                           "La puesta al día privada filtró el importe \(forbidden): \(updateSpoken)")
        }
        listen.tap()
        XCTAssertTrue(waitUntil(6) { listen.label == "Escuchar" })

        // 2. Foco de Nyx con el ojo cerrado: cero dígitos en absoluto.
        let focusListen = app.buttons["nyx-listen-focus"]
        scrollTo(focusListen)
        XCTAssertTrue(focusListen.waitForExistence(timeout: 8), "Falta nyx-listen-focus en privado")
        focusListen.tap()
        XCTAssertTrue(waitUntil(6) { focusListen.label == "Parar" })
        let focusSpoken = spokenTextValue()
        XCTAssertFalse(focusSpoken.isEmpty, "El foco hablado privado está vacío")
        XCTAssertFalse(focusSpoken.contains(where: \.isNumber), "El foco hablado privado contiene dígitos: \(focusSpoken)")
        XCTAssertFalse(focusSpoken.contains("€"), "El foco hablado privado contiene €: \(focusSpoken)")
        XCTAssertFalse(focusSpoken.localizedCaseInsensitiveContains("euros"), "El foco hablado privado contiene euros: \(focusSpoken)")
        XCTAssertFalse(focusSpoken.contains("%"), "El foco hablado privado contiene %: \(focusSpoken)")
        focusListen.tap()
        XCTAssertTrue(waitUntil(6) { focusListen.label == "Escuchar" })

        // 3. Respuesta con el ojo cerrado: cero dígitos, cero €, cero euros.
        let field = app.textFields["assistant-question-field"]
        scrollTo(field)
        XCTAssertTrue(field.waitForExistence(timeout: 8), "Falta assistant-question-field en privado")
        field.tap()
        field.typeText("¿Cuánto llevo en Mercadona?")
        app.buttons["assistant-send"].tap()

        let answerListen = app.buttons["nyx-listen-answer"]
        XCTAssertTrue(answerListen.waitForExistence(timeout: 10), "Falta nyx-listen-answer en privado")
        scrollTo(answerListen)
        answerListen.tap()
        XCTAssertTrue(waitUntil(6) { answerListen.label == "Parar" })
        let answerSpoken = spokenTextValue()
        XCTAssertFalse(answerSpoken.isEmpty, "La respuesta hablada privada está vacía")
        XCTAssertFalse(answerSpoken.contains(where: \.isNumber), "La respuesta hablada privada contiene dígitos: \(answerSpoken)")
        XCTAssertFalse(answerSpoken.contains("€"), "La respuesta hablada privada contiene €: \(answerSpoken)")
        XCTAssertFalse(answerSpoken.localizedCaseInsensitiveContains("euros"), "La respuesta hablada privada contiene euros: \(answerSpoken)")
        XCTAssertFalse(answerSpoken.contains("%"), "La respuesta hablada privada contiene %: \(answerSpoken)")
        answerListen.tap()
    }
}
