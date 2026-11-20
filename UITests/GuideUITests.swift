import XCTest

/// Toques reales sobre la guía de avisos: abrirla desde Ajustes, avanzar, retroceder, ayuda y «Abrir Atajos».
final class GuideUITests: XCTestCase {
    /// Pasos de la guía de Revolut (una sola acción por pantalla).
    static let revolutSteps = 20
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

    /// El contador lleva identificador, así que se lee su etiqueta («Revolut · Paso 3 de 20»), no se busca por texto.
    private func waitForStep(_ n: Int, _ message: String) {
        let counter = app.descendants(matching: .any).matching(identifier: "guide-step-counter").firstMatch
        if !counter.waitForExistence(timeout: 10) {
            // Si falla, el árbol de accesibilidad (en una línea) queda en el registro para ver qué había en pantalla.
            let tree = app.debugDescription.replacingOccurrences(of: "\n", with: " | ")
            XCTFail("\(message). Árbol: \(tree.prefix(6000))")
            return
        }
        let expected = "Revolut · Paso \(n) de \(Self.revolutSteps)"
        let reached = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: counter)
        XCTAssertEqual(XCTWaiter().wait(for: [reached], timeout: 6), .completed, "\(message) (se esperaba «\(expected)»)")
    }

    private func openRevolutGuide() {
        let link = app.buttons["settings-alerts-guide"]
        XCTAssertTrue(link.waitForExistence(timeout: 15), "Ajustes no muestra «Avisos al instante»")
        link.tap()
        let revolut = app.buttons["guide-track-revolut"]
        XCTAssertTrue(revolut.waitForExistence(timeout: 5), "La lista de guías no aparece")
        revolut.tap()
        waitForStep(1, "No abrió el paso 1")
    }

    func testStepsAndHelp() throws {
        openRevolutGuide()
        let next = app.buttons["guide-next"]
        XCTAssertTrue(next.exists)
        next.tap()
        waitForStep(2, "Siguiente no avanzó al paso 2")
        next.tap()
        waitForStep(3, "Siguiente no avanzó al paso 3")

        let back = app.buttons["guide-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        waitForStep(2, "Atrás no volvió al paso 2")
        next.tap()
        waitForStep(3, "Siguiente no avanzó otra vez al paso 3")

        XCTAssertFalse(app.staticTexts["guide-help-text"].exists)
        let help = app.buttons["guide-help"]
        XCTAssertTrue(help.waitForExistence(timeout: 5))
        help.tap()
        XCTAssertTrue(app.staticTexts["guide-help-text"].waitForExistence(timeout: 5), "La ayuda no se abrió")
        XCTAssertTrue(app.buttons["guide-open-shortcuts"].exists, "Falta el botón «Abrir Atajos»")
    }

    func testListHasOneApplePayGuidePerBank() throws {
        let link = app.buttons["settings-alerts-guide"]
        XCTAssertTrue(link.waitForExistence(timeout: 15), "Ajustes no muestra «Avisos al instante»")
        link.tap()
        for id in ["guide-track-walletImagin", "guide-track-walletRevolut", "guide-track-walletTradeRepublic"] {
            XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 5), "Falta la guía de Apple Pay: \(id)")
        }
    }

    func testLastStepIsDone() throws {
        openRevolutGuide()
        let next = app.buttons["guide-next"]
        for step in 2...Self.revolutSteps {
            next.tap()
            waitForStep(step, "No llegó al paso \(step)")
        }
        XCTAssertEqual(next.label, "Hecho")
        next.tap()
        XCTAssertTrue(app.buttons["guide-track-revolut"].waitForExistence(timeout: 5), "«Hecho» no volvió a la lista")
    }
}
