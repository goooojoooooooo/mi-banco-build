import XCTest

/// Toques reales sobre Inversiones (Ajustes › Inversiones, tarjeta Cartera y hoja de posición).
/// Siempre en modo demo (`-MiBancoDemo…`): datos inventados, sin red.
final class InvestmentsUITests: XCTestCase {
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

    private func waitFor(_ predicate: NSPredicate, _ object: Any, timeout: TimeInterval) -> Bool {
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: object)
        return XCTWaiter().wait(for: [exp], timeout: timeout) == .completed
    }

    private func scrollTo(_ el: XCUIElement, swipes: Int = 6) {
        var left = swipes
        while left > 0 && !(el.exists && el.isHittable) {
            app.swipeUp()
            left -= 1
        }
    }

    func testPricesSwitchAndAsk() throws {
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoInvestmentsSettings", "-MiBancoDemoAskPrices"])
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 15), "No se ve Ajustes")

        let askTitle = app.staticTexts["¿Buscar los precios cada día?"]
        scrollTo(askTitle)
        XCTAssertTrue(askTitle.waitForExistence(timeout: 10), "No aparece la pregunta inicial de precios")

        let yesButton = app.buttons["Sí, buscar precios"]
        scrollTo(yesButton)
        XCTAssertTrue(yesButton.waitForExistence(timeout: 5), "Falta el botón Sí, buscar precios")
        yesButton.tap()

        let gone = NSPredicate(format: "exists == false")
        XCTAssertTrue(waitFor(gone, askTitle, timeout: 8), "La pregunta de precios no desapareció al aceptar")

        let pricesSwitch = app.switches["Precios de tus inversiones"]
        scrollTo(pricesSwitch)
        XCTAssertTrue(pricesSwitch.waitForExistence(timeout: 5), "No aparece el interruptor de precios")
        XCTAssertEqual(pricesSwitch.value as? String, "1", "El interruptor debería quedar activado tras aceptar")

        pricesSwitch.tap()
        let off = NSPredicate(format: "value == '0'")
        XCTAssertTrue(waitFor(off, pricesSwitch, timeout: 8), "El interruptor no pasó a 0 al tocarlo")
    }

    func testCardAndPosition() throws {
        launch(["-MiBancoDemoCard", "inv"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")

        let invLabel = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Inversiones'"))
            .firstMatch
        let countLabel = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '3 posiciones'"))
            .firstMatch
        XCTAssertTrue(invLabel.waitForExistence(timeout: 10), "No se ve Inversiones")
        XCTAssertTrue(countLabel.waitForExistence(timeout: 10), "No se ve 3 posiciones")

        let appleRow = app.buttons["Apple"]
        scrollTo(appleRow)
        XCTAssertTrue(appleRow.waitForExistence(timeout: 10), "No se ve la fila de Apple")
        appleRow.tap()

        let manualButton = app.buttons["Poner precio a mano"]
        scrollTo(manualButton)
        XCTAssertTrue(manualButton.waitForExistence(timeout: 8), "No aparece Poner precio a mano en la hoja")
        manualButton.tap()

        let field = app.textFields["manualPriceField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "No apareció el campo de precio a mano")

        let close = app.buttons["Cerrar"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "Falta el botón Cerrar")
        close.tap()

        let gone = NSPredicate(format: "exists == false")
        XCTAssertTrue(waitFor(gone, manualButton, timeout: 8), "La hoja de posición no se cerró")
    }

    func testInvestmentsPrivateModeHidesAmounts() throws {
        launch(["-MiBancoDemoCard", "inv", "-MiBancoDemoPrivate"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")

        let appleRow = app.buttons["Apple"]
        scrollTo(appleRow)
        XCTAssertTrue(appleRow.waitForExistence(timeout: 10), "No se ve la fila de Apple en privado")
        XCTAssertFalse(appleRow.label.contains("€"), "La fila de posición filtró € en modo privado: \(appleRow.label)")
        XCTAssertFalse(appleRow.label.contains("%"), "La fila de posición filtró % en modo privado: \(appleRow.label)")

        appleRow.tap()
        let close = app.buttons["Cerrar"]
        XCTAssertTrue(close.waitForExistence(timeout: 8), "No se abrió la hoja de posición en privado")
        let euroTexts = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '€'"))
        XCTAssertEqual(euroTexts.count, 0, "La hoja de posición expuso importes a VoiceOver en modo privado")
        close.tap()
    }
}
