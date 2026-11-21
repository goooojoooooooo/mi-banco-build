import XCTest

final class BanksUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-MiBancoDemo"] + extra + ["-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for name in ["Permitir", "Allow"] {
            let b = springboard.alerts.buttons[name]
            if b.waitForExistence(timeout: 2) { b.tap(); break }
        }
        return app
    }

    func testBanksScreenShowsStatus() {
        let app = launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoBanks"])

        let revRow = app.buttons["settings-bank-rev"]
        XCTAssertTrue(revRow.waitForExistence(timeout: 15), "Debe existir la fila de Revolut en Ajustes › Bancos")
        XCTAssertTrue(
            app.staticTexts["Actualizado hace 5 min · exacto"].waitForExistence(timeout: 10),
            "Debe verse el estado exacto de Revolut"
        )
        XCTAssertTrue(
            app.staticTexts["Importa su extracto"].waitForExistence(timeout: 10),
            "Debe verse el estado de Trade Republic sin conexión"
        )

        let imaRow = app.buttons["settings-bank-ima"]
        XCTAssertTrue(imaRow.waitForExistence(timeout: 5), "Debe existir la fila de imagin")
        imaRow.tap()

        XCTAssertTrue(
            app.staticTexts["Caduca en 9 días"].waitForExistence(timeout: 10),
            "En la pantalla de imagin debe verse que el consentimiento caduca en 9 días"
        )
        XCTAssertTrue(
            app.buttons["Renovar conexión"].waitForExistence(timeout: 5),
            "Debe mostrarse el botón para renovar la conexión"
        )
        XCTAssertTrue(
            app.buttons["bank-import-statement"].waitForExistence(timeout: 5),
            "Debe mostrarse el botón para importar extracto"
        )
    }

    func testConnectionGuideSteps() {
        let app = launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoGuide"])

        XCTAssertTrue(
            app.staticTexts["Paso 1 de 4"].waitForExistence(timeout: 15),
            "Debe abrirse la guía de conexión en el paso 1"
        )
        XCTAssertTrue(
            app.staticTexts["Crea tu cuenta gratis"].waitForExistence(timeout: 5),
            "Debe verse el título del paso 1"
        )

        let nextButton = app.buttons["guide-next"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        nextButton.tap()

        XCTAssertTrue(
            app.staticTexts["Paso 2 de 4"].waitForExistence(timeout: 5),
            "Debe avanzar al paso 2"
        )
        let copyButton = app.buttons["guide-copy-redirect"]
        XCTAssertTrue(copyButton.waitForExistence(timeout: 5))
        copyButton.tap()
        XCTAssertTrue(
            app.staticTexts["Copiada"].waitForExistence(timeout: 5),
            "Copiar dirección debe cambiar la etiqueta a Copiada"
        )
    }
}
