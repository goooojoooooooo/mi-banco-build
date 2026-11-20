import XCTest

/// Toques reales sobre las pantallas de Plan 3 (Gasto, categoría, presupuestos, suscripciones, la categoría en la hoja
/// del movimiento y la copia de seguridad). Siempre con la demo (`-MiBancoDemo…`): datos inventados, sin red.
final class Plan3TapTests: XCTestCase {
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

    /// Cualquier elemento con ese identificador (filas combinadas, interruptores propios, etc.).
    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Desplaza la pantalla hasta que el elemento se pueda tocar (como mucho `swipes` veces).
    private func scrollTo(_ el: XCUIElement, swipes: Int = 6) {
        var left = swipes
        while left > 0 && !(el.exists && el.isHittable) {
            app.swipeUp()
            left -= 1
        }
    }

    private func openGasto() {
        launch()
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")
        app.tabBars.buttons["Gasto"].tap()
        XCTAssertTrue(element("gasto.total").waitForExistence(timeout: 8), "No se ve Gasto")
    }

    private func goBack() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    // MARK: - Gasto

    func testGastoMonthArrows() throws {
        openGasto()
        let previous = app.buttons["gasto.mesAnterior"]
        let next = app.buttons["gasto.mesSiguiente"]
        let month = element("gasto.mes")
        XCTAssertTrue(previous.waitForExistence(timeout: 5))
        XCTAssertFalse(next.isEnabled, "En el mes en curso no se puede ir al siguiente")
        XCTAssertTrue(element("gasto.prevision").exists, "El mes en curso tiene previsión")
        let current = month.label

        previous.tap()
        let changed = NSPredicate(format: "label != %@", current)
        expectation(for: changed, evaluatedWith: month)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(next.isEnabled, "Desde un mes pasado se puede volver")
        XCTAssertFalse(element("gasto.prevision").waitForExistence(timeout: 2), "Un mes pasado no tiene previsión")

        next.tap()
        expectation(for: NSPredicate(format: "label == %@", current), evaluatedWith: month)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(next.isEnabled)
    }

