import XCTest

final class OnboardingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testWelcomeToHome() {
        let app = XCUIApplication()
        app.launchArguments = ["-MiBancoDemo", "-MiBancoDemoOnboarding", "1"]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["Tus saldos"].waitForExistence(timeout: 15),
            "El paso 1 de bienvenida debe mostrar «Tus saldos»"
        )

        let revField = app.textFields["Saldo de Revolut"]
        if revField.waitForExistence(timeout: 5) {
            revField.tap()
            revField.typeText("340,20\n")
        }

        let nextButton = app.buttons["onboarding-next-1"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5), "Debe existir el botón Seguir")
        nextButton.tap()

        XCTAssertTrue(
            app.staticTexts["Avisos al instante"].waitForExistence(timeout: 5),
            "El paso 2 debe mostrar «Avisos al instante»"
        )

        let laterButton = app.buttons["onboarding-later"]
        XCTAssertTrue(laterButton.waitForExistence(timeout: 5), "Debe existir el botón «Lo haré luego»")
        laterButton.tap()

        XCTAssertTrue(
            app.staticTexts["Tus bancos, al día"].waitForExistence(timeout: 5),
            "El paso 3 debe mostrar «Tus bancos, al día»"
        )

        let finishButton = app.buttons["onboarding-finish"]
        XCTAssertTrue(finishButton.waitForExistence(timeout: 5), "Debe existir el botón Empezar")
        finishButton.tap()

        XCTAssertTrue(
            app.staticTexts["Tu dinero"].waitForExistence(timeout: 5),
            "Al pulsar Empezar debe abrirse Inicio («Tu dinero») en menos de 5 s"
        )
        XCTAssertFalse(
            app.buttons["Vale"].waitForExistence(timeout: 2),
            "No debe aparecer un resumen vacío tras terminar la bienvenida"
        )
    }
}
