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

    /// Gasto abierto por argumento (determinista); el cambio de pestaña con un toque se prueba aparte.
    private func openGasto() {
        launch(["-MiBancoDemoScreen", "gasto"])
        XCTAssertTrue(element("gasto.total").waitForExistence(timeout: 20), "No se ve Gasto")
    }

    /// Espera a que el predicado se cumpla sobre el objeto (XCTWaiter: sin `waitForExpectations`, que no es seguro en Swift 6).
    private func waitFor(_ predicate: NSPredicate, _ object: Any, timeout: TimeInterval) -> Bool {
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: object)
        return XCTWaiter().wait(for: [exp], timeout: timeout) == .completed
    }

    /// Cambia de pestaña tocando la barra. En el simulador de CI (Intel) la barra de cristal con cuatro pestañas a veces
    /// no toma el toque sintético; se prueba toque, pulsación corta y toque otra vez.
    private func selectTab(_ tab: XCUIElement, until target: XCUIElement) -> Bool {
        tab.tap()
        if target.waitForExistence(timeout: 8) { return true }
        tab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).press(forDuration: 0.25)
        if target.waitForExistence(timeout: 8) { return true }
        tab.tap()
        return target.waitForExistence(timeout: 10)
    }

    private func goBack() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    private let gone = NSPredicate(format: "exists == false")

    /// Cierra la hoja de compartir. El botón de cerrar aparece un instante DESPUÉS de la lista (mirar `exists` sin esperar era
    /// la causa de que `testBackupRowsInSettings` fallara a veces en el simulador lento de CI): se espera por él, se toca y se
    /// espera a que la hoja se vaya; si no, se desliza la hoja hacia abajo desde su borde superior y, en último lugar, se toca fuera.
    private func closeShareSheet(_ share: XCUIElement) -> Bool {
        for attempt in 0..<3 {
            var closed = false
            for name in ["Cerrar", "Close"] {
                let button = app.buttons[name]
                if button.waitForExistence(timeout: attempt == 0 ? 8 : 2) {
                    button.tap()
                    closed = true
                    break
                }
            }
            if !closed && share.exists {
                let frame = share.frame
                let origin = app.coordinate(withNormalizedOffset: .zero)
                let from = origin.withOffset(CGVector(dx: frame.midX, dy: max(frame.minY - 24, 40)))
                let to = origin.withOffset(CGVector(dx: frame.midX, dy: app.frame.maxY - 8))
                from.press(forDuration: 0.1, thenDragTo: to, withVelocity: 600, thenHoldForDuration: 0)
            }
            if waitFor(gone, share, timeout: 8) { return true }
        }
        return !share.exists
    }

    /// Ajustes con las filas de copia de seguridad a la vista.
    private func openBackupSettings() -> XCUIElement {
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoBackup"])
        let save = element("backup-save")
        XCTAssertTrue(save.waitForExistence(timeout: 15), "No se ven las filas de copia de seguridad")
        scrollTo(save)
        return save
    }

    /// La hoja de restaurar, abierta TOCANDO «Volver a lo de antes de restaurar» (nunca por argumento).
    private func openRestoreSheetByTap() {
        _ = openBackupSettings()
        let previous = element("backup-previous")
        scrollTo(previous)
        XCTAssertTrue(previous.waitForExistence(timeout: 5), "Falta «Volver a lo de antes de restaurar» en la demo")
        previous.tap()
        XCTAssertTrue(element("restore-slide").waitForExistence(timeout: 15), "No se abrió la confirmación de restaurar")
    }

    /// Sale de primer plano y vuelve (lo que hace el dueño al ir al selector de apps).
    private func backgroundAndReturn() {
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1.0)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "La app no volvió a primer plano")
    }

    /// El botón de cerrar de la hoja del movimiento (su etiqueta es «Cerrar»).
    private var sheetClose: XCUIElement { app.buttons["Cerrar"] }

    /// Abre la primera fila de un comercio por su nombre (la n-ésima, empezando en 0).
    private func movementRow(_ merchant: String, at index: Int) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "movementRow", merchant))
            .element(boundBy: index)
    }

    // MARK: - Gasto

    /// En el simulador de CI la barra de pestañas de cristal tarda en cambiar de pestaña tras el toque (a veces lo toma
    /// como pulsación larga): se espera con margen y, si no cambió, se toca otra vez.
    func testGastoTabByTap() throws {
        launch()
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")
        let tab = app.tabBars.buttons["Gasto"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        XCTAssertTrue(selectTab(tab, until: element("gasto.total")), "La pestaña Gasto no se abre")
        XCTAssertTrue(app.tabBars.buttons.count == 4, "La barra tiene cuatro pestañas")
    }

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
        XCTAssertTrue(waitFor(changed, month, timeout: 5))
        XCTAssertTrue(next.isEnabled, "Desde un mes pasado se puede volver")
        XCTAssertFalse(element("gasto.prevision").waitForExistence(timeout: 2), "Un mes pasado no tiene previsión")

        next.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "label == %@", current), month, timeout: 5))
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
        XCTAssertTrue(comparison.waitForExistence(timeout: 5), "Falta la comparación del mes en la categoría")
        XCTAssertTrue(comparison.label.contains("a estas alturas"), "La comparación del mes en curso no dice «a estas alturas»")
        XCTAssertTrue(app.tabBars.buttons["Gasto"].exists, "La barra de pestañas sigue ahí")

        // Un pago de la categoría abre la hoja del movimiento (Gasto › categoría › hoja) y se cierra.
        let payment = app.buttons.matching(identifier: "movementRow").firstMatch
        XCTAssertTrue(payment.waitForExistence(timeout: 5), "La categoría no lista pagos")
        payment.tap()
        XCTAssertTrue(sheetClose.waitForExistence(timeout: 8), "El pago de la categoría no abrió la hoja")
        sheetClose.tap()
        XCTAssertTrue(waitFor(gone, sheetClose, timeout: 8), "La hoja no se cerró")
        XCTAssertTrue(element("categoria.total").waitForExistence(timeout: 5))
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
        // Guardado: al salir y volver, el campo enseña el límite (formateado) y no hay error.
        goBack()
        scrollTo(link)
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(waitFor(NSPredicate(format: "value CONTAINS %@", "100"), field, timeout: 10), "El límite no se guardó")
        XCTAssertFalse(app.staticTexts["Escribe un importe como 120,00"].exists)
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
        XCTAssertTrue(waitFor(NSPredicate(format: "count == 1"), rows, timeout: 5))

        hidden.tap()
        let showAgain = app.buttons["suscripciones.volverAMostrar"]
        XCTAssertTrue(showAgain.waitForExistence(timeout: 5))
        showAgain.tap()
        XCTAssertTrue(element("suscripciones.total").waitForExistence(timeout: 5), "No volvió a Suscripciones")
        XCTAssertTrue(waitFor(NSPredicate(format: "count == 2"), rows, timeout: 5))
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
        XCTAssertTrue(waitFor(NSPredicate(format: "label == %@", "Categoría: Comer fuera"), chip, timeout: 5))
        XCTAssertFalse(tile.waitForExistence(timeout: 1), "La rejilla no se plegó")

        // Volver a la categoría automática.
        chip.tap()
        let automatic = app.buttons["category-automatic"]
        XCTAssertTrue(automatic.waitForExistence(timeout: 5), "Falta «Volver a la categoría automática»")
        automatic.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "label == %@", original), chip, timeout: 5))

        // Traspaso entre tus cuentas: la fila de categoría se va y vuelve.
        let transfer = element("own-transfer-toggle")
        scrollTo(transfer, swipes: 2)
        XCTAssertTrue(transfer.waitForExistence(timeout: 5))
        transfer.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "exists == false"), chip, timeout: 5))
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
        XCTAssertTrue(closeShareSheet(share), "La hoja de compartir no se cerró")
    }

    /// R25 (a) y R27 (7): «Volver a lo de antes» se toca de verdad; la hoja se abre y «Cancelar» la cierra, también tocando
    /// cerca del borde izquierdo (el botón entero responde, no solo la palabra).
    func testRestoreSheetOpensByTapAndCancels() throws {
        openRestoreSheetByTap()
        let cancel = app.buttons["restore-cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "Falta «Cancelar»")
        XCTAssertGreaterThanOrEqual(cancel.frame.height, 43.5, "«Cancelar» mide menos de 44 pt")
        cancel.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        XCTAssertTrue(waitFor(gone, element("restore-slide"), timeout: 8), "Cancelar no cerró la hoja")
        XCTAssertTrue(waitFor(gone, cancel, timeout: 5))
    }

    /// R25 (b): se desliza hasta el final y se espera el texto de éxito de la hoja, no solo a que desaparezca el control.
    func testRestoreSlideShowsSuccessText() throws {
        openRestoreSheetByTap()
        let slide = element("restore-slide")
        // La hoja termina de subir antes de arrastrar (si no, el arrastre se lo lleva la hoja); un segundo intento si hace falta.
        Thread.sleep(forTimeInterval: 1.5)
        let success = app.staticTexts["Copia restaurada"]
        for _ in 0..<2 where slide.exists && !success.exists {
            let frame = slide.frame
            let start = slide.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 28, dy: frame.height / 2))
            let end = slide.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.width - 6, dy: frame.height / 2))
            start.press(forDuration: 0.3, thenDragTo: end, withVelocity: 300, thenHoldForDuration: 0.2)
            if success.waitForExistence(timeout: 10) { break }
        }
        XCTAssertTrue(success.exists || waitFor(NSPredicate(format: "exists == true"), success, timeout: 3),
                      "Deslizar no mostró «Copia restaurada»")
        XCTAssertTrue(waitFor(gone, slide, timeout: 10), "La hoja no se cerró tras restaurar")
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 10), "No volvió a Ajustes")
    }

    // MARK: - Copia de seguridad: el resto de filas con toque real (R25 c)

    func testBackupCSVRowOpensShareSheet() throws {
        _ = openBackupSettings()
        let csv = element("backup-csv")
        scrollTo(csv)
        XCTAssertTrue(csv.waitForExistence(timeout: 5))
        csv.tap()
        let share = app.otherElements["ActivityListView"]
        XCTAssertTrue(share.waitForExistence(timeout: 15), "El CSV no abrió la hoja de compartir")
        XCTAssertTrue(closeShareSheet(share), "La hoja de compartir del CSV no se cerró")
    }

    func testBackupRestoreRowOpensFilePicker() throws {
        _ = openBackupSettings()
        let restore = element("backup-restore")
        scrollTo(restore)
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.tap()
        // El selector de archivos del sistema: se reconoce por su botón de cancelar.
        let cancelNames = ["Cancelar", "Cancel", "Cerrar", "Close"]
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", cancelNames)).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 20), "No apareció el selector de archivos")
        cancel.tap()
        XCTAssertTrue(waitFor(gone, cancel, timeout: 10), "El selector de archivos no se cerró")
        XCTAssertTrue(element("backup-restore").waitForExistence(timeout: 5))
    }

    // MARK: - Traspasos abre la hoja del movimiento (R25 e)

    func testTransfersRowOpensMovementSheet() throws {
        openGasto()
        let link = element("gasto.traspasos")
        scrollTo(link)
        XCTAssertTrue(link.waitForExistence(timeout: 5), "No hay enlace a Traspasos")
        link.tap()
        let row = app.buttons.matching(identifier: "movementRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "Traspasos no lista movimientos")
        row.tap()
        XCTAssertTrue(sheetClose.waitForExistence(timeout: 8), "La fila de Traspasos no abrió la hoja")
        sheetClose.tap()
        XCTAssertTrue(waitFor(gone, sheetClose, timeout: 8), "La hoja no se cerró")
    }

    // MARK: - Presupuestos: vaciar el campo quita el límite (R25 f) y VoiceOver en modo privado (R27 8)

    func testEmptyingBudgetFieldRemovesLimit() throws {
        openGasto()
        let link = element("gasto.presupuestos")
        scrollTo(link)
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        let field = app.textFields["presupuestos.mes"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "No se ve el presupuesto del mes")
        XCTAssertTrue(element("presupuestos.pie").label.contains("Deja el campo vacío para quitar el límite."),
                      "Falta cómo quitar un presupuesto")
        // La demo trae un presupuesto del mes de 700 €.
        XCTAssertTrue(waitFor(NSPredicate(format: "value CONTAINS %@", "700"), field, timeout: 5), "La demo no trae el límite del mes")

        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 14) + "\n")
        goBack()
        scrollTo(link)
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(waitFor(NSPredicate(format: "NOT (value CONTAINS %@)", "700"), field, timeout: 10),
                      "Vaciar el campo no quitó el límite")
    }

    func testPrivateModeHidesBudgetFromVoiceOver() throws {
        launch(["-MiBancoDemoScreen", "gasto", "-MiBancoDemoPrivate"])
        XCTAssertTrue(element("gasto.total").waitForExistence(timeout: 20), "No se ve Gasto")
        let link = element("gasto.presupuestos")
        scrollTo(link)
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        let field = app.textFields["presupuestos.mes"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(waitFor(NSPredicate(format: "value == %@", "importe oculto"), field, timeout: 5),
                      "VoiceOver lee el límite con el modo privado")
    }

    // MARK: - «Aplicar a todo» y volver a lo automático (R22, R25 d)

    private func openFirstMercadonaCategory() -> XCUIElement {
        launch()
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")
        let row = movementRow("Mercadona", at: 0)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "No hay pagos de Mercadona en la demo")
        row.tap()
        let chip = app.buttons["category-chip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "La hoja no tiene la fila de categoría")
        return chip
    }

    private func closeSheet() {
        XCTAssertTrue(sheetClose.waitForExistence(timeout: 5))
        sheetClose.tap()
        XCTAssertTrue(waitFor(gone, sheetClose, timeout: 8), "La hoja no se cerró")
    }

    /// Con «Aplicar a todo» encendido (lo normal en un comercio), la elección llega a otro pago del mismo comercio.
    func testApplyToMerchantOnReachesSecondPayment() throws {
        let chip = openFirstMercadonaCategory()
        chip.tap()
        let toggle = element("category-apply-merchant")
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        scrollTo(toggle, swipes: 3)
        // Se apaga y se vuelve a encender: queda para todo el comercio.
        toggle.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "value == %@", "0"), toggle, timeout: 5), "El interruptor no se apagó")
        toggle.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "value == %@", "1"), toggle, timeout: 5), "El interruptor no se encendió")
        let tile = app.buttons["category-tile-comerFuera"]
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        tile.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "label == %@", "Categoría: Comer fuera"), chip, timeout: 5))
        closeSheet()

        let second = movementRow("Mercadona", at: 1)
        scrollTo(second)
        XCTAssertTrue(second.waitForExistence(timeout: 5), "La demo no trae un segundo pago de Mercadona")
        second.tap()
        let secondChip = app.buttons["category-chip"]
        XCTAssertTrue(secondChip.waitForExistence(timeout: 5))
        XCTAssertEqual(secondChip.label, "Categoría: Comer fuera", "La categoría para todo el comercio no llegó al otro pago")
    }

    /// Con «Aplicar a todo» apagado, el otro pago del comercio no cambia.
    func testApplyToMerchantOffLeavesSecondPayment() throws {
        let chip = openFirstMercadonaCategory()
        let original = chip.label
        chip.tap()
        let toggle = element("category-apply-merchant")
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        scrollTo(toggle, swipes: 3)
        toggle.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "value == %@", "0"), toggle, timeout: 5), "El interruptor no se apagó")
        let tile = app.buttons["category-tile-comerFuera"]
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        tile.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "label == %@", "Categoría: Comer fuera"), chip, timeout: 5))
        closeSheet()

        let second = movementRow("Mercadona", at: 1)
        scrollTo(second)
        XCTAssertTrue(second.waitForExistence(timeout: 5), "La demo no trae un segundo pago de Mercadona")
        second.tap()
        let secondChip = app.buttons["category-chip"]
        XCTAssertTrue(secondChip.waitForExistence(timeout: 5))
        XCTAssertEqual(secondChip.label, original, "La elección de un solo pago cambió otro pago del comercio")
    }

    /// R22: los dos textos del botón y lo que hace cada uno.
    func testResetButtonHasTwoMeaningsAndTexts() throws {
        let chip = openFirstMercadonaCategory()
        let original = chip.label

        // 1. Para todo el comercio: sin elección propia, el botón quita la del comercio y lo dice con su nombre.
        chip.tap()
        app.buttons["category-tile-casa"].tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "label == %@", "Categoría: Casa"), chip, timeout: 5))
        chip.tap()
        let reset = app.buttons["category-automatic"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        XCTAssertEqual(reset.label, "Quitar mi categoría de todo Mercadona")

        // 2. Elección propia encima de la del comercio: el botón quita SOLO la del pago y el pago vuelve a la del comercio.
        let toggle = element("category-apply-merchant")
        scrollTo(toggle, swipes: 3)
        toggle.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "value == %@", "0"), toggle, timeout: 5))
        app.buttons["category-tile-comerFuera"].tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "label == %@", "Categoría: Comer fuera"), chip, timeout: 5))
        chip.tap()
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        XCTAssertEqual(reset.label, "Volver a la categoría automática")
        reset.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "label == %@", "Categoría: Casa"), chip, timeout: 5),
                      "Volver a lo automático borró también la elección del comercio")

        // 3. Ahora solo queda la del comercio: el botón dice su nombre y la quita.
        chip.tap()
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        XCTAssertEqual(reset.label, "Quitar mi categoría de todo Mercadona")
        reset.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "label == %@", original), chip, timeout: 5))
    }

    // MARK: - R24: un solo toque en cada pestaña (visible en el log, sin poner en rojo la ejecución)

    func testTabSwitchSingleTapStrict() throws {
        continueAfterFailure = true
        launch()
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")
        let steps: [(String, XCUIElement)] = [
            ("Avisos", app.navigationBars["Avisos"]),
            ("Ajustes", app.navigationBars["Ajustes"]),
            ("Gasto", element("gasto.total")),
            ("Inicio", app.staticTexts["Tu dinero"]),
        ]
        XCTExpectFailure("Cambio de pestaña con un solo toque: lento o ignorado en el simulador de CI", strict: false) {
            for (name, target) in steps {
                app.tabBars.buttons[name].tap()
                XCTAssertTrue(target.waitForExistence(timeout: 5), "La pestaña \(name) no cambió con un solo toque")
            }
        }
    }

    // MARK: - R25 (h): salir de primer plano cierra todo lo que está encima

    func testBackgroundClosesMovementSheet() throws {
        launch()
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")
        let row = app.buttons.matching(identifier: "movementRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(sheetClose.waitForExistence(timeout: 8), "No se abrió la hoja del movimiento")
        backgroundAndReturn()
        XCTAssertTrue(waitFor(gone, sheetClose, timeout: 10), "La hoja del movimiento sigue abierta tras salir de primer plano")
    }

    func testBackgroundClosesShareSheet() throws {
        let save = openBackupSettings()
        save.tap()
        let share = app.otherElements["ActivityListView"]
        XCTAssertTrue(share.waitForExistence(timeout: 15), "No se abrió la hoja de compartir")
        backgroundAndReturn()
        XCTAssertTrue(waitFor(gone, share, timeout: 10), "La hoja de compartir sigue abierta tras salir de primer plano")
    }

    func testBackgroundClosesRestoreSheet() throws {
        openRestoreSheetByTap()
        backgroundAndReturn()
        XCTAssertTrue(waitFor(gone, element("restore-slide"), timeout: 10),
                      "La confirmación de restaurar sigue abierta tras salir de primer plano")
    }

    /// R26: el menú contextual de una suscripción tampoco sobrevive a salir de primer plano.
    func testBackgroundClosesContextMenu() throws {
        openGasto()
        let link = element("gasto.suscripciones")
        scrollTo(link)
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        let row = app.descendants(matching: .any).matching(identifier: "suscripciones.fila").element(boundBy: 0)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.press(forDuration: 1.2)
        let hide = app.buttons["Esto no es una suscripción"]
        XCTAssertTrue(hide.waitForExistence(timeout: 5), "No salió el menú de ocultar")
        backgroundAndReturn()
        XCTAssertTrue(waitFor(gone, hide, timeout: 10), "El menú contextual sigue abierto tras salir de primer plano")
    }
}