    func testCategoryRowOpensCategory() throws {
        openGasto()
        let row = element("gasto.fila.comerFuera")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "No hay fila de Comer fuera")
        scrollTo(row)
        row.tap()
        XCTAssertTrue(element("categoria.total").waitForExistence(timeout: 5), "No se abrió la categoría")
        let comparison = element("categoria.comparacion")
        if comparison.waitForExistence(timeout: 2) {
            XCTAssertTrue(comparison.label.contains("a estas alturas"), "La comparación del mes en curso no dice «a estas alturas»")
        }
        XCTAssertTrue(app.tabBars.buttons["Gasto"].exists, "La barra de pestañas sigue ahí")
        goBack()
        XCTAssertTrue(element("gasto.total").waitForExistence(timeout: 5), "No volvió a Gasto")
    }

    func testBudgetsFieldKeepsBadEntryAndSaves() throws {
        openGasto()
        let link = element("gasto.presupuestos")
        scrollTo(link)
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        let field = app.textFields["presupuestos.cat.supermercado"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "No se ve Presupuestos")
        XCTAssertTrue(element("presupuestos.pie").exists)

        field.tap()
        field.typeText("abc\n")
        let error = app.staticTexts["Escribe un importe como 120,00"]
        XCTAssertTrue(error.waitForExistence(timeout: 5), "Un importe mal escrito no avisa")

        // Se sale y se vuelve: el texto mal escrito sigue ahí con su error (no se pierde sin decir nada).
        goBack()
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        scrollTo(link)
        link.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Escribe un importe como 120,00"].waitForExistence(timeout: 5),
                      "El importe mal escrito se perdió al volver")

        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "100\n")
        XCTAssertFalse(app.staticTexts["Escribe un importe como 120,00"].waitForExistence(timeout: 2))
        goBack()
        scrollTo(link)
        let summary = NSPredicate(format: "label CONTAINS %@", "2 categorías")
        expectation(for: summary, evaluatedWith: link)
        waitForExpectations(timeout: 5)
    }

    func testSubscriptionsHideAndShowAgain() throws {
        openGasto()
        let link = element("gasto.suscripciones")
        scrollTo(link)
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        XCTAssertTrue(element("suscripciones.total").waitForExistence(timeout: 5), "No se ve Suscripciones")
        XCTAssertTrue(element("suscripciones.pie").exists, "Falta cómo ocultar una suscripción")
        let rows = app.descendants(matching: .any).matching(identifier: "suscripciones.fila")
        XCTAssertEqual(rows.count, 2)

        rows.element(boundBy: 0).press(forDuration: 1.2)
        let hide = app.buttons["Esto no es una suscripción"]
        XCTAssertTrue(hide.waitForExistence(timeout: 5), "No salió el menú de ocultar")
        hide.tap()
        let hidden = element("suscripciones.ocultas")
        XCTAssertTrue(hidden.waitForExistence(timeout: 5), "No aparece «Ocultas»")
        expectation(for: NSPredicate(format: "count == 1"), evaluatedWith: rows)
        waitForExpectations(timeout: 5)

        hidden.tap()
        let showAgain = app.buttons["suscripciones.volverAMostrar"]
        XCTAssertTrue(showAgain.waitForExistence(timeout: 5))
        showAgain.tap()
        XCTAssertTrue(element("suscripciones.total").waitForExistence(timeout: 5), "No volvió a Suscripciones")
        expectation(for: NSPredicate(format: "count == 2"), evaluatedWith: rows)
        waitForExpectations(timeout: 5)
    }

    // MARK: - Categoría y traspaso en la hoja del movimiento

    func testSheetCategoryChipTileAndSwitches() throws {
        launch()
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")
        let row = app.buttons.matching(identifier: "movementRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let chip = app.buttons["category-chip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "La hoja no tiene la fila de categoría")
        let original = chip.label

        chip.tap()
        let tile = app.buttons["category-tile-comerFuera"]
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "No se desplegó la rejilla")
        XCTAssertTrue(element("category-apply-merchant").exists, "Falta «Aplicar a todo»")
        tile.tap()
        expectation(for: NSPredicate(format: "label == %@", "Categoría: Comer fuera"), evaluatedWith: chip)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(tile.waitForExistence(timeout: 1), "La rejilla no se plegó")

        // Volver a la categoría automática.
        chip.tap()
        let automatic = app.buttons["category-automatic"]
        XCTAssertTrue(automatic.waitForExistence(timeout: 5), "Falta «Volver a la categoría automática»")
        automatic.tap()
        expectation(for: NSPredicate(format: "label == %@", original), evaluatedWith: chip)
        waitForExpectations(timeout: 5)

        // Traspaso entre tus cuentas: la fila de categoría se va y vuelve.
        let transfer = element("own-transfer-toggle")
        scrollTo(transfer, swipes: 2)
        XCTAssertTrue(transfer.waitForExistence(timeout: 5))
        transfer.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: chip)
        waitForExpectations(timeout: 5)
        transfer.tap()
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "La categoría no volvió al apagar el traspaso")
    }

    // MARK: - Copia de seguridad

    func testBackupRowsInSettings() throws {
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoBackup"])
        let save = element("backup-save")
        XCTAssertTrue(save.waitForExistence(timeout: 15), "No se ven las filas de copia de seguridad")
        scrollTo(save)
        XCTAssertTrue(element("backup-csv").exists)
        XCTAssertTrue(element("backup-restore").exists)
        XCTAssertTrue(element("backup-previous").exists, "Falta «Volver a lo de antes de restaurar» en la demo")

        save.tap()
        let share = app.otherElements["ActivityListView"]
        XCTAssertTrue(share.waitForExistence(timeout: 15), "No se abrió la hoja de compartir")
        for name in ["Cerrar", "Close"] where app.buttons[name].exists {
            app.buttons[name].tap()
            break
        }
        if share.exists { share.swipeDown(velocity: .fast) }
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: share)
        waitForExpectations(timeout: 8)
    }

    func testRestoreSheetCancelAndSlide() throws {
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoRestorePreview"])
        let cancel = app.buttons["restore-cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 15), "No se abrió la confirmación de restaurar")
        cancel.tap()
        XCTAssertFalse(cancel.waitForExistence(timeout: 3), "Cancelar no cerró la hoja")

        // Se relanza y esta vez se desliza hasta el final: la copia se restaura y la hoja se cierra.
        app.terminate()
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoRestorePreview"])
        let slide = element("restore-slide")
        XCTAssertTrue(slide.waitForExistence(timeout: 15))
        let frame = slide.frame
        let start = slide.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 28, dy: frame.height / 2))
        let end = slide.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.width - 6, dy: frame.height / 2))
        start.press(forDuration: 0.1, thenDragTo: end)
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: slide)
        waitForExpectations(timeout: 10)
    }
}
