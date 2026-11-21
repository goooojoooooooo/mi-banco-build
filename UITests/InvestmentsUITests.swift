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

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func waitFor(_ predicate: NSPredicate, _ object: Any, timeout: TimeInterval) -> Bool {
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: object)
        return XCTWaiter().wait(for: [exp], timeout: timeout) == .completed
    }

    /// Espera un instante por si `SettingsScrollHost` desplaza la vista solo, y luego busca hacia abajo y hacia arriba.
    private func scrollTo(_ el: XCUIElement, swipes: Int = 6) {
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

        let pricesSwitch = element("investments-prices-toggle")
        scrollTo(pricesSwitch)
        XCTAssertTrue(pricesSwitch.waitForExistence(timeout: 5), "No aparece el interruptor de precios")
        let on = NSPredicate(format: "value == '1'")
        XCTAssertTrue(waitFor(on, pricesSwitch, timeout: 8), "El interruptor debería quedar activado tras aceptar")

        pricesSwitch.tap()
        let off = NSPredicate(format: "value == '0'")
        XCTAssertTrue(waitFor(off, pricesSwitch, timeout: 8), "El interruptor no pasó a 0 al tocarlo")
    }

    func testPricesAskDeclineLeavesSwitchOff() throws {
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoInvestmentsSettings", "-MiBancoDemoAskPrices"])
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 15), "No se ve Ajustes")

        let askTitle = app.staticTexts["¿Buscar los precios cada día?"]
        scrollTo(askTitle)
        XCTAssertTrue(askTitle.waitForExistence(timeout: 10), "No aparece la pregunta inicial de precios")

        let decline = app.buttons["Los pondré yo"]
        scrollTo(decline)
        XCTAssertTrue(decline.waitForExistence(timeout: 5), "Falta el botón Los pondré yo")
        decline.tap()

        let gone = NSPredicate(format: "exists == false")
        XCTAssertTrue(waitFor(gone, askTitle, timeout: 8), "La pregunta no desapareció al elegir Los pondré yo")

        let pricesSwitch = element("investments-prices-toggle")
        scrollTo(pricesSwitch)
        XCTAssertTrue(pricesSwitch.waitForExistence(timeout: 5), "No aparece el interruptor de precios")
        let off = NSPredicate(format: "value == '0'")
        XCTAssertTrue(waitFor(off, pricesSwitch, timeout: 8), "El interruptor debería seguir en 0")
    }

    func testImportTradeRepublicOpensFilePicker() throws {
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoInvestmentsSettings"])
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 15), "No se ve Ajustes")

        let importRow = element("investments-import")
        scrollTo(importRow)
        XCTAssertTrue(importRow.waitForExistence(timeout: 10), "Falta la fila Importar de Trade Republic")
        importRow.tap()

        let cancelNames = ["Cancelar", "Cancel", "Cerrar", "Close"]
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", cancelNames)).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 20), "No se abrió el selector de archivos al tocar Importar de Trade Republic")
        cancel.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "exists == false"), cancel, timeout: 10), "El selector de archivos no se cerró")
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

    func testPositionSheetDismissesOnBackground() throws {
        launch(["-MiBancoDemoCard", "inv"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")

        let appleRow = app.buttons["Apple"]
        scrollTo(appleRow)
        XCTAssertTrue(appleRow.waitForExistence(timeout: 10), "No se ve la fila de Apple")
        appleRow.tap()

        let close = app.buttons["Cerrar"]
        XCTAssertTrue(close.waitForExistence(timeout: 8), "No se abrió la hoja de posición")

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1.0)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "La app no volvió a primer plano")

        let gone = NSPredicate(format: "exists == false")
        XCTAssertTrue(waitFor(gone, close, timeout: 8), "La hoja de posición no se cerró al salir de primer plano")
    }

    func testInvestmentsPrivateModeHidesAmounts() throws {
        launch(["-MiBancoDemoCard", "inv", "-MiBancoDemoPrivate"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")

        let appleRow = app.buttons["Apple"]
        scrollTo(appleRow)
        XCTAssertTrue(appleRow.waitForExistence(timeout: 10), "No se ve la fila de Apple en privado")
        let euroPred = NSPredicate(format: "label CONTAINS '€' OR value CONTAINS '€'")
        let pctPred = NSPredicate(format: "label CONTAINS '%' OR value CONTAINS '%'")
        let appleEuro = appleRow.descendants(matching: .any).matching(euroPred)
        let applePct = appleRow.descendants(matching: .any).matching(pctPred)
        XCTAssertEqual(appleEuro.count, 0, "La fila de Apple filtró € en privado: \(appleEuro.allElementsBoundByIndex.map(\.label))")
        XCTAssertEqual(applePct.count, 0, "La fila de Apple filtró % en privado: \(applePct.allElementsBoundByIndex.map(\.label))")
        XCTAssertEqual(appleRow.label, "Apple, importe oculto", "La etiqueta de Apple en privado no coincide: \(appleRow.label)")

        appleRow.tap()
        let close = app.buttons["Cerrar"]
        XCTAssertTrue(close.waitForExistence(timeout: 8), "No se abrió la hoja de posición en privado")
        let scroll = app.scrollViews["position-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 8), "Falta position-scroll en la hoja de posición")
        let euroInside = scroll.descendants(matching: .any).matching(euroPred)
        let pctInside = scroll.descendants(matching: .any).matching(pctPred)
        let allAppEuro = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '€'"))
        XCTAssertEqual(
            euroInside.count, 0,
            "U8 diag position-scroll €=\(euroInside.count): \(euroInside.allElementsBoundByIndex.map { "\($0.identifier)|\($0.label)" }) | app.staticTexts €=\(allAppEuro.count): \(allAppEuro.allElementsBoundByIndex.map { "\($0.identifier)|\($0.label)" })"
        )
        XCTAssertEqual(
            pctInside.count, 0,
            "U8 diag position-scroll %=\(pctInside.count): \(pctInside.allElementsBoundByIndex.map { "\($0.identifier)|\($0.label)" })"
        )

        let manualButton = app.buttons["Poner precio a mano"]
        scrollTo(manualButton)
        XCTAssertTrue(manualButton.waitForExistence(timeout: 5), "Falta Poner precio a mano")
        manualButton.tap()

        let field = app.textFields["manualPriceField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "No apareció el campo de precio a mano")
        // Al guardar el precio actual, el campo pierde el foco y su valor de accesibilidad debe quedar oculto.
        let save = app.buttons["Guardar"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "Falta el botón Guardar")
        save.tap()
        if field.exists {
            let valueText = (field.value as? String) ?? ""
            XCTAssertFalse(valueText.contains("200"), "El campo sin foco filtró el precio a VoiceOver: \(valueText)")
        }
        close.tap()
    }
}
