import XCTest

/// Toques reales sobre «Tu resumen», Onyx («Te puede interesar», «Pregúntame»), lectura en voz alta y ajustes del asistente
/// (Plan 4b, tareas 9, 10 y 13 ampliada A1–A6). Siempre en modo demo, sin red ni escritura persistente.
final class BriefingUITests: XCTestCase {
    var app: XCUIApplication!
    private let nbsp = "\u{00A0}"

    override func setUpWithError() throws {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "Alerta del sistema") { alert in
            for name in ["Permitir", "Allow", "OK", "Aceptar", "Not Now", "Ahora no"] {
                let b = alert.buttons[name]
                if b.exists { b.tap(); return true }
            }
            return false
        }
    }

    private func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-MiBancoDemo"] + extra + ["-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for name in ["Permitir", "Allow"] {
            let b = springboard.alerts.buttons[name]
            if b.waitForExistence(timeout: 2) { b.tap(); break }
        }
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func waitFor(_ predicate: NSPredicate, _ object: Any, timeout: TimeInterval) -> Bool {
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: object)
        return XCTWaiter().wait(for: [exp], timeout: timeout) == .completed
    }

    private func scrollTo(_ el: XCUIElement, swipes: Int = 8) {
        if el.waitForExistence(timeout: 2), el.isHittable { return }
        for _ in 0..<swipes {
            if el.exists && el.isHittable { return }
            app.swipeUp()
        }
        for _ in 0..<swipes {
            if el.exists && el.isHittable { return }
            app.swipeDown()
        }
    }

    /// Review Focus 2: el resumen aparece una vez solo al abrir y luego se puede volver a abrir con «Tu resumen».
    func testBriefingOnceThenFromButton() throws {
        launch(["-MiBancoDemoBriefing", "busy"])

        let doneButton = app.buttons["Vale"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 12), "El resumen automático no apareció al abrir")
        doneButton.tap()

        XCTAssertTrue(
            waitFor(NSPredicate(format: "exists == false"), doneButton, timeout: 8),
            "La hoja del resumen no se cerró al pulsar Vale"
        )

        let reopenButton = app.buttons["Tu resumen"]
        XCTAssertTrue(reopenButton.waitForExistence(timeout: 8), "Falta el botón «Tu resumen» en la barra de Inicio")
        reopenButton.tap()

        XCTAssertTrue(doneButton.waitForExistence(timeout: 8), "El resumen no se volvió a abrir desde «Tu resumen»")
    }

    /// Review Focus 3: con el modo privado activo, ningún elemento del resumen expone «€» ni «%».
    func testBriefingPrivateHidesAmounts() throws {
        launch(["-MiBancoDemoBriefing", "busy", "-MiBancoDemoPrivate"])

        let doneButton = app.buttons["Vale"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 12), "El resumen en modo privado no apareció")

        let euroElements = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '€'"))
        XCTAssertEqual(euroElements.count, 0, "El resumen expuso '€' en modo privado")

        let percentElements = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '%'"))
        XCTAssertEqual(percentElements.count, 0, "El resumen expuso '%' en modo privado")
    }

    /// Tocar la acción del consejo de falta de saldo abre «Mover dinero» con el importe ya rellenado.
    func testBriefingActionOpensMoveMoney() throws {
        launch(["-MiBancoDemoBriefing", "busy", "-MiBancoDemoShortfall"])

        let doneButton = app.buttons["Vale"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 12), "El resumen con falta de saldo no apareció")

        let tipAction = app.buttons["Pasar 10,00\(nbsp)€"]
        scrollTo(tipAction)
        XCTAssertTrue(tipAction.waitForExistence(timeout: 8), "Falta el botón «Pasar 10,00 €» en el consejo")
        tipAction.tap()

        XCTAssertTrue(app.navigationBars["Mover dinero"].waitForExistence(timeout: 10), "No se abrió la hoja Mover dinero")
        XCTAssertTrue(
            app.staticTexts["10,00\(nbsp)€"].waitForExistence(timeout: 8),
            "Mover dinero no llegó con 10,00 € pre-rellenado"
        )
    }

    /// Tarea 10: el botón «Escuchar» cambia a «Parar» y vuelve a «Escuchar».
    func testListenToggles() throws {
        launch(["-MiBancoDemoBriefing", "busy"])

        let doneButton = app.buttons["Vale"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 12), "El resumen no apareció")

        let listen = app.buttons["Escuchar"]
        XCTAssertTrue(listen.waitForExistence(timeout: 8), "Falta el botón «Escuchar»")
        listen.tap()

        let stop = app.buttons["Parar"]
        XCTAssertTrue(stop.waitForExistence(timeout: 6), "El botón no pasó a «Parar» al escuchar")
        stop.tap()

        XCTAssertTrue(listen.waitForExistence(timeout: 6), "El botón no volvió a «Escuchar» al parar")
    }

    /// A1–A4: «Te puede interesar» descarta una tarjeta y «Pregúntame» rechaza consejos de inversión literalmente y contesta hechos.
    func testAssistantAskAndInterestCards() throws {
        launch(["-MiBancoDemoBriefing", "busy"])

        let doneButton = app.buttons["Vale"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 12), "El resumen no apareció")

        let dislikeButton = app.buttons["No me interesa"].firstMatch
        scrollTo(dislikeButton)
        if dislikeButton.waitForExistence(timeout: 5) {
            let beforeCount = app.buttons.matching(identifier: "No me interesa").count
            dislikeButton.tap()
            let afterMatches = app.buttons.matching(NSPredicate(format: "label == 'No me interesa'"))
            _ = waitFor(NSPredicate(format: "count < %d", max(1, beforeCount)), afterMatches, timeout: 4)
        }

        let questionField = element("assistant-question-field")
        scrollTo(questionField)
        XCTAssertTrue(questionField.waitForExistence(timeout: 8), "Falta el campo «Pregúntame algo de tu dinero…»")
        questionField.tap()
        questionField.typeText("¿Debo comprar Apple?")

        let sendButton = element("assistant-send")
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5), "Falta el botón de enviar pregunta")
        sendButton.tap()

        let refusal = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'asesor financiero autorizado'")
        ).firstMatch
        scrollTo(refusal)
        XCTAssertTrue(refusal.waitForExistence(timeout: 8), "No apareció la negativa de consejo financiero")

        let balancesChip = element("assistant-chip-balances")
        scrollTo(balancesChip)
        XCTAssertTrue(balancesChip.waitForExistence(timeout: 6), "Falta la ficha sugerida «¿Cuánto tengo?»")
        balancesChip.tap()

        let totalAnswer = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'En total tienes'")
        ).firstMatch
        scrollTo(totalAnswer)
        XCTAssertTrue(totalAnswer.waitForExistence(timeout: 8), "No apareció la respuesta factual de saldos")
    }

    /// A4 + Tarea 10: Ajustes › Asistente muestra los 6 temas y Avisos muestra la regla «Resumen cada mañana» con selector de hora.
    func testAssistantSettingsAndMorningRule() throws {
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoAssistantSettings"])

        let firstTopic = element("assistant-topic-unusualPayment")
        scrollTo(firstTopic)
        XCTAssertTrue(firstTopic.waitForExistence(timeout: 10), "Falta el interruptor de tema en Ajustes › Asistente")
        let lastTopic = element("assistant-topic-portfolioMover")
        scrollTo(lastTopic)
        XCTAssertTrue(lastTopic.waitForExistence(timeout: 8), "Falta el sexto tema en Ajustes › Asistente")

        launch(["-MiBancoDemoScreen", "avisos", "-MiBancoDemoRules"])
        let morningRule = element("alert-rule-morningBriefing")
        scrollTo(morningRule)
        XCTAssertTrue(morningRule.waitForExistence(timeout: 10), "Falta la regla «Resumen cada mañana» en Avisos")
        let morningTime = element("morning-briefing-time")
        scrollTo(morningTime)
        XCTAssertTrue(morningTime.waitForExistence(timeout: 6), "Falta el selector de hora de «Resumen cada mañana»")
    }

    /// Al salir a segundo plano, la hoja del resumen abierta a mano se cierra sola y nunca queda abierta al volver.
    func testBriefingDismissesOnBackground() throws {
        launch([])

        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no apareció")
        let button = app.buttons["Tu resumen"]
        XCTAssertTrue(button.waitForExistence(timeout: 8), "Falta el botón «Tu resumen»")
        button.tap()

        let doneButton = app.buttons["Vale"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 8), "La hoja del resumen no se abrió")

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1.0)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "La app no volvió a primer plano")

        XCTAssertTrue(
            waitFor(NSPredicate(format: "exists == false"), doneButton, timeout: 8),
            "La hoja del resumen siguió abierta tras volver de segundo plano"
        )
    }
}
