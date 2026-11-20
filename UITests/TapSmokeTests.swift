import XCTest

/// Toques reales (no argumentos de lanzamiento) sobre los controles de Inicio y la navegación.
final class TapSmokeTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Cualquier alerta del sistema (permiso de notificaciones, etc.) se descarta sin bloquear la prueba.
        addUIInterruptionMonitor(withDescription: "Alerta del sistema") { alert in
            for name in ["Permitir", "Allow", "OK", "Aceptar", "Not Now", "Ahora no"] {
                let b = alert.buttons[name]
                if b.exists { b.tap(); return true }
            }
            return false
        }
        app = XCUIApplication()
        app.launchArguments = ["-MiBancoDemo", "-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()
        // Si aparece la alerta de notificaciones, la tocamos desde Springboard.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for name in ["Permitir", "Allow"] {
            let b = springboard.alerts.buttons[name]
            if b.waitForExistence(timeout: 2) { b.tap(); break }
        }
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")
    }

    private func button(_ label: String) -> XCUIElement { app.buttons[label] }

    private func hasKeyboardFocus(_ el: XCUIElement) -> Bool {
        (el.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }

    private func waitForFocus(_ el: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let exp = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.hasKeyboardFocus(el) }, object: nil)
        return XCTWaiter().wait(for: [exp], timeout: timeout) == .completed
    }

    func testEyeTogglesPrivacy() throws {
        let hide = button("Ocultar importes")
        XCTAssertTrue(hide.waitForExistence(timeout: 5))
        hide.tap()
        let show = button("Mostrar importes")
        XCTAssertTrue(show.waitForExistence(timeout: 5), "El ojo no cambió a Mostrar importes")
        show.tap()
        XCTAssertTrue(button("Ocultar importes").waitForExistence(timeout: 5), "El ojo no volvió a Ocultar importes")
    }

    func testEyeRespondsOffCentre() throws {
        let hide = button("Ocultar importes")
        XCTAssertTrue(hide.waitForExistence(timeout: 5))
        hide.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        XCTAssertTrue(button("Mostrar importes").waitForExistence(timeout: 5), "El ojo no respondió fuera del centro")
    }

    func testSearchOpensAndCancels() throws {
        let search = button("Buscar movimientos")
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "No apareció el campo de búsqueda")
        XCTAssertTrue(waitForFocus(field), "El campo no tiene el foco del teclado")
        field.typeText("a")
        let cancel = button("Cancelar")
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(button("Buscar movimientos").waitForExistence(timeout: 5), "Cancelar no cerró la búsqueda")
    }

    func testSearchRespondsOffCentre() throws {
        let search = button("Buscar movimientos")
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5), "La lupa no respondió fuera del centro")
    }

    func testTabsAndRowOpenDetail() throws {
        // Con cuatro pestañas, la barra de cristal del simulador de CI a veces no toma el toque sintético: toque, pulsación
        // corta y otro toque (la comprobación es la misma).
        let tabs = app.tabBars.buttons
        func open(_ name: String, until target: XCUIElement) -> Bool {
            tabs[name].tap()
            if target.waitForExistence(timeout: 8) { return true }
            tabs[name].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).press(forDuration: 0.25)
            if target.waitForExistence(timeout: 8) { return true }
            tabs[name].tap()
            return target.waitForExistence(timeout: 10)
        }
        XCTAssertTrue(open("Avisos", until: app.navigationBars["Avisos"]), "No se ve Avisos")
        XCTAssertTrue(open("Ajustes", until: app.navigationBars["Ajustes"]), "No se ve Ajustes")
        XCTAssertTrue(open("Inicio", until: app.staticTexts["Tu dinero"]), "No se ve Inicio")

        let row = app.buttons.matching(identifier: "movementRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "No hay filas de movimientos")
        row.tap()
        let close = button("Cerrar")
        XCTAssertTrue(close.waitForExistence(timeout: 5), "No se abrió la hoja de detalle")
        close.tap()
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 5))
        XCTAssertFalse(button("Cerrar").exists)
    }
}
