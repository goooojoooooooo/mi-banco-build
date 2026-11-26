import XCTest

final class ImportUITests: XCTestCase {
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

    func testImportPreviewCounts() {
        let app = launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoImport"])

        let summary = app.staticTexts["import-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15), "Debe abrirse la vista previa del extracto")
        XCTAssertEqual(summary.label, "3 movimientos nuevos, 3 filas ignoradas")

        let importButton = app.buttons["import-confirm"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 5), "Debe existir el botón Importar")
        XCTAssertTrue(importButton.isEnabled)
        importButton.tap()

        let bankImportButton = app.buttons["bank-import-statement"]
        XCTAssertTrue(
            bankImportButton.waitForExistence(timeout: 5),
            "Tras importar debe volver a la pantalla del banco"
        )
        // U48 #5: tras importar no vuelve a empujarse sola la vista previa en 3 s.
        XCTAssertFalse(
            summary.waitForExistence(timeout: 3),
            "U48: la vista previa del extracto volvió a aparecer sola tras importar"
        )
    }

    func testImportHidesAmountsInPrivateMode() {
        let privateApp = launch([
            "-MiBancoDemoScreen", "ajustes",
            "-MiBancoDemoImport",
            "-MiBancoDemoPrivate",
        ])

        let scroll = privateApp.scrollViews["import-statement-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 15), "Debe abrirse la vista previa del extracto")
        XCTAssertTrue(privateApp.staticTexts["import-summary"].waitForExistence(timeout: 5))

        let balanceLine = privateApp.descendants(matching: .any)["import-latest-balance"]
        XCTAssertTrue(balanceLine.waitForExistence(timeout: 5))
        XCTAssertTrue(balanceLine.label.contains("importe oculto"), "El saldo del extracto debe anunciar importe oculto")

        let leaks = scroll.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '€'")).count
        XCTAssertEqual(leaks, 0, "En modo privado no debe quedar ningún importe con € en la vista previa del extracto")
        let privatePNG = balanceLine.screenshot().pngRepresentation

        // U48 #4: comparación visual (PNG) contra modo normal — falla si se quita `.privateAmount()`.
        let normalApp = launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoImport"])
        let normalBalance = normalApp.descendants(matching: .any)["import-latest-balance"]
        XCTAssertTrue(normalBalance.waitForExistence(timeout: 15), "Debe abrirse el saldo del extracto en modo normal")
        let normalPNG = normalBalance.screenshot().pngRepresentation
        XCTAssertNotEqual(privatePNG, normalPNG, "U48: la imagen del saldo del extracto debe cambiar con modo privado")
    }

    /// U49 #6: «Cancelar» en la vista previa vuelve a la pantalla del banco, no a Ajustes.
    func testImportPreviewCancel() {
        let app = launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoImport"])
        let cancel = app.buttons["import-cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 15), "Falta el botón Cancelar en la vista previa")
        cancel.tap()

        XCTAssertTrue(
            app.buttons["bank-import-statement"].waitForExistence(timeout: 8),
            "U49: Cancelar debe volver a la pantalla del banco"
        )
        XCTAssertFalse(
            app.staticTexts["import-summary"].waitForExistence(timeout: 2),
            "U49: la vista previa no debe reaparecer tras cancelar"
        )
    }
}
