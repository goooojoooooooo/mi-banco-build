import XCTest

/// Toques reales sobre la guía de avisos: abrirla desde Ajustes, avanzar, retroceder, ayuda y «Abrir Atajos».
final class GuideUITests: XCTestCase {
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
        app.launchArguments = ["-MiBancoDemo", "-MiBancoDemoScreen", "ajustes", "-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()
    }

    private func openRevolutGuide() {
        let link = app.buttons["settings-alerts-guide"]
        XCTAssertTrue(link.waitForExistence(timeout: 15), "Ajustes no muestra «Avisos al instante»")
        link.tap()
        let revolut = app.buttons["guide-track-revolut"]
        XCTAssertTrue(revolut.waitForExistence(timeout: 5), "La lista de guías no aparece")
        revolut.tap()
        XCTAssertTrue(app.staticTexts["Revolut · Paso 1 de 11"].waitForExistence(timeout: 5), "No abrió el paso 1")
    }

    func testStepsAndHelp() throws {
        openRevolutGuide()
        let next = app.buttons["guide-next"]
        XCTAssertTrue(next.exists)
        next.tap()
        XCTAssertTrue(app.staticTexts["Revolut · Paso 2 de 11"].waitForExistence(timeout: 5), "Siguiente no avanzó al paso 2")
        next.tap()
        XCTAssertTrue(app.staticTexts["Revolut · Paso 3 de 11"].waitForExistence(timeout: 5), "Siguiente no avanzó al paso 3")

        let back = app.buttons["guide-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(app.staticTexts["Revolut · Paso 2 de 11"].waitForExistence(timeout: 5), "Atrás no volvió al paso 2")
        next.tap()
        XCTAssertTrue(app.staticTexts["Revolut · Paso 3 de 11"].waitForExistence(timeout: 5))

        XCTAssertFalse(app.staticTexts["guide-help-text"].exists)
        let help = app.buttons["guide-help"]
        XCTAssertTrue(help.waitForExistence(timeout: 5))
        help.tap()
        XCTAssertTrue(app.staticTexts["guide-help-text"].waitForExistence(timeout: 5), "La ayuda no se abrió")
        XCTAssertTrue(app.buttons["guide-open-shortcuts"].exists, "Falta el botón «Abrir Atajos»")
    }

    func testLastStepIsDone() throws {
        openRevolutGuide()
        let next = app.buttons["guide-next"]
        for step in 2...11 {
            next.tap()
            XCTAssertTrue(app.staticTexts["Revolut · Paso \(step) de 11"].waitForExistence(timeout: 5), "No llegó al paso \(step)")
        }
        XCTAssertEqual(next.label, "Hecho")
        next.tap()
        XCTAssertTrue(app.buttons["guide-track-revolut"].waitForExistence(timeout: 5), "«Hecho» no volvió a la lista")
    }
}
