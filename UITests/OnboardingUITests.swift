import XCTest

final class OnboardingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testWelcomeToHome() {
        let app = XCUIApplication()
        // U48 #1: pasa `-MiBancoDemoBriefing quiet` para comprobar que `markOnboardingCompleted()` evita el resumen tras la bienvenida.
        app.launchArguments = [
            "-MiBancoDemo", "-MiBancoDemoOnboarding", "1", "-MiBancoDemoBriefing", "quiet",
            "-AppleLanguages", "(es)", "-AppleLocale", "es_ES",
        ]
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for name in ["Permitir", "Allow"] {
            let b = springboard.alerts.buttons[name]
            if b.waitForExistence(timeout: 2) { b.tap(); break }
        }

        XCTAssertTrue(
            app.staticTexts["Tus saldos"].waitForExistence(timeout: 15),
            "El paso 1 de bienvenida debe mostrar «Tus saldos»"
        )

        // U48 #2 + #3: sin `if`; escribe 340,20 en Revolut y pasa al paso 2 («Avisos al instante»).
        let revField = app.textFields["Saldo de Revolut"]
        XCTAssertTrue(revField.waitForExistence(timeout: 5), "U48: falta el campo Saldo de Revolut en el paso 1")
        revField.tap()
        revField.typeText("340,20\n")

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
            app.buttons["Vale"].waitForExistence(timeout: 5),
            "U48: no debe aparecer un resumen tras terminar la bienvenida"
        )
    }

    /// U49 #7: botones «Saltar», «Empezar la guía», «Conectar ahora» e interruptor «Bloquear con Face ID».
    func testOnboardingButtons() {
        func launchStep(_ step: String) -> XCUIApplication {
            let app = XCUIApplication()
            app.launchArguments = ["-MiBancoDemo", "-MiBancoDemoOnboarding", step, "-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
            app.launch()
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            for name in ["Permitir", "Allow"] {
                let b = springboard.alerts.buttons[name]
                if b.waitForExistence(timeout: 2) { b.tap(); break }
            }
            return app
        }

        // 1. Saltar → Inicio («Tu dinero»).
        let skipApp = launchStep("1")
        let skip = skipApp.buttons["onboarding-skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 15), "U49: falta Saltar")
        skip.tap()
        XCTAssertTrue(skipApp.staticTexts["Tu dinero"].waitForExistence(timeout: 8), "U49: Saltar debe abrir Inicio")

        // 2. Empezar la guía → guía de avisos al instante.
        let guideApp = launchStep("2")
        let startGuide = guideApp.buttons["onboarding-start-guide"]
        XCTAssertTrue(startGuide.waitForExistence(timeout: 15), "U49: falta Empezar la guía")
        startGuide.tap()
        XCTAssertTrue(guideApp.navigationBars["Avisos al instante"].waitForExistence(timeout: 8), "U49: Empezar la guía debe abrir Avisos al instante")

        // 3. Interruptor Face ID + Conectar ahora → Ajustes › Bancos.
        let step3App = launchStep("3")
        let faceID = step3App.switches.firstMatch
        XCTAssertTrue(faceID.waitForExistence(timeout: 15), "U49: falta el interruptor Bloquear con Face ID")
        let before = faceID.value as? String
        faceID.tap()
        let after = faceID.value as? String
        XCTAssertNotEqual(before, after, "U49: tocar Bloquear con Face ID debe cambiar su valor")

        let connectNow = step3App.buttons["onboarding-connect-now"]
        XCTAssertTrue(connectNow.waitForExistence(timeout: 5), "U49: falta Conectar ahora")
        connectNow.tap()
        XCTAssertTrue(step3App.buttons["settings-bank-rev"].waitForExistence(timeout: 10), "U49: Conectar ahora debe abrir Ajustes › Bancos")
    }

    /// U62: arrancar directamente en el paso 2 (`-MiBancoDemoOnboarding 2`) muestra «Avisos al instante» y «Empezar la guía».
    func testOnboardingStartsOnStep2() {
        let app = XCUIApplication()
        app.launchArguments = ["-MiBancoDemo", "-MiBancoDemoOnboarding", "2", "-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for name in ["Permitir", "Allow"] {
            let b = springboard.alerts.buttons[name]
            if b.waitForExistence(timeout: 2) { b.tap(); break }
        }

        XCTAssertTrue(
            app.staticTexts["Avisos al instante"].waitForExistence(timeout: 15),
            "U62: el paso 2 directo debe mostrar «Avisos al instante»"
        )
        XCTAssertTrue(
            app.buttons["Empezar la guía"].waitForExistence(timeout: 5),
            "U62: el paso 2 directo debe mostrar «Empezar la guía»"
        )
    }

    /// U62: llegar al paso 2 desde el paso 1 tocando «Seguir».
    func testOnboardingStep1ToStep2() {
        let app = XCUIApplication()
        app.launchArguments = ["-MiBancoDemo", "-MiBancoDemoOnboarding", "1", "-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for name in ["Permitir", "Allow"] {
            let b = springboard.alerts.buttons[name]
            if b.waitForExistence(timeout: 2) { b.tap(); break }
        }

        XCTAssertTrue(app.staticTexts["Tus saldos"].waitForExistence(timeout: 15))
        let nextButton = app.buttons["onboarding-next-1"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        nextButton.tap()

        XCTAssertTrue(
            app.staticTexts["Avisos al instante"].waitForExistence(timeout: 5),
            "U62: tras Seguir debe aparecer «Avisos al instante»"
        )
        XCTAssertTrue(
            app.buttons["Empezar la guía"].waitForExistence(timeout: 5),
            "U62: tras Seguir debe aparecer «Empezar la guía»"
        )
    }
}
