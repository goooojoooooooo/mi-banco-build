import XCTest

final class ImportUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testImportPreviewCounts() {
        let app = XCUIApplication()
        app.launchArguments = ["-MiBancoDemo", "-MiBancoDemoScreen", "ajustes", "-MiBancoDemoImport"]
        app.launch()

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
    }

    func testImportHidesAmountsInPrivateMode() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-MiBancoDemo",
            "-MiBancoDemoScreen", "ajustes",
            "-MiBancoDemoImport",
            "-MiBancoDemoPrivate",
        ]
        app.launch()

        let scroll = app.scrollViews["import-statement-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 15), "Debe abrirse la vista previa del extracto")
        XCTAssertTrue(app.staticTexts["import-summary"].waitForExistence(timeout: 5))

        let balanceLine = app.descendants(matching: .any)["import-latest-balance"]
        XCTAssertTrue(balanceLine.waitForExistence(timeout: 5))
        XCTAssertTrue(balanceLine.label.contains("importe oculto"), "El saldo del extracto debe anunciar importe oculto")

        let leakPredicate = NSPredicate(format: "label CONTAINS '€'")
        let leaks = scroll.descendants(matching: .any).matching(leakPredicate).count
        XCTAssertEqual(leaks, 0, "En modo privado no debe quedar ningún importe con € en la vista previa del extracto")
    }
}
