import XCTest

/// Pruebas de interfaz de Nyx Fase 2 — N11 (preguntar a Nyx por texto o voz, preguntas seguidas y privacidad `m-11`).
final class NyxAskUITests: XCTestCase {
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

    private func openNyxFromButton() {
        let nyx = app.buttons["nyx-button"]
        XCTAssertTrue(nyx.waitForExistence(timeout: 20), "Falta nyx-button")
        nyx.tap()
        XCTAssertTrue(element("nyx-sheet-title").waitForExistence(timeout: 8), "No se abrió la hoja de Nyx")
    }

    private func ask(_ question: String) {
        let field = app.textFields["assistant-question-field"]
        let scroller = app.scrollViews["briefing-scroll"].exists ? app.scrollViews["briefing-scroll"] : app.scrollViews.firstMatch
        for _ in 0..<8 where !(field.exists && field.isHittable) {
            scroller.swipeUp()
        }
        XCTAssertTrue(field.waitForExistence(timeout: 8), "Falta el campo Pregúntame")
        field.tap()
        field.typeText(question)
        let send = app.buttons["assistant-send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5), "Falta el botón Preguntar")
        send.tap()
    }

    private func answerCardText() -> String {
        let card = element("assistant-answer-card")
        guard card.exists else { return "" }
        let labels = card.descendants(matching: .any).allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }
        return labels.joined(separator: " ")
    }

    /// N11: «¿Cuánto llevo en Mercadona?» seguido de «¿y el mes pasado?» responde con el mes anterior (octubre).
    func testPreguntaSeguidaElMesPasado() throws {
        launch(["-MiBancoDemoToday", "2026-11-20"])
        openNyxFromButton()

        ask("¿Cuánto llevo en Mercadona?")
        XCTAssertTrue(waitUntil(10) { self.answerCardText().localizedCaseInsensitiveContains("Mercadona") },
                      "La primera respuesta no menciona Mercadona: \(answerCardText())")

        ask("¿y el mes pasado?")
        XCTAssertTrue(waitUntil(10) {
            let text = self.answerCardText()
            return text.localizedCaseInsensitiveContains("octubre") && text.localizedCaseInsensitiveContains("Mercadona")
        }, "La pregunta seguida no mantuvo Mercadona en octubre: \(answerCardText())")
    }

    /// N11: «¿Qué has visto?» contesta con los mensajes de «Lo que he visto».
    func testQueHasVisto() throws {
        launch(["-MiBancoDemoNyx", "seen-list"])
        openNyxFromButton()

        ask("¿Qué has visto?")
        XCTAssertTrue(waitUntil(10) {
            let text = self.answerCardText()
            return text.contains("Esto es lo que he visto")
                && (text.contains("Netflix") || text.contains("Zara"))
        }, "«¿Qué has visto?» no devolvió las observaciones recientes: \(answerCardText())")
    }

    /// N11 (`m-11`): con el ojo cerrado, «¿Qué has visto?» no filtra ningún dígito, «€» ni «%».
    func testQueHasVistoConOjoCerradoSinCifras() throws {
        launch(["-MiBancoDemoNyx", "seen-list", "-MiBancoDemoPrivate"])
        openNyxFromButton()

        ask("¿Qué has visto?")
        XCTAssertTrue(waitUntil(10) { self.answerCardText().contains("Esto es lo que he visto") },
                      "«¿Qué has visto?» en privado no contestó: \(answerCardText())")

        let text = answerCardText()
        XCTAssertFalse(text.contains(where: \.isNumber), "«¿Qué has visto?» en privado contiene dígitos: \(text)")
        XCTAssertFalse(text.contains("€"), "«¿Qué has visto?» en privado contiene €: \(text)")
        XCTAssertFalse(text.contains("%"), "«¿Qué has visto?» en privado contiene %: \(text)")
    }

    /// N11: al cerrar y reabrir la hoja de Nyx, la conversación anterior se olvida («¿y el mes pasado?» no se une a Mercadona).
    func testLaConversacionSeOlvidaAlCerrar() throws {
        launch(["-MiBancoDemoToday", "2026-11-20"])
        openNyxFromButton()

        ask("¿Cuánto llevo en Mercadona?")
        XCTAssertTrue(waitUntil(10) { self.answerCardText().localizedCaseInsensitiveContains("Mercadona") },
                      "La primera respuesta no menciona Mercadona: \(answerCardText())")

        let close = app.buttons["briefing-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 6), "Falta el botón Cerrar de la hoja")
        close.tap()
        XCTAssertTrue(waitUntil(8) { !close.exists }, "No se cerró la hoja de Nyx")

        openNyxFromButton()
        ask("¿y el mes pasado?")
        XCTAssertTrue(waitUntil(10) { !self.answerCardText().isEmpty }, "No apareció tarjeta de respuesta tras reabrir")
        XCTAssertFalse(answerCardText().localizedCaseInsensitiveContains("Mercadona"),
                       "Tras cerrar y reabrir, Nyx recordó Mercadona de la conversación anterior: \(answerCardText())")
    }

    /// N11: sin transcripción local disponible no aparece el botón de micrófono (`nyx-mic`); con ella disponible, sí.
    func testSinTranscripcionNoHayMicrofono() throws {
        launch(["-MiBancoDemoNyxNoSpeech"])
        openNyxFromButton()

        let field = app.textFields["assistant-question-field"]
        let scroller = app.scrollViews["briefing-scroll"].exists ? app.scrollViews["briefing-scroll"] : app.scrollViews.firstMatch
        for _ in 0..<8 where !field.exists { scroller.swipeUp() }
        XCTAssertTrue(field.waitForExistence(timeout: 8), "Falta el campo Pregúntame")
        XCTAssertFalse(app.buttons["nyx-mic"].exists, "Sin transcripción local no debe existir nyx-mic")

        app.terminate()

        launch()
        openNyxFromButton()
        for _ in 0..<8 where !field.exists { scroller.swipeUp() }
        XCTAssertTrue(app.buttons["nyx-mic"].waitForExistence(timeout: 6), "Con transcripción disponible falta nyx-mic")
    }
}
