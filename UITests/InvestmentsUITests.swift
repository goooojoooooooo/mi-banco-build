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

        // U14: la tarjeta dice «desde la compra» y no usa el formato viejo «(viernes)».
        let sinceBuy = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'desde la compra'"))
            .firstMatch
        XCTAssertTrue(sinceBuy.waitForExistence(timeout: 5), "U14: la tarjeta de inversiones debe mostrar «desde la compra»")
        let oldParenFriday = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '(viernes)'"))
        XCTAssertEqual(oldParenFriday.count, 0, "U14: no debe quedar el formato viejo «(viernes)»")

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
        let appleEuro = appleRow.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '€' OR value CONTAINS '€'"))
        let applePct = appleRow.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '%' OR value CONTAINS '%'"))
        XCTAssertEqual(appleEuro.count, 0, "La fila de Apple filtró € en privado: \(appleEuro.allElementsBoundByIndex.map { $0.label })")
        XCTAssertEqual(applePct.count, 0, "La fila de Apple filtró % en privado: \(applePct.allElementsBoundByIndex.map { $0.label })")
        XCTAssertEqual(appleRow.label, "Apple, importe oculto", "La etiqueta de Apple en privado no coincide: \(appleRow.label)")

        appleRow.tap()
        let close = app.buttons["Cerrar"]
        XCTAssertTrue(close.waitForExistence(timeout: 8), "No se abrió la hoja de posición en privado")
        let scroll = app.scrollViews["position-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 8), "Falta position-scroll en la hoja de posición")
        let euroInside = scroll.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '€' OR value CONTAINS '€'"))
        let pctInside = scroll.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '%' OR value CONTAINS '%'"))
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
        // U12 + U19: en modo privado el campo abre sin foco y su valor de accesibilidad debe ser «importe oculto».
        XCTAssertEqual(field.value as? String, "importe oculto", "U12/U19: el campo en privado debe abrir como importe oculto")

        // U75 (A-I3): al enfocarlo el valor deja de ser «importe oculto» (se edita a la vista); al quitar el foco con «Hecho»
        // del teclado (que NO guarda), vuelve a «importe oculto». Sin condiciones ni plan B.
        field.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "value != 'importe oculto'"), field, timeout: 5),
                      "U12/U19: con el foco dentro el campo debe dejar de decir «importe oculto»")
        let keyboardDone = app.buttons["manualPriceKeyboardDone"]
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: 5), "U75: falta «Hecho» encima del teclado decimal")
        keyboardDone.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "exists == false"), app.keyboards.firstMatch, timeout: 5),
                      "U75: «Hecho» no quitó el teclado")
        XCTAssertTrue(field.waitForExistence(timeout: 3), "U75: el campo desapareció: «Hecho» no debe guardar ni cerrar el editor")
        let valueText = (field.value as? String) ?? ""
        XCTAssertEqual(valueText, "importe oculto", "U12/U19: el campo sin foco filtró el precio a VoiceOver: \(valueText)")
        close.tap()
    }

    /// U9: el campo de precio a mano abre sin punto de miles («3000,00»), borrar «,00» guarda 3.000 € y no 3 €.
    func testManualPriceThousands() throws {
        launch(["-MiBancoDemoCard", "inv"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")

        let ethRow = app.buttons["Ethereum"]
        scrollTo(ethRow)
        XCTAssertTrue(ethRow.waitForExistence(timeout: 10), "No se ve la fila de Ethereum")
        ethRow.tap()

        let manualButton = app.buttons["Poner precio a mano"]
        scrollTo(manualButton)
        XCTAssertTrue(manualButton.waitForExistence(timeout: 8), "Falta Poner precio a mano")
        manualButton.tap()

        let field = app.textFields["manualPriceField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Falta el campo manualPriceField")
        XCTAssertEqual(field.value as? String, "3000,00", "U9: el campo debe rellenarse sin punto de miles («3000,00»)")

        field.tap()
        // Borra ",00" (dos ⌫ y la coma) → queda "3000".
        field.typeText("\u{8}\u{8}\u{8}")
        let save = app.buttons["Guardar"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "Falta Guardar")
        save.tap()

        let priceRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Precio:' AND label CONTAINS '3.000,00' AND label CONTAINS 'a mano'"))
            .firstMatch
        XCTAssertTrue(priceRow.waitForExistence(timeout: 8), "U9: la fila Precio debe mostrar 3.000,00 € · a mano")

        let wrongTinyValue = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == '0,03 euros' OR label CONTAINS '0,03'"))
        XCTAssertEqual(wrongTinyValue.count, 0, "U9: el valor de Ethereum se corrompió a 0,03 €")
    }

    /// U13 #1: tocar la tarjeta Inversiones la voltea y «Importar de nuevo» lleva a Ajustes › Inversiones.
    func testInvestmentsCardBackImportAgain() throws {
        // `-MiBancoDemoCardElements` (DEBUG): el reverso de la tarjeta queda a la vista de XCUITest (U80).
        launch(["-MiBancoDemoCard", "inv", "-MiBancoDemoCardElements"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")

        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Inversiones' AND label CONTAINS '3 posiciones'"))
            .firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Falta la tarjeta Inversiones")
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()

        let importAgain = app.buttons["Importar de nuevo"]
        XCTAssertTrue(importAgain.waitForExistence(timeout: 8), "U13: no apareció Importar de nuevo en el reverso")
        importAgain.tap()

        let importRow = element("investments-import")
        scrollTo(importRow)
        XCTAssertTrue(importRow.waitForExistence(timeout: 10), "U13: Importar de nuevo no abrió Ajustes › Inversiones")
    }

    /// U13 #2: el segmento «Cartera» cambia a la lista de posiciones de inversión.
    func testCarteraSegmentSelectsInvestments() throws {
        launch(["-MiBancoDemoPortfolio", "-MiBancoDemoCard", "todo"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")

        let carteraSegment = app.buttons["Cartera"]
        XCTAssertTrue(carteraSegment.waitForExistence(timeout: 10), "U13: falta el segmento Cartera")
        carteraSegment.tap()

        let appleRow = app.buttons["Apple"]
        scrollTo(appleRow)
        XCTAssertTrue(appleRow.waitForExistence(timeout: 10), "U13: tocar Cartera no mostró Apple")
    }

    /// U13 #3: guardar un precio a mano y luego borrarlo devuelve la fila Precio a «mercado».
    func testManualPriceSaveAndClear() throws {
        launch(["-MiBancoDemoCard", "inv"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")

        let appleRow = app.buttons["Apple"]
        scrollTo(appleRow)
        XCTAssertTrue(appleRow.waitForExistence(timeout: 10), "No se ve Apple")
        appleRow.tap()

        let manualButton = app.buttons["Poner precio a mano"]
        scrollTo(manualButton)
        XCTAssertTrue(manualButton.waitForExistence(timeout: 8), "Falta Poner precio a mano")
        manualButton.tap()

        let field = app.textFields["manualPriceField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Falta manualPriceField")
        field.tap()
        let current = (field.value as? String) ?? ""
        if !current.isEmpty {
            field.typeText(String(repeating: "\u{8}", count: current.count + 2))
        }
        field.typeText("250")
        app.buttons["Guardar"].tap()

        let manualRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Precio:' AND label CONTAINS '250,00' AND label CONTAINS 'a mano'"))
            .firstMatch
        XCTAssertTrue(manualRow.waitForExistence(timeout: 8), "U13: no se guardó el precio manual 250,00")

        // Esperar a que se cierre el editor y volver a abrirlo para borrar el precio manual.
        Thread.sleep(forTimeInterval: 1.2)
        scrollTo(manualButton)
        manualButton.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5), "No reabrió manualPriceField")
        field.tap()
        let savedText = (field.value as? String) ?? ""
        field.typeText(String(repeating: "\u{8}", count: max(savedText.count + 2, 10)))
        app.buttons["Guardar"].tap()

        let marketRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Precio:' AND label CONTAINS 'mercado'"))
            .firstMatch
        XCTAssertTrue(marketRow.waitForExistence(timeout: 8), "U13: vaciar el precio a mano no volvió a mercado")
    }

    /// U17: el último resumen de importación en Ajustes › Inversiones desaparece al cambiar de pestaña y volver.
    func testImportFeedbackClearsOnLeave() throws {
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoInvestmentsSettings", "-MiBancoDemoImportFeedback"])
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 15), "Ajustes no aparece")

        let feedback = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'operaciones nuevas'")).firstMatch
        scrollTo(feedback)
        XCTAssertTrue(feedback.waitForExistence(timeout: 10), "U17: no se mostró el resumen de importación de demo")

        // Las pestañas se pulsan en su icono, como en `TapSmokeTests` (un `tap()` al centro del botón cae a veces en la vecina).
        app.tabBars.buttons["Inicio"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).press(forDuration: 0.25)
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 8), "No cambió a Inicio")
        app.tabBars.buttons["Ajustes"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).press(forDuration: 0.25)
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 8), "No volvió a Ajustes")

        XCTAssertFalse(feedback.waitForExistence(timeout: 2), "U17: el resumen de importación no se limpió al salir")
    }
}
