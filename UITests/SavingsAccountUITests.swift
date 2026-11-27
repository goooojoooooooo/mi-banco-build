import XCTest

/// Plan 12: la cuenta remunerada de Revolut. Con la demo `-MiBancoDemoSavings` (5.000,00 € puestos hace 3 minutos al
/// 2,00 % y un traspaso de 100,00 € después), Ajustes › Saldos la enseña bajo Revolut como «estimado», el total de Inicio
/// la suma, el ojo cerrado la tapa entera (también el interés) y corregir el saldo cambia la fila y el total.
final class SavingsAccountUITests: XCTestCase {
    /// Total de la demo sin la remunerada: 340,20 + 1.284,55 + 2.150,00 €.
    private let banksTotal = 377_475

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        // Día fijo (a mediodía): ningún cambio de día entre la base y ahora, así los intereses estimados son 0,00 €.
        app.launchArguments = ["-MiBancoDemo", "-MiBancoDemoSavings", "-MiBancoDemoToday", "2026-11-18"] + extra
            + ["-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for name in ["Permitir", "Allow"] {
            let b = springboard.alerts.buttons[name]
            if b.waitForExistence(timeout: 2) { b.tap(); break }
        }
        return app
    }

    private func eurosLabel(_ cents: Int) -> String {
        let euros = cents / 100
        let thousands = euros >= 1_000 ? "\(euros / 1_000)." + String(format: "%03d", euros % 1_000) : "\(euros)"
        return thousands + "," + String(format: "%02d", cents % 100) + " euros"
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    private func waitUntil(_ timeout: TimeInterval = 6, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return condition()
    }

    /// La fila de la remunerada en Ajustes, desplazando hasta que se vea.
    private func savingsRow(_ app: XCUIApplication) -> XCUIElement {
        let row = app.buttons["settings-savings"]
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15), "La app no arrancó")
        var tries = 0
        while !(row.waitForExistence(timeout: 2) && row.isHittable) && tries < 6 {
            app.swipeUp()
            tries += 1
        }
        XCTAssertTrue(row.exists && row.isHittable, "Falta la fila de la cuenta remunerada en Ajustes › Saldos")
        return row
    }

    func testRowUnderRevolutIsEstimatedAndCountsInTotal() {
        let app = launch(["-MiBancoDemoScreen", "ajustes"])
        let row = savingsRow(app)
        XCTAssertTrue(row.label.contains("Cuenta remunerada"), "La fila no se llama «Cuenta remunerada»: \(row.label)")
        XCTAssertTrue(row.label.contains("estimado"), "La fila no dice «estimado»: \(row.label)")
        XCTAssertTrue(row.label.contains("2,00"), "La fila no enseña el interés anual: \(row.label)")
        XCTAssertTrue(row.label.contains("5.100,00 euros"), "La fila no suma el traspaso a la base: \(row.label)")
        // Va justo debajo de Revolut en la lista de saldos.
        let saldoRev = app.textFields["Saldo de Revolut"]
        if saldoRev.exists {
            XCTAssertLessThan(saldoRev.frame.minY, row.frame.minY, "La remunerada debe ir debajo de Revolut")
        }

        app.tabBars.buttons["Inicio"].tap()
        let hero = any(app, "card-hero-all")
        XCTAssertTrue(hero.waitForExistence(timeout: 8), "Falta la cifra grande de «Todo»")
        let expected = eurosLabel(banksTotal + 510_000)
        XCTAssertTrue(waitUntil(8) { hero.label == expected }, "El total no incluye la remunerada: \(hero.label), se esperaba \(expected)")
    }

    func testEyeClosedHidesBalanceAndRate() {
        let app = launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoPrivate"])
        let row = savingsRow(app)
        XCTAssertTrue(row.label.contains("estimado"), "La fila no dice «estimado»: \(row.label)")
        XCTAssertTrue(row.label.contains("importe oculto"), "Con el ojo cerrado el saldo no está oculto: \(row.label)")
        XCTAssertNil(row.label.rangeOfCharacter(from: .decimalDigits), "Con el ojo cerrado la fila lleva cifras: \(row.label)")

        // La hoja tampoco enseña cifras: los dos campos llevan la máscara.
        row.tap()
        let balance = app.textFields["savings-balance-field"]
        XCTAssertTrue(balance.waitForExistence(timeout: 5), "No se abrió la hoja de la cuenta remunerada")
        let rate = app.textFields["savings-rate-field"]
        for field in [balance, rate] {
            let shown = (field.value as? String) ?? ""
            XCTAssertNil(shown.rangeOfCharacter(from: .decimalDigits), "Un campo enseña cifras con el ojo cerrado: \(shown)")
        }
        app.buttons["Cancelar"].tap()

        app.tabBars.buttons["Inicio"].tap()
        let hero = any(app, "card-hero-all")
        XCTAssertTrue(hero.waitForExistence(timeout: 8), "Falta la cifra grande de «Todo»")
        XCTAssertEqual(hero.label, "importe oculto", "El total no está oculto con el ojo cerrado")
    }

    func testCorrectingTheBalanceUpdatesRowAndTotal() {
        let app = launch(["-MiBancoDemoScreen", "ajustes"])
        savingsRow(app).tap()
        let balance = app.textFields["savings-balance-field"]
        XCTAssertTrue(balance.waitForExistence(timeout: 5), "No se abrió la hoja de la cuenta remunerada")
        XCTAssertEqual(balance.label, "Saldo de hoy", "Falta el campo «Saldo de hoy»")
        XCTAssertEqual(app.textFields["savings-rate-field"].label, "Interés anual (opcional)",
                       "Falta el campo «Interés anual (opcional)»")
        XCTAssertTrue(app.staticTexts["Cuenta remunerada"].exists, "Falta el título de la hoja")
        // Al final del texto, borrar lo que hay y escribir el saldo real.
        balance.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        balance.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 16) + "6000")
        app.buttons["savings-save"].tap()

        let row = app.buttons["settings-savings"]
        XCTAssertTrue(waitUntil(6) { row.exists && row.label.contains("6.000,00 euros") },
                      "La fila no enseña el saldo corregido: \(row.label)")
        XCTAssertTrue(row.label.contains("estimado"), "La fila corregida no dice «estimado»: \(row.label)")

        app.tabBars.buttons["Inicio"].tap()
        let hero = any(app, "card-hero-all")
        XCTAssertTrue(hero.waitForExistence(timeout: 8), "Falta la cifra grande de «Todo»")
        let expected = eurosLabel(banksTotal + 600_000)
        XCTAssertTrue(waitUntil(8) { hero.label == expected }, "El total no sigue a la corrección: \(hero.label), se esperaba \(expected)")
    }
}
