import XCTest

/// Pruebas de interfaz de Nyx Fase 2 — N9 (hoja de Nyx, puesta al día como Nyx, «Lo que he visto», acciones y privacidad).
final class NyxSheetUITests: XCTestCase {
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

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func waitFor(_ predicate: NSPredicate, _ object: Any, timeout: TimeInterval) -> Bool {
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: object)
        return XCTWaiter().wait(for: [exp], timeout: timeout) == .completed
    }

    private func isClearOfBottomBar(_ el: XCUIElement) -> Bool {
        guard el.exists && el.isHittable else { return false }
        let frame = el.frame
        let screenH = app.windows.firstMatch.frame.height
        guard screenH > 0, !frame.isEmpty else { return true }
        return frame.minY >= 80 && frame.maxY <= screenH - 125
    }

    private func scrollInNyxSheet(to el: XCUIElement, maxSwipes: Int = 12) {
        if el.waitForExistence(timeout: 2), isClearOfBottomBar(el) { return }
        let scroller = app.scrollViews["briefing-scroll"].exists ? app.scrollViews["briefing-scroll"] : app.scrollViews.firstMatch
        for _ in 0..<maxSwipes {
            if isClearOfBottomBar(el) { return }
            if el.exists && el.isHittable {
                let start = scroller.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.68))
                let end = scroller.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.36))
                start.press(forDuration: 0.05, thenDragTo: end)
                if isClearOfBottomBar(el) { return }
            } else {
                scroller.swipeUp()
            }
        }
        for _ in 0..<3 {
            if isClearOfBottomBar(el) || (el.exists && el.isHittable) { return }
            let start = scroller.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            let end = scroller.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }

    /// N9: la puesta al día abre con título «Nyx», muestra «Para tener en cuenta» (`nyx-focus`) y oculta el consejo clásico.
    func testLaPuestaAlDiaEsDeNyx() throws {
        launch(["-MiBancoDemoBriefing", "busy", "-MiBancoDemoNyx", "daily-focus"])
        XCTAssertTrue(app.buttons["Vale"].waitForExistence(timeout: 20), "No se abrió la hoja de Nyx")

        let title = element("nyx-sheet-title")
        XCTAssertTrue(title.waitForExistence(timeout: 6), "Falta la cabecera con el título «Nyx»")
        XCTAssertEqual(title.label, "Nyx", "El título de la hoja debe ser «Nyx»: \(title.label)")

        let focus = element("nyx-focus")
        scrollInNyxSheet(to: focus)
        XCTAssertTrue(focus.waitForExistence(timeout: 6), "Falta la tarjeta de foco `nyx-focus`")
        XCTAssertTrue(app.staticTexts["Para tener en cuenta"].exists, "Falta la cabecera «Para tener en cuenta»")
        XCTAssertFalse(element("briefing-tip-action").exists, "Con foco de Nyx no debe salir el consejo clásico")
    }

    /// N9: tocar «Preparar traspaso» en el cobro que no cabe abre «Mover dinero» relleno (10,00 € de imagin a Revolut).
    func testPrepararTraspasoAbreMoverDineroRelleno() throws {
        launch(["-MiBancoDemoBriefing", "busy", "-MiBancoDemoNyx", "daily-focus"])
        XCTAssertTrue(app.buttons["Vale"].waitForExistence(timeout: 20), "No se abrió la hoja de Nyx")

        let action = app.buttons["nyx-action-shortfall|rev|netflix|demo-0"]
        scrollInNyxSheet(to: action)
        XCTAssertTrue(action.waitForExistence(timeout: 8), "Falta la acción Preparar traspaso en el foco")
        XCTAssertEqual(action.label, "Preparar traspaso")
        action.tap()

        XCTAssertTrue(app.navigationBars["Mover dinero"].waitForExistence(timeout: 12), "No se abrió Mover dinero")
        let filled = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '10,00' OR value CONTAINS '10,00'"))
            .firstMatch
        XCTAssertTrue(filled.waitForExistence(timeout: 6), "Mover dinero no se abrió relleno con 10,00 €")
        let imagin = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'imagin'"))
            .firstMatch
        let revolut = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Revolut'"))
            .firstMatch
        XCTAssertTrue(imagin.exists && revolut.exists, "Mover dinero no mantiene origen imagin y destino Revolut")
    }

    /// N9: «No es mío» marca el movimiento y ofrece «Deshacer» (`nyx-undo`) para revertirlo.
    func testNoEsMioYDeshacer() throws {
        launch(["-MiBancoDemoBriefing", "busy", "-MiBancoDemoNyx", "seen-list"])
        XCTAssertTrue(app.buttons["Vale"].waitForExistence(timeout: 20), "No se abrió la hoja de Nyx")

        let notMine = app.buttons["nyx-action-unusualPayment|zara-demo-0"]
        scrollInNyxSheet(to: notMine)
        XCTAssertTrue(notMine.waitForExistence(timeout: 8), "Falta la acción «No es mío» en el pago de Zara")
        XCTAssertEqual(notMine.label, "No es mío")
        notMine.tap()

        let undo = app.buttons["nyx-undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "Falta «Deshacer» tras pulsar «No es mío»")
        undo.tap()

        XCTAssertTrue(notMine.waitForExistence(timeout: 5), "Al deshacer «No es mío» debe volver el mensaje con su acción")
    }

    /// N9: «Silenciar Zara» silencia el comercio y ofrece «Deshacer».
    func testSilenciarComercio() throws {
        launch(["-MiBancoDemoBriefing", "busy", "-MiBancoDemoNyx", "seen-list"])
        XCTAssertTrue(app.buttons["Vale"].waitForExistence(timeout: 20), "No se abrió la hoja de Nyx")

        let mute = app.buttons["nyx-action-unusualPayment|zara-demo-1"]
        scrollInNyxSheet(to: mute)
        XCTAssertTrue(mute.waitForExistence(timeout: 8), "Falta la acción «Silenciar Zara»")
        XCTAssertTrue(mute.label.contains("Silenciar"), "Etiqueta inesperada para silenciar: \(mute.label)")
        mute.tap()

        let undo = app.buttons["nyx-undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "Falta «Deshacer» tras silenciar el comercio")
        undo.tap()
        XCTAssertTrue(mute.waitForExistence(timeout: 5), "Al deshacer debe volver la acción de silenciar")
    }

    /// N9: «Descartar» enseña «Descartado» con «Deshacer», y deshacer recupera la fila.
    func testDescartarYDeshacer() throws {
        launch(["-MiBancoDemoBriefing", "busy", "-MiBancoDemoNyx", "seen-list"])
        XCTAssertTrue(app.buttons["Vale"].waitForExistence(timeout: 20), "No se abrió la hoja de Nyx")

        let dismissBtn = app.buttons["nyx-dismiss-unusualPayment|zara-demo"]
        scrollInNyxSheet(to: dismissBtn)
        XCTAssertTrue(dismissBtn.waitForExistence(timeout: 8), "Falta el botón «Descartar» en la fila de Zara")
        dismissBtn.tap()

        XCTAssertTrue(app.staticTexts["Descartado"].waitForExistence(timeout: 5), "Falta el texto «Descartado»")
        let undo = app.buttons["nyx-undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "Falta el botón «Deshacer» al descartar")
        undo.tap()

        XCTAssertTrue(dismissBtn.waitForExistence(timeout: 5), "Al deshacer no volvió la fila descartada")
    }

    /// N9: «Poner un presupuesto» abre Presupuestos en esa categoría con el importe sugerido rellenado.
    func testPonerUnPresupuestoAbreLaCategoria() throws {
        launch(["-MiBancoDemoBriefing", "busy", "-MiBancoDemoNyx", "seen-list"])
        XCTAssertTrue(app.buttons["Vale"].waitForExistence(timeout: 20), "No se abrió la hoja de Nyx")

        let setBudget = app.buttons["nyx-action-categoryAboveNormal|compras-demo-0"]
        scrollInNyxSheet(to: setBudget)
        XCTAssertTrue(setBudget.waitForExistence(timeout: 8), "Falta el botón «Poner un presupuesto»")
        XCTAssertEqual(setBudget.label, "Poner un presupuesto")
        setBudget.tap()

        XCTAssertTrue(app.navigationBars["Presupuestos"].waitForExistence(timeout: 12), "No se abrió Presupuestos")
        let comprasField = app.textFields["presupuestos.cat.compras"]
        if !comprasField.waitForExistence(timeout: 5) {
            app.swipeUp()
        }
        XCTAssertTrue(comprasField.waitForExistence(timeout: 8), "Falta el campo de presupuesto de Compras")
        let fieldVal = (comprasField.value as? String) ?? ""
        XCTAssertTrue(fieldVal.contains("90,00"), "El campo de Compras no llegó rellenado con 90,00: \(fieldVal)")
    }

    /// N9: sin observaciones en la memoria, «Lo que he visto» enseña su frase vacía exacta.
    func testListaVaciaDiceSuFrase() throws {
        launch(["-MiBancoDemoBriefing", "quiet"])
        XCTAssertTrue(app.buttons["Vale"].waitForExistence(timeout: 20), "No se abrió la hoja de Nyx")

        let empty = element("nyx-seen-empty")
        scrollInNyxSheet(to: empty)
        XCTAssertTrue(empty.waitForExistence(timeout: 8), "Falta el texto vacío de «Lo que he visto»")
        XCTAssertEqual(empty.label, "Aún no he visto nada. Lo que vea aparecerá aquí.")
    }

    /// N9 (privacidad ojo cerrado): con el ojo cerrado, ninguna fila `nyx-message-*`, ni el foco ni la línea de novedades
    /// exponen dígitos, «€» ni «%».
    func testConElOjoCerradoNingunaCifra() throws {
        launch(["-MiBancoDemoBriefing", "busy", "-MiBancoDemoNyx", "seen-list", "-MiBancoDemoPrivate"])
        XCTAssertTrue(app.buttons["Vale"].waitForExistence(timeout: 20), "No se abrió la hoja de Nyx en privado")

        let seenLine = element("nyx-seen-line")
        scrollInNyxSheet(to: seenLine)
        XCTAssertTrue(seenLine.waitForExistence(timeout: 6), "Falta la línea de novedades con el ojo cerrado")
        XCTAssertFalse(seenLine.label.contains(where: \.isNumber),
                       "Con el ojo cerrado `nyxSeenLine` expone un dígito: \(seenLine.label)")

        let seenList = element("nyx-seen-list")
        scrollInNyxSheet(to: seenList)
        XCTAssertTrue(seenList.waitForExistence(timeout: 8), "Falta la lista «Lo que he visto»")

        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'nyx-message-'"))
        XCTAssertGreaterThan(rows.count, 0, "Debe haber mensajes en «Lo que he visto»")
        for i in 0..<rows.count {
            let row = rows.element(boundBy: i)
            let lbl = row.label
            XCTAssertFalse(lbl.contains(where: \.isNumber), "Fila \(row.identifier) expone dígitos con ojo cerrado: \(lbl)")
            XCTAssertFalse(lbl.contains("€"), "Fila \(row.identifier) expone € con ojo cerrado: \(lbl)")
            XCTAssertFalse(lbl.contains("%"), "Fila \(row.identifier) expone % con ojo cerrado: \(lbl)")
            let children = row.descendants(matching: .any)
            for j in 0..<children.count {
                let child = children.element(boundBy: j)
                let cLbl = child.label
                XCTAssertFalse(cLbl.contains(where: \.isNumber), "Elemento \(child.identifier) expone dígitos con ojo cerrado: \(cLbl)")
                XCTAssertFalse(cLbl.contains("€"), "Elemento \(child.identifier) expone € con ojo cerrado: \(cLbl)")
                XCTAssertFalse(cLbl.contains("%"), "Elemento \(child.identifier) expone % con ojo cerrado: \(cLbl)")
            }
        }
    }
}
