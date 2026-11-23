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

    /// Lista cada elemento que coincide (tipo, identificador, etiqueta y marco) para que un recuento inesperado se explique solo.
    private func describe(_ query: XCUIElementQuery) -> String {
        let all = query.allElementsBoundByIndex
        let lines = all.enumerated().map { i, el in
            "[\(i)] tipo \(el.elementType.rawValue) id «\(el.identifier)» etiqueta «\(el.label)» marco \(el.frame)"
        }
        return "\(all.count) elementos: " + lines.joined(separator: " | ")
    }

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

        // El campo alinea el texto a la derecha (AmountField): tocar el borde derecho deja el cursor al final de «abc».
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "100\n")
        XCTAssertFalse(app.staticTexts["Escribe un importe como 120,00"].waitForExistence(timeout: 2))
        // Guardado: al salir y volver, el campo enseña el límite (formateado) y no hay error.
        goBack()
        scrollTo(link)
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        // El resumen de la fila de Gasto sigue al presupuesto guardado: la demo trae el del mes y uno de «Comer fuera», y ahora
        // hay también el de Supermercado (R36 9).
        XCTAssertTrue(waitFor(NSPredicate(format: "label CONTAINS %@", "2 categorías"), link, timeout: 10),
                      "La fila de Presupuestos en Gasto no cuenta el límite guardado: \(link.label)")
        link.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        // «100,00» y no «100»: un borrador sin guardar («100») también contiene «100».
        XCTAssertTrue(waitFor(NSPredicate(format: "value CONTAINS %@", "100,00"), field, timeout: 10), "El límite no se guardó")
        XCTAssertFalse(app.staticTexts["Escribe un importe como 120,00"].exists)
    }

    /// R30 (b) y R38: la demo enseña exactamente Spotify y Netflix como suscripciones CUALQUIER día del año, y además ese día
    /// es el que se pidió. Se fija el «hoy» de la demo (`-MiBancoDemoToday`, solo en DEBUG y con `-MiBancoDemo`) en días de cada
    /// hueco del mes en que antes se encadenaban Renfe (7 a 16) y Glovo (21 a 30), en fin de mes, en un cambio de año y en un
    /// marzo tras un febrero corto. Netflix se cobra tres días después del «hoy» de la demo: su fila lo dice, y si el «hoy» no
    /// se aplicara (se ignorara el argumento) fallarían cinco de las seis fechas. Los dos últimos días de noviembre se repiten
    /// con la llegada de la demo (`-MiBancoDemoArrival`: Carrefour 23,45 € ~4 s tras arrancar), que no debe encadenarse con el
    /// Carrefour del mes pasado (31,50 € el día 27).
    func testDemoSubscriptionsAreSpotifyAndNetflixOnAnyDay() throws {
        let cases: [(day: String, arrival: Bool, netflix: String)] = [
            ("2026-11-07", false, "10 nov"), ("2026-11-16", false, "19 nov"), ("2026-11-21", false, "24 nov"),
            ("2026-11-30", false, "3 dic"), ("2027-01-31", false, "3 feb"), ("2027-03-01", false, "4 mar"),
            ("2026-11-22", true, "25 nov"), ("2026-11-30", true, "3 dic"),
        ]
        for c in cases {
            let day = c.day + (c.arrival ? " con llegada" : "")
            if app != nil { app.terminate() }
            launch(["-MiBancoDemoScreen", "gasto", "-MiBancoDemoSubscriptions", "-MiBancoDemoToday", c.day]
                   + (c.arrival ? ["-MiBancoDemoArrival"] : []))
            XCTAssertTrue(element("suscripciones.total").waitForExistence(timeout: 20), "No se ve Suscripciones el \(day)")
            let rows = app.descendants(matching: .any).matching(identifier: "suscripciones.fila")
            XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), "No hay filas de suscripción el \(day)")
            // La llegada entra a los ~4 s: se espera a que haya pasado antes de contar.
            if c.arrival { Thread.sleep(forTimeInterval: 9) }
            let labels = rows.allElementsBoundByIndex.map { $0.label }
            XCTAssertEqual(labels.count, 2, "El \(day) la demo no trae exactamente 2 suscripciones: \(describe(rows))")
            XCTAssertTrue(labels.contains { $0.hasPrefix("Spotify,") }, "El \(day) falta Spotify: \(labels)")
            let netflix = labels.first { $0.hasPrefix("Netflix,") }
            XCTAssertNotNil(netflix, "El \(day) falta Netflix: \(labels)")
            XCTAssertTrue(netflix?.contains(c.netflix) == true,
                          "El \(day) la fila de Netflix no trae «\(c.netflix)» (¿se aplicó el «hoy» de la demo?): \(netflix ?? "")")
        }
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
        XCTAssertEqual(rows.count, 2, "La demo no trae exactamente 2 suscripciones: \(describe(rows))")

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

    /// R25 (b) y R36 (10): se desliza hasta el final y se espera el texto de éxito de la hoja, no solo a que desaparezca el
    /// control. El resultado de la espera se guarda (no se vuelve a preguntar `exists`: el texto dura 1,6 s) y se afirma sobre el
    /// PRIMER arrastre: un arrastre que no hizo nada ya no pasa en silencio.
    func testRestoreSlideShowsSuccessText() throws {
        openRestoreSheetByTap()
        let slide = element("restore-slide")
        // La hoja termina de subir antes de arrastrar (si no, el arrastre se lo lleva la hoja).
        Thread.sleep(forTimeInterval: 1.5)
        let success = app.staticTexts["Copia restaurada"]
        let frame = slide.frame
        let start = slide.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 28, dy: frame.height / 2))
        let end = slide.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.width - 6, dy: frame.height / 2))
        start.press(forDuration: 0.3, thenDragTo: end, withVelocity: 300, thenHoldForDuration: 0.2)
        let appeared = success.waitForExistence(timeout: 10)
        XCTAssertTrue(appeared, "El primer arrastre no mostró «Copia restaurada»")
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
        // El resumen de la fila de Gasto antes de tocar nada: el presupuesto del mes y uno por categoría.
        let before = link.label
        XCTAssertTrue(before.contains("Del mes"), "La demo no trae el presupuesto del mes en Gasto: \(before)")
        link.tap()
        let field = app.textFields["presupuestos.mes"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "No se ve el presupuesto del mes")
        XCTAssertTrue(element("presupuestos.pie").label.contains("Deja el campo vacío para quitar el límite."),
                      "Falta cómo quitar un presupuesto")
        // La demo trae un presupuesto del mes de 700 €.
        XCTAssertTrue(waitFor(NSPredicate(format: "value CONTAINS %@", "700"), field, timeout: 5), "La demo no trae el límite del mes")

        // Primera pasada: el texto va pegado a la derecha y un toque en el centro deja el cursor al principio (borrar no quita
        // nada): se toca junto al borde derecho, donde el cursor queda al final del texto.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 14) + "\n")
        assertLimitRemoved(field)
        goBack()
        scrollTo(link)
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        XCTAssertTrue(waitFor(NSPredicate(format: "NOT (label CONTAINS %@)", "Del mes"), link, timeout: 10),
                      "La fila de Presupuestos en Gasto sigue contando el límite del mes: \(link.label)")
        XCTAssertNotEqual(link.label, before)
        link.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        assertLimitRemoved(field)

        // Segunda pasada (R32): se borran los números y queda « €». Lo mismo que vaciar el campo: se quita el límite y no sale
        // el error. Se hace en «Comer fuera» (90,00 € en la demo).
        let category = app.textFields["presupuestos.cat.comerFuera"]
        scrollTo(category)
        XCTAssertTrue(category.waitForExistence(timeout: 5), "No se ve el presupuesto de Comer fuera")
        XCTAssertTrue(waitFor(NSPredicate(format: "value CONTAINS %@", "90"), category, timeout: 5),
                      "La demo no trae el límite de Comer fuera")
        category.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        // R40 (c): primero « €», se comprueba que «€» llegó al campo, y SOLO después se pulsa Intro.
        category.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 14) + " €")
        XCTAssertTrue(waitFor(NSPredicate(format: "value CONTAINS %@", "€"), category, timeout: 5),
                      "El símbolo «€» no llegó al campo antes de pulsar Intro: «\(String(describing: category.value))»")
        category.typeText("\n")
        assertLimitRemoved(category)
        goBack()
        scrollTo(link)
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        XCTAssertTrue(waitFor(NSPredicate(format: "label CONTAINS %@", "Sin presupuestos"), link, timeout: 10),
                      "La fila de Presupuestos en Gasto sigue contando el límite de Comer fuera: \(link.label)")
    }

    /// El campo quedó vacío (o con su texto de relleno «Sin límite») y no hay error de importe.
    private func assertLimitRemoved(_ field: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let empty = NSPredicate(format: "value == %@ OR value == %@", "", "Sin límite")
        XCTAssertTrue(waitFor(empty, field, timeout: 10), "El campo no quedó vacío: «\(String(describing: field.value))»",
                      file: file, line: line)
        XCTAssertFalse(app.staticTexts["Escribe un importe como 120,00"].exists, "Salió el error de importe",
                       file: file, line: line)
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
        XCTAssertTrue(waitFor(NSPredicate(format: "label == %@", "Categoría: Casa y facturas"), chip, timeout: 5),
                      "La categoría para todo el comercio no se aplicó (la ficha «Casa y facturas»)")
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
        XCTAssertTrue(waitFor(NSPredicate(format: "label == %@", "Categoría: Casa y facturas"), chip, timeout: 5),
                      "Volver a lo automático borró también la elección del comercio")

        // 3. Ahora solo queda la del comercio: el botón dice su nombre y la quita.
        chip.tap()
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        XCTAssertEqual(reset.label, "Quitar mi categoría de todo Mercadona")
        reset.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "label == %@", original), chip, timeout: 5))
    }

    // MARK: - R24 y R31: un solo toque en cada pestaña (con los tiempos a la vista, sin poner en rojo la ejecución)

    /// R39. Mide, para cada pestaña, lo que tarda UN toque en dejarla seleccionada (`isSelected` de su botón en la barra) y en
    /// dejar su contenido a la vista. El reloj arranca cuando `tap()` ya volvió. Un paso cuya pestaña ya estaba seleccionada
    /// antes del toque se da por «sin medir» y nunca como un tiempo. Se hacen DOS vueltas: la 1 es la primera visita de cada
    /// pestaña; la 2, cuando las cuatro ya se han visitado. Las cifras van en el nombre de una actividad y en el mensaje del
    /// fallo esperado; el paso «Resumen por prueba» de `ui-tests.yml` las imprime en cada ejecución. Vuelta 2 en verde y la 1
    /// no: el coste es construir la pestaña la primera vez; vuelta 2 en rojo: es el toque sintético del simulador.
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
        var laps: [String] = []
        var allChanged = true
        var visited: Set<String> = ["Inicio"]
        for lap in 1...2 {
            // R39: la segunda vuelta empieza SOLO cuando las cuatro pestañas ya se han visitado de verdad y se está en Inicio.
            if lap == 2 {
                for (name, target) in steps where !visited.contains(name) {
                    _ = selectTab(app.tabBars.buttons[name], until: target)
                }
                let home = app.tabBars.buttons["Inicio"]
                if !home.isSelected { _ = selectTab(home, until: app.staticTexts["Tu dinero"]) }
            }
            var figures: [String] = []
            for (name, target) in steps {
                let tab = app.tabBars.buttons[name]
                if tab.isSelected {
                    figures.append("\(name) sin medir (ya estaba seleccionada)")
                    continue
                }
                tab.tap()
                let start = Date()
                let selected = waitFor(NSPredicate(format: "isSelected == true"), tab, timeout: 5)
                let selectedAt = Date().timeIntervalSince(start)
                let shown = target.waitForExistence(timeout: 5)
                let shownAt = Date().timeIntervalSince(start)
                let tabText = selected ? String(format: "pestaña %.1f s", selectedAt) : "pestaña no seleccionada en 5 s"
                let contentText = shown ? String(format: "contenido %.1f s", shownAt) : "contenido no visto en 5 s"
                figures.append("\(name) \(tabText), \(contentText)")
                if selected && shown { visited.insert(name) } else { allChanged = false }
            }
            laps.append("vuelta \(lap): " + figures.joined(separator: "; "))
        }
        let summary = "Cambio de pestaña con un solo toque, " + laps.joined(separator: "; ")
        XCTContext.runActivity(named: summary) { _ in }
        XCTExpectFailure(summary, strict: false) {
            XCTAssertTrue(allChanged, summary)
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
        let merchant = row.label.split(separator: ",").first.map(String.init) ?? ""
        row.press(forDuration: 1.2)
        // R43 (c) / Menor 3: comprobar también la vista previa con el ojo abierto de una fila de suscripción.
        let preview = app.descendants(matching: .any).matching(identifier: "menu.vistaPrevia").firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5), "Falta la vista previa del menú de suscripción (menu.vistaPrevia)")
        XCTAssertFalse(merchant.isEmpty)
        XCTAssertTrue(preview.label.contains(merchant), "La vista previa de suscripción no trae «\(merchant)»: «\(preview.label)»")
        let hide = app.buttons["Esto no es una suscripción"]
        XCTAssertTrue(hide.waitForExistence(timeout: 5), "No salió el menú de ocultar")
        backgroundAndReturn()
        XCTAssertTrue(waitFor(gone, hide, timeout: 10), "El menú contextual sigue abierto tras salir de primer plano")
    }

    // MARK: - R33: el ojo no reconstruye las filas y la vista previa privada no lleva importes

    /// En Inicio, tocar el ojo (cerrarlo y abrirlo) no hace aparecer copias de las filas: durante 1 s tras cada toque el número
    /// de filas de movimiento no supera el de antes. (XCUITest espera a que la app esté quieta tras el toque, así que esto
    /// vigila lo que quede de la transición de 0,35 s; el parpadeo en sí solo se ve en el iPhone.)
    func testEyeToggleDoesNotDuplicateRows() throws {
        launch()
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")
        let rows = app.buttons.matching(identifier: "movementRow")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 8), "No hay filas de movimiento")
        let before = rows.count
        XCTAssertGreaterThan(before, 0)
        for name in ["Ocultar importes", "Mostrar importes"] {
            let eye = app.buttons[name]
            XCTAssertTrue(eye.waitForExistence(timeout: 5), "No está el ojo «\(name)»")
            eye.tap()
            var peak = 0
            let end = Date().addingTimeInterval(1)
            repeat { peak = max(peak, rows.count) } while Date() < end
            XCTAssertLessThanOrEqual(peak, before, "Tras «\(name)» hubo \(peak) filas de movimiento y antes \(before)")
        }
    }

    /// R37(a): con el ojo abierto, mantener pulsada la primera fila de Inicio («Mercadona») levanta una vista previa que existe,
    /// mide al menos 44 pt de alto y trae el nombre del comercio (si dibujara en blanco, no tendría ni alto ni nombre).
    func testOpenEyePreviewDrawsTheRow() throws {
        launch()
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")
        let row = app.buttons.matching(identifier: "movementRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "No hay filas de movimiento")
        XCTAssertTrue(row.label.contains("Mercadona"), "La primera fila no es Mercadona: \(row.label)")
        row.press(forDuration: 1.2)
        let preview = app.descendants(matching: .any).matching(identifier: "menu.vistaPrevia").firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5), "No existe la vista previa del menú (menu.vistaPrevia)")
        XCTAssertGreaterThanOrEqual(preview.frame.height, 44, "La vista previa mide \(preview.frame.height) pt de alto")
        XCTAssertTrue(preview.label.contains("Mercadona"), "La vista previa no trae el nombre: «\(preview.label)»")
    }

    /// R37(b) y R43(c): con el ojo cerrado la vista previa es solo el nombre: existe la privada («Mercadona»), no existe la
    /// normal, y al abrir el menú no aparece ningún elemento nuevo en TODA la app con forma de importe ni en `label` ni en `value`.
    func testPrivatePreviewHasNoAmount() throws {
        launch(["-MiBancoDemoPrivate"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")
        let row = app.buttons.matching(identifier: "movementRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "No hay filas de movimiento")
        func moneyShaped(_ text: String) -> Bool {
            text.contains("€") || text.contains("euros") || text.range(of: #"\d,\d{2}"#, options: .regularExpression) != nil
        }
        func moneyStrings() -> [String] {
            app.descendants(matching: .any).allElementsBoundByIndex.flatMap { el -> [String] in
                var found: [String] = []
                if moneyShaped(el.label) { found.append("label:\(el.label)") }
                if let val = el.value as? String, moneyShaped(val) { found.append("value:\(val)") }
                return found
            }
        }
        let before = NSCountedSet(array: moneyStrings())
        row.press(forDuration: 1.2)
        let preview = app.descendants(matching: .any).matching(identifier: "menu.vistaPreviaPrivada").firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5), "No existe la vista previa privada (menu.vistaPreviaPrivada)")
        XCTAssertEqual(preview.label, "Mercadona", "La vista previa privada no es solo el nombre: «\(preview.label)»")
        if let val = preview.value as? String {
            XCTAssertFalse(moneyShaped(val), "La vista previa privada trae importe en value: «\(val)»")
        }
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "menu.vistaPrevia").firstMatch.exists,
                       "Con el ojo cerrado salió la vista previa normal")
        let after = NSCountedSet(array: moneyStrings())
        var leaked: [String] = []
        for item in after {
            if after.count(for: item) > before.count(for: item), let text = item as? String {
                leaked.append(text)
            }
        }
        XCTAssertTrue(leaked.isEmpty, "Al abrir el menú en modo privado aparecieron importes en la app: \(leaked)")
    }
}
