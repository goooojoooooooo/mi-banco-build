import XCTest

/// Toques reales sobre «Mover dinero», acciones rápidas, «Cuentas y contactos» y «Próximos cobros» (Plan 4b, tareas 8 y 16).
/// Siempre en modo demo (`-MiBancoDemo…`): datos ficticios e IBANs de ejemplo publicados, sin red ni Llavero real.
final class MoveMoneyUITests: XCTestCase {
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

    func testMoveToRevolut() throws {
        launch(["-MiBancoDemoCard", "ima"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")

        let moveButton = app.buttons["Mover dinero"]
        XCTAssertTrue(moveButton.waitForExistence(timeout: 10), "Falta la acción rápida Mover dinero")
        moveButton.tap()

        XCTAssertTrue(app.navigationBars["Mover dinero"].waitForExistence(timeout: 8), "No se abrió la hoja Mover dinero")

        let revolutTarget = element("move-target-rev")
        scrollTo(revolutTarget)
        XCTAssertTrue(revolutTarget.waitForExistence(timeout: 8), "No aparece Revolut como destino")
        revolutTarget.tap()

        let key2 = app.buttons["2"]
        let key0 = app.buttons["0"]
        XCTAssertTrue(key2.waitForExistence(timeout: 8), "No apareció el teclado de importe")
        key2.tap()
        key0.tap()
        key0.tap()

        let expectedAmount = "200,00\(nbsp)€"
        let amountText = app.staticTexts[expectedAmount]
        XCTAssertTrue(amountText.waitForExistence(timeout: 5), "El importe no mostró \(expectedAmount)")

        let slider = element("move-slide")
        scrollTo(slider)
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "Falta Desliza para preparar")
        let start = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        let end = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)

        let copied = app.staticTexts["IBAN de Revolut copiado"]
        XCTAssertTrue(copied.waitForExistence(timeout: 10), "No apareció IBAN de Revolut copiado")

        let openBank = app.buttons["Abrir imagin"]
        let fallbackHint = app.staticTexts["Abre imagin y pega el IBAN."]
        XCTAssertTrue(openBank.exists || fallbackHint.exists, "Falta el botón Abrir imagin o la instrucción alternativa")

        let close = app.buttons["Cerrar"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "Falta el botón Cerrar")
        close.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "exists == false"), copied, timeout: 8), "La hoja Mover dinero no se cerró")
    }

    func testCopyIban() throws {
        launch(["-MiBancoDemoCard", "ima"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")

        let copyButton = app.buttons["Copiar IBAN"]
        XCTAssertTrue(copyButton.waitForExistence(timeout: 10), "Falta la acción rápida Copiar IBAN")
        copyButton.tap()

        let toast = app.staticTexts["IBAN copiado · se borra en 3 min"]
        XCTAssertTrue(toast.waitForExistence(timeout: 5), "No apareció el aviso de IBAN copiado")
    }

    func testAccountsScreen() throws {
        launch(["-MiBancoDemoScreen", "ajustes"])
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 15), "No se ve Ajustes")

        let row = element("settings-accounts")
        scrollTo(row)
        XCTAssertTrue(row.waitForExistence(timeout: 8), "Falta Cuentas y contactos en Ajustes")
        row.tap()

        XCTAssertTrue(app.navigationBars["Cuentas y contactos"].waitForExistence(timeout: 8), "No se abrió Cuentas y contactos")

        let maskedIma = app.staticTexts["ES91 •••• 1332"]
        scrollTo(maskedIma)
        XCTAssertTrue(maskedIma.waitForExistence(timeout: 8), "No aparece el IBAN enmascarado ES91 •••• 1332")

        let addContact = app.buttons["Añadir contacto"]
        scrollTo(addContact)
        XCTAssertTrue(addContact.waitForExistence(timeout: 8), "Falta el botón Añadir contacto")
        addContact.tap()

        let nameField = app.textFields["payeeNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Falta el campo de nombre")
        nameField.tap()
        nameField.typeText("Prueba")

        let ibanField = app.textFields["payeeIBANField"]
        XCTAssertTrue(ibanField.waitForExistence(timeout: 5), "Falta el campo de IBAN del contacto")
        ibanField.tap()
        ibanField.typeText("ES91 2100")

        let saveButton = app.buttons["Guardar contacto"]
        scrollTo(saveButton)
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Falta Guardar contacto")
        saveButton.tap()

        let errorText = app.staticTexts["Ese IBAN no es correcto: revisa los números."]
        XCTAssertTrue(errorText.waitForExistence(timeout: 5), "No apareció el aviso de IBAN incorrecto")
    }

    func testMoveSheetDismissesOnBackground() throws {
        launch(["-MiBancoDemoCard", "ima"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")

        let moveButton = app.buttons["Mover dinero"]
        XCTAssertTrue(moveButton.waitForExistence(timeout: 10), "Falta Mover dinero")
        moveButton.tap()
        XCTAssertTrue(app.navigationBars["Mover dinero"].waitForExistence(timeout: 8), "No se abrió la hoja Mover dinero")

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1.0)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "La app no volvió a primer plano")

        let nav = app.navigationBars["Mover dinero"]
        XCTAssertTrue(waitFor(NSPredicate(format: "exists == false"), nav, timeout: 8), "La hoja Mover dinero no se cerró al pasar a segundo plano")
    }

    func testUpcomingCalendarOpensFromSpending() throws {
        launch(["-MiBancoDemoScreen", "gasto"])
        let link = element("gasto.proximos")
        scrollTo(link)
        XCTAssertTrue(link.waitForExistence(timeout: 15), "Falta Próximos cobros en Gasto")
        link.tap()

        XCTAssertTrue(app.navigationBars["Próximos cobros"].waitForExistence(timeout: 8), "No se abrió Próximos cobros")
        let netflix = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Netflix'")).firstMatch
        scrollTo(netflix)
        XCTAssertTrue(netflix.waitForExistence(timeout: 8), "Netflix no aparece en los próximos 14 días")
    }
}
