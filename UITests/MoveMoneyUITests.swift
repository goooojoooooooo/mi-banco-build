import UIKit
import XCTest

/// Toques reales sobre «Mover dinero», acciones rápidas, «Cuentas y contactos» y «Próximos cobros» (Plan 4b, tareas 8 y 16).
/// Siempre en modo demo (`-MiBancoDemo…`): datos ficticios e IBANs de ejemplo publicados, sin red ni Llavero real.
final class MoveMoneyUITests: XCTestCase {
    var app: XCUIApplication!
    private let nbsp = "\u{00A0}"

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

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func waitFor(_ predicate: NSPredicate, _ object: Any, timeout: TimeInterval) -> Bool {
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: object)
        return XCTWaiter().wait(for: [exp], timeout: timeout) == .completed
    }

    private func scrollTo(_ el: XCUIElement, swipes: Int = 6) {
        if el.waitForExistence(timeout: 2), el.isHittable { return }
        for _ in 0..<swipes {
            if el.exists && el.isHittable { return }
            app.swipeUp()
        }
        for _ in 0..<swipes {
            if el.exists && el.isHittable { return }
            app.swipeDown()
        }
    }

    /// Arrastre desde el centro del pulgar (48 pt) hasta el extremo derecho, con reintento (mismo patrón que `Plan3TapTests`).
    private func dragSlide(_ slider: XCUIElement, until target: XCUIElement) -> Bool {
        for _ in 0..<2 {
            let frame = slider.frame
            guard frame.width > 60 else { continue }
            let origin = slider.coordinate(withNormalizedOffset: .zero)
            let from = origin.withOffset(CGVector(dx: 28, dy: frame.height / 2))
            let to = origin.withOffset(CGVector(dx: frame.width - 6, dy: frame.height / 2))
            from.press(forDuration: 0.3, thenDragTo: to, withVelocity: 300, thenHoldForDuration: 0.2)
            if target.waitForExistence(timeout: 8) { return true }
        }
        return target.waitForExistence(timeout: 4)
    }

    func testMoveToRevolut() throws {
        launch(["-MiBancoDemoCard", "ima"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")

        let moveButton = app.buttons["Mover dinero"]
        XCTAssertTrue(moveButton.waitForExistence(timeout: 10), "Falta la acción rápida Mover dinero")
        moveButton.tap()

        XCTAssertTrue(app.navigationBars["Mover dinero"].waitForExistence(timeout: 8), "No se abrió la hoja Mover dinero")

        let revolutTarget = element("move-target-rev")
        scrollTo(revolutTarget)
        XCTAssertTrue(revolutTarget.waitForExistence(timeout: 8), "No aparece Revolut como destino")
        revolutTarget.tap()

        let key2 = app.buttons["2"]
        let key0 = app.buttons["0"]
        XCTAssertTrue(key2.waitForExistence(timeout: 8), "No apareció el teclado de importe")
        key2.tap()
        key0.tap()
        key0.tap()

        let expectedAmount = "200\(nbsp)€"
        let amountText = app.staticTexts[expectedAmount]
        XCTAssertTrue(amountText.waitForExistence(timeout: 5), "U26: el importe debe mostrar lo tecleado (\(expectedAmount))")

        let slider = element("move-slide")
        scrollTo(slider)
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "Falta Desliza para preparar")

        let copied = app.staticTexts["IBAN de Revolut copiado"]
        XCTAssertTrue(dragSlide(slider, until: copied), "No apareció IBAN de Revolut copiado")

        // U24: en el simulador `canOpenURL` es falso, así que se exige la instrucción alternativa (no «uno u otro»).
        let fallbackHint = app.staticTexts["Abre imagin y pega el IBAN."]
        XCTAssertTrue(fallbackHint.waitForExistence(timeout: 5), "U24: falta la instrucción alternativa Abre imagin y pega el IBAN.")

        let close = app.buttons["Cerrar"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "Falta el botón Cerrar")
        close.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "exists == false"), copied, timeout: 8), "La hoja Mover dinero no se cerró")
    }

    func testCopyIban() throws {
        launch(["-MiBancoDemoCard", "ima"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")

        let copyButton = app.buttons["Copiar IBAN"]
        XCTAssertTrue(copyButton.waitForExistence(timeout: 10), "Falta la acción rápida Copiar IBAN")
        copyButton.tap()

        let toast = app.staticTexts["IBAN copiado · se borra en 3 min"]
        XCTAssertTrue(toast.waitForExistence(timeout: 5), "No apareció el aviso de IBAN copiado")
        // U24: si el simulador permite leer el portapapeles entre procesos, exigir el IBAN normalizado sin espacios.
        if let pasted = UIPasteboard.general.string {
            XCTAssertEqual(pasted, "ES9121000418450200051332", "U24: el portapapeles no recibió el IBAN sin espacios")
        }
    }

    func testAccountsScreen() throws {
        launch(["-MiBancoDemoScreen", "ajustes"])
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 15), "No se ve Ajustes")

        let row = element("settings-accounts")
        scrollTo(row)
        XCTAssertTrue(row.waitForExistence(timeout: 8), "Falta Cuentas y contactos en Ajustes")
        row.tap()

        XCTAssertTrue(app.navigationBars["Cuentas y contactos"].waitForExistence(timeout: 8), "No se abrió Cuentas y contactos")

        let maskedIma = app.staticTexts["ES91 •••• 1332"]
        scrollTo(maskedIma)
        XCTAssertTrue(maskedIma.waitForExistence(timeout: 8), "No aparece el IBAN enmascarado ES91 •••• 1332")

        // U29: teléfono enmascarado en la fila de Ana (demo): nunca «612 345 678», sí acabado en «678».
        let anaName = app.staticTexts["Ana (demo)"]
        scrollTo(anaName)
        XCTAssertTrue(anaName.waitForExistence(timeout: 8), "Falta el contacto Ana (demo)")
        let fullPhone = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '612 345 678'"))
        XCTAssertEqual(fullPhone.count, 0, "U29: el teléfono completo no debe verse en la lista")
        let maskedPhoneEl = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '678'")).firstMatch
        XCTAssertTrue(maskedPhoneEl.waitForExistence(timeout: 5), "U29: deben verse las últimas 3 cifras del teléfono (678)")

        let addContact = element("accounts-add-payee")
        scrollTo(addContact)
        XCTAssertTrue(addContact.waitForExistence(timeout: 8), "Falta el botón Añadir contacto")
        addContact.tap()

        let nameField = app.textFields["payeeNameField"]
        scrollTo(nameField)
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Falta el campo de nombre")
        nameField.tap()
        nameField.typeText("Prueba\n")

        let ibanField = app.textFields["payeeIBANField"]
        scrollTo(ibanField)
        XCTAssertTrue(ibanField.waitForExistence(timeout: 5), "Falta el campo de IBAN del contacto")
        ibanField.tap()
        ibanField.typeText("ES91 2100\n")

        let saveButton = app.buttons["Guardar contacto"]
        scrollTo(saveButton)
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Falta Guardar contacto")
        saveButton.tap()

        let errorText = app.staticTexts["Ese IBAN no es correcto: revisa los números."]
        XCTAssertTrue(errorText.waitForExistence(timeout: 5), "No apareció el aviso de IBAN incorrecto")

        // U24: corregir a un IBAN válido y comprobar que se guarda.
        scrollTo(ibanField)
        ibanField.tap()
        ibanField.typeText(String(repeating: "\u{8}", count: 15) + "ES9121000418450200051332\n")
        scrollTo(saveButton)
        saveButton.tap()
        let savedContact = app.staticTexts["Prueba"]
        scrollTo(savedContact)
        XCTAssertTrue(savedContact.waitForExistence(timeout: 8), "U24: el contacto válido no se guardó")
    }

    func testMoveSheetDismissesOnBackground() throws {
        launch(["-MiBancoDemoCard", "ima"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")

        let moveButton = app.buttons["Mover dinero"]
        XCTAssertTrue(moveButton.waitForExistence(timeout: 10), "Falta Mover dinero")
        moveButton.tap()
        XCTAssertTrue(app.navigationBars["Mover dinero"].waitForExistence(timeout: 8), "No se abrió la hoja Mover dinero")

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1.0)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "La app no volvió a primer plano")

        let nav = app.navigationBars["Mover dinero"]
        XCTAssertTrue(waitFor(NSPredicate(format: "exists == false"), nav, timeout: 8), "La hoja Mover dinero no se cerró al pasar a segundo plano")
    }

    func testUpcomingCalendarOpensFromSpending() throws {
        launch(["-MiBancoDemoScreen", "gasto"])
        let link = element("gasto.proximos")
        scrollTo(link)
        XCTAssertTrue(link.waitForExistence(timeout: 15), "Falta Próximos cobros en Gasto")
        link.tap()

        XCTAssertTrue(app.navigationBars["Próximos cobros"].waitForExistence(timeout: 8), "No se abrió Próximos cobros")
        let netflix = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Netflix'")).firstMatch
        scrollTo(netflix)
        XCTAssertTrue(netflix.waitForExistence(timeout: 8), "Netflix no aparece en los próximos 14 días")
    }

    func testMoveMoneyAndCalendarPrivateModeHidesAmounts() throws {
        launch(["-MiBancoDemoCard", "ima", "-MiBancoDemoPrivate"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")

        let moveButton = app.buttons["Mover dinero"]
        XCTAssertTrue(moveButton.waitForExistence(timeout: 10), "Falta Mover dinero")
        moveButton.tap()
        XCTAssertTrue(app.navigationBars["Mover dinero"].waitForExistence(timeout: 8), "No se abrió Mover dinero")

        let revolutTarget = element("move-target-rev")
        scrollTo(revolutTarget)
        XCTAssertTrue(revolutTarget.waitForExistence(timeout: 8), "No aparece Revolut")
        revolutTarget.tap()

        XCTAssertTrue(app.buttons["2"].waitForExistence(timeout: 8), "No apareció el teclado")
        app.buttons["2"].tap()
        app.buttons["0"].tap()
        app.buttons["0"].tap()

        let moveSheet = app.scrollViews["move-money-scroll"]
        XCTAssertTrue(moveSheet.waitForExistence(timeout: 5), "Falta el contenedor de Mover dinero")
        let euroElements = moveSheet.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '€'"))
        XCTAssertEqual(euroElements.count, 0, "Mover dinero expuso € a VoiceOver en modo privado")

        // U24: llegar al paso 3 y comprobar que la pista tampoco expone «€».
        let slider = element("move-slide")
        scrollTo(slider)
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "Falta Desliza para preparar en privado")
        let copied = app.staticTexts["IBAN de Revolut copiado"]
        XCTAssertTrue(dragSlide(slider, until: copied), "No llegó al paso 3 en modo privado")
        // U79 (A-M3): dentro de la hoja del paso 3, no en el primer `ScrollView` que salga (podría ser el de Inicio).
        let step3Sheet = app.scrollViews["move-money-scroll"]
        XCTAssertTrue(step3Sheet.waitForExistence(timeout: 5), "Falta el contenedor del paso 3")
        XCTAssertTrue(step3Sheet.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'En imagin:' OR label BEGINSWITH 'En Revolut:'"))
            .firstMatch.waitForExistence(timeout: 5), "U24: la pista del paso 3 no está dentro de la hoja")
        let step3Euro = step3Sheet.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '€'"))
        XCTAssertEqual(step3Euro.count, 0, "U24: la pista del paso 3 expuso € en modo privado")

        app.buttons["Cerrar"].tap()

        launch(["-MiBancoDemoScreen", "gasto", "-MiBancoDemoUpcoming", "-MiBancoDemoPrivate"])
        XCTAssertTrue(app.navigationBars["Próximos cobros"].waitForExistence(timeout: 15), "No se abrió Próximos cobros en privado")
        let calScroll = app.scrollViews["upcoming-calendar-scroll"]
        XCTAssertTrue(calScroll.waitForExistence(timeout: 5), "Falta el contenedor de Próximos cobros")
        let calEuro = calScroll.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '€'"))
        XCTAssertEqual(calEuro.count, 0, "Próximos cobros expuso € a VoiceOver en modo privado")
    }

    /// U23: «Compartir IBAN» abre la hoja del sistema sin «Copiar»/«Copy» y se cierra al salir a segundo plano.
    func testShareIbanHasNoCopyAndClosesOnBackground() throws {
        launch(["-MiBancoDemoCard", "ima"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")

        let shareButton = app.buttons["Compartir IBAN"]
        XCTAssertTrue(shareButton.waitForExistence(timeout: 10), "U23: falta Compartir IBAN")
        shareButton.tap()

        let activityList = app.otherElements["ActivityListView"]
        let closeShare = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cerrar", "Close"])).firstMatch
        // U79 (A-M5): el cierre se comprueba sobre EL MISMO elemento con el que se vio abierta la hoja.
        let shareSheet: XCUIElement
        if activityList.waitForExistence(timeout: 10) {
            shareSheet = activityList
        } else {
            XCTAssertTrue(closeShare.waitForExistence(timeout: 5), "U23: no se abrió la hoja de compartir del sistema")
            shareSheet = closeShare
        }

        let copyButtons = app.buttons.matching(NSPredicate(format: "label == 'Copiar' OR label == 'Copy'"))
        let copyCells = app.cells.matching(NSPredicate(format: "label == 'Copiar' OR label == 'Copy'"))
        XCTAssertEqual(copyButtons.count + copyCells.count, 0, "U23: la hoja de compartir no debe ofrecer Copiar")

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1.0)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "La app no volvió a primer plano")
        XCTAssertTrue(
            waitFor(NSPredicate(format: "exists == false"), shareSheet, timeout: 8),
            "U23: la hoja de compartir no se cerró al pasar a segundo plano"
        )
    }

    /// U24 #1 + U21: en Próximos cobros hay exactamente UN botón «Pasar … a Revolut» y abrirlo llega a «Para Revolut».
    func testCalendarTopUpOpensMoveMoney() throws {
        launch(["-MiBancoDemoScreen", "gasto", "-MiBancoDemoUpcoming", "-MiBancoDemoFloor"])
        XCTAssertTrue(app.navigationBars["Próximos cobros"].waitForExistence(timeout: 15), "No se abrió Próximos cobros")

        let topUps = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Pasar ' AND label CONTAINS 'a Revolut'"))
        XCTAssertTrue(topUps.firstMatch.waitForExistence(timeout: 10), "U21/U24: falta el botón Pasar X a Revolut")
        XCTAssertEqual(topUps.count, 1, "U21: debe existir exactamente un botón Pasar X por banco, encontrados: \(topUps.count)")
        topUps.firstMatch.tap()

        XCTAssertTrue(app.scrollViews["move-money-scroll"].waitForExistence(timeout: 8), "U24: no se abrió Mover dinero")
        XCTAssertTrue(app.staticTexts["Para Revolut"].waitForExistence(timeout: 5), "U24: falta «Para Revolut»")
    }

    /// U24 #2 + U25: aviso «Esperando:» se quita con «Quitar»; en estado `.done` dice «He visto salir» y no hay «Quitar».
    func testPendingBannerRemove() throws {
        launch(["-MiBancoDemoPending"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")

        let waitingText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Esperando:'")).firstMatch
        XCTAssertTrue(waitingText.waitForExistence(timeout: 8), "U24: no aparece el aviso Esperando:")

        let removeBtn = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Quitar'")).firstMatch
        XCTAssertTrue(removeBtn.waitForExistence(timeout: 5), "U24: falta el botón Quitar")
        removeBtn.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "exists == false"), waitingText, timeout: 8), "U24: Quitar no borró el aviso")

        launch(["-MiBancoDemoPending", "done"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece en estado done")
        let doneText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'He visto salir'")).firstMatch
        XCTAssertTrue(doneText.waitForExistence(timeout: 8), "U25: falta el texto «He visto salir» en estado done")
        let doneRemove = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Quitar'"))
        XCTAssertEqual(doneRemove.count, 0, "U24/U25: en estado done no debe haber botón Quitar")
    }

    /// U24 #3: «Añadir dinero» abre Mover dinero hacia Revolut; sin IBAN, «Añadir IBAN» abre Cuentas y contactos.
    func testQuickActionsAddMoneyAndAddIban() throws {
        launch(["-MiBancoDemoCard", "rev"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")

        let addMoney = app.buttons["Añadir dinero"]
        XCTAssertTrue(addMoney.waitForExistence(timeout: 10), "U24: falta Añadir dinero en Revolut")
        addMoney.tap()
        XCTAssertTrue(app.scrollViews["move-money-scroll"].waitForExistence(timeout: 8), "U24: no abrió Mover dinero")
        XCTAssertTrue(app.staticTexts["Para Revolut"].waitForExistence(timeout: 5), "U24: falta Para Revolut")

        launch(["-MiBancoDemoCard", "rev", "-MiBancoDemoNoIban", "rev"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")
        let addIban = app.buttons["Añadir IBAN"]
        XCTAssertTrue(addIban.waitForExistence(timeout: 10), "U24: falta Añadir IBAN sin IBAN guardado")
        addIban.tap()
        XCTAssertTrue(app.navigationBars["Cuentas y contactos"].waitForExistence(timeout: 10), "U24: Añadir IBAN no abrió Cuentas y contactos")
    }

    /// U24 #4 + U27: «Ver» en Cuentas responde a pulsación mantenida y vuelve al enmascarado al soltar.
    func testAccountsHoldToRevealIban() throws {
        // U74 (A-I2): `-MiBancoDemoRevealLinger 4` (solo DEBUG) deja el IBAN revelado 4 s tras SOLTAR, porque `press` bloquea
        // la prueba mientras dura. No revela nada por sí solo: si «Ver» no revelara, el IBAN completo no saldría nunca.
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoAccounts", "-MiBancoDemoRevealLinger", "4"])
        XCTAssertTrue(app.navigationBars["Cuentas y contactos"].waitForExistence(timeout: 15), "No se abrió Cuentas y contactos")

        let masked = app.staticTexts["ES91 •••• 1332"]
        scrollTo(masked)
        XCTAssertTrue(masked.waitForExistence(timeout: 8), "Falta el IBAN enmascarado de imagin")

        let reveal = app.buttons["accounts-reveal-iban-ima"]
        scrollTo(reveal)
        XCTAssertTrue(reveal.waitForExistence(timeout: 5), "Falta el botón Ver de imagin")
        XCTAssertGreaterThanOrEqual(reveal.frame.width, 44, "U27: Ver debe medir ≥ 44 pt de ancho")
        XCTAssertGreaterThanOrEqual(reveal.frame.height, 44, "U27: Ver debe medir ≥ 44 pt de alto")

        let full = app.staticTexts["ES91 2100 0418 4502 0005 1332"]
        XCTAssertFalse(full.exists, "U27: el IBAN completo no puede verse antes de pulsar «Ver»")
        reveal.press(forDuration: 1.0)
        XCTAssertTrue(full.waitForExistence(timeout: 2), "U24/U27: al mantener «Ver» debe verse el IBAN completo")
        XCTAssertFalse(masked.exists, "U24/U27: con el IBAN revelado no debe quedar el enmascarado")
        XCTAssertTrue(masked.waitForExistence(timeout: 8), "U24/U27: al soltar Ver debe volver el IBAN enmascarado")
        XCTAssertFalse(full.exists, "U27: el IBAN completo no debe quedarse visible tras soltar")
    }

    /// U24 #5 + U27: «Editar» (≥ 44 pt) abre campo vacío, guardar actualiza el enmascarado y cancelar conserva el guardado.
    func testAccountsEditIbanSaveAndCancel() throws {
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoAccounts"])
        XCTAssertTrue(app.navigationBars["Cuentas y contactos"].waitForExistence(timeout: 15), "No se abrió Cuentas y contactos")

        let editIma = app.buttons["accounts-edit-iban-ima"]
        scrollTo(editIma)
        XCTAssertTrue(editIma.waitForExistence(timeout: 8), "Falta Editar de imagin")
        XCTAssertGreaterThanOrEqual(editIma.frame.width, 44, "U27: Editar debe medir ≥ 44 pt de ancho")
        editIma.tap()

        let field = app.textFields["accounts-iban-field-ima"]
        scrollTo(field)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Falta el campo de edición de IBAN")
        let initialVal = (field.value as? String) ?? ""
        XCTAssertFalse(initialVal.contains("0418"), "U27: Editar no debe pre-rellenar el IBAN completo")
        let save = app.buttons["Guardar"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled, "U27: Guardar debe estar desactivado con el campo vacío")

        field.tap()
        field.typeText("DE89370400440532013000")
        XCTAssertTrue(save.isEnabled, "Guardar debe activarse con un IBAN escrito")
        save.tap()

        let updated = app.staticTexts["DE89 •••• 3000"]
        scrollTo(updated)
        XCTAssertTrue(updated.waitForExistence(timeout: 8), "U24: no se actualizó el IBAN enmascarado tras guardar")

        scrollTo(editIma)
        editIma.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("GB82WEST12345698765432")
        app.buttons["Cancelar"].tap()
        XCTAssertTrue(updated.waitForExistence(timeout: 5), "U24: Cancelar no debe cambiar el IBAN guardado")
    }

    /// U24 #6: escribir «50» en «Colchón mínimo» de Revolut se conserva al salir y volver.
    func testAccountsFloorSaves() throws {
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoAccounts"])
        XCTAssertTrue(app.navigationBars["Cuentas y contactos"].waitForExistence(timeout: 15), "No se abrió Cuentas y contactos")

        let floor = app.textFields["accounts-floor-field-rev"]
        scrollTo(floor)
        XCTAssertTrue(floor.waitForExistence(timeout: 8), "Falta el campo Colchón mínimo de Revolut")
        floor.tap()
        floor.typeText("50\n")

        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 8), "No volvió a Ajustes")

        let row = element("settings-accounts")
        scrollTo(row)
        row.tap()
        XCTAssertTrue(app.navigationBars["Cuentas y contactos"].waitForExistence(timeout: 8), "No reabrió Cuentas")
        scrollTo(floor)
        XCTAssertTrue(floor.waitForExistence(timeout: 5))
        let val = (floor.value as? String) ?? ""
        XCTAssertTrue(val.contains("50"), "U24: el colchón de 50 no se conservó al volver: \(val)")
    }

    /// U24 #7 + U29: alta de «Luis (demo)» (teléfono enmascarado) y borrado deslizando.
    func testAccountsAddAndDeletePayee() throws {
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoAccounts"])
        XCTAssertTrue(app.navigationBars["Cuentas y contactos"].waitForExistence(timeout: 15), "No se abrió Cuentas y contactos")

        let add = element("accounts-add-payee")
        scrollTo(add)
        add.tap()

        let name = app.textFields["payeeNameField"]
        scrollTo(name)
        name.tap()
        name.typeText("Luis (demo)\n")
        let phone = app.textFields["payeePhoneField"]
        scrollTo(phone)
        phone.tap()
        phone.typeText("+34 600 000 000")
        let save = app.buttons["Guardar contacto"]
        scrollTo(save)
        save.tap()

        let luis = app.staticTexts["Luis (demo)"]
        scrollTo(luis)
        XCTAssertTrue(luis.waitForExistence(timeout: 8), "U24: no apareció Luis (demo) tras guardar")
        XCTAssertEqual(
            app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '600 000 000'")).count,
            0,
            "U29: el teléfono de Luis (demo) debe estar enmascarado"
        )

        luis.swipeLeft()
        let deleteBtn = app.buttons.matching(NSPredicate(format: "label IN %@", ["Eliminar", "Delete", "Borrar"])).firstMatch
        XCTAssertTrue(deleteBtn.waitForExistence(timeout: 5), "U24: no apareció el botón de borrar contacto")
        deleteBtn.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "exists == false"), luis, timeout: 8), "U24: Luis (demo) no desapareció al borrarlo")
    }

    /// U24 #8 + U32: texto contextual de contacto, «Atrás», cambio de ficha «Desde» y pista con el banco elegido.
    func testMoveSheetSourceChipAndBack() throws {
        launch(["-MiBancoDemoCard", "ima"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")
        app.buttons["Mover dinero"].tap()

        let ana = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Ana (demo)'")).firstMatch
        scrollTo(ana)
        XCTAssertTrue(ana.waitForExistence(timeout: 8), "Falta Ana (demo)")
        ana.tap()

        // U32: importe 0 hacia contacto dice «…para preparar el pago.»
        XCTAssertTrue(
            app.staticTexts["Escribe un importe para preparar el pago."].waitForExistence(timeout: 5),
            "U32: falta el texto contextual para preparar el pago"
        )

        let back = app.buttons["Atrás"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "U24: falta el botón Atrás")
        back.tap()
        XCTAssertTrue(app.staticTexts["¿A dónde?"].waitForExistence(timeout: 5), "U24: Atrás no volvió a ¿A dónde?")

        scrollTo(ana)
        ana.tap()
        XCTAssertTrue(app.buttons["2"].waitForExistence(timeout: 5))
        app.buttons["2"].tap()
        app.buttons["0"].tap()
        app.buttons["0"].tap()

        let revChip = app.buttons["move-from-rev"]
        XCTAssertTrue(revChip.waitForExistence(timeout: 5), "Falta ficha Desde Revolut")
        revChip.tap()
        XCTAssertTrue(revChip.isSelected, "U24: la ficha Revolut debe quedar seleccionada")

        let slider = element("move-slide")
        scrollTo(slider)
        let phoneCopied = app.staticTexts["Teléfono copiado"]
        XCTAssertTrue(dragSlide(slider, until: phoneCopied), "No llegó al paso 3")
        // U79 (A-M3): la pista se busca DENTRO de la hoja (Inicio, debajo, también dice «Revolut») y con la frase exacta de
        // `bankTransferHint(from: .rev, kind: .phone, …)`.
        let readySheet = app.scrollViews["move-money-scroll"]
        XCTAssertTrue(readySheet.waitForExistence(timeout: 5), "Falta el contenedor del paso 3")
        let revHint = readySheet.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "En Revolut: Pagos → Enviar → pega el número y pon ")
        ).firstMatch
        XCTAssertTrue(revHint.waitForExistence(timeout: 5), "U24: la pista del paso 3 debe ser la de Revolut")
        XCTAssertFalse(readySheet.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'En imagin:'")).firstMatch.exists,
                       "U24: la pista del paso 3 no puede ser la de imagin")
    }

    /// U24 #9: destino sin IBAN («Guardar y seguir») y «Añadir contacto» en línea.
    func testMoveSheetSaveAndContinueAndInlinePayee() throws {
        launch(["-MiBancoDemoCard", "ima", "-MiBancoDemoNoIban", "tr"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")
        app.buttons["Mover dinero"].tap()

        let trTarget = element("move-target-tr")
        scrollTo(trTarget)
        XCTAssertTrue(trTarget.waitForExistence(timeout: 8))
        trTarget.tap()

        let inlineField = app.textFields["move-inline-iban-field"]
        scrollTo(inlineField)
        XCTAssertTrue(inlineField.waitForExistence(timeout: 5), "U24: falta el campo de IBAN en línea")
        inlineField.tap()
        inlineField.typeText("DE89370400440532013000")
        let saveContinue = app.buttons["Guardar y seguir"]
        scrollTo(saveContinue)
        saveContinue.tap()
        XCTAssertTrue(app.staticTexts["Para Trade Republic"].waitForExistence(timeout: 8), "U24: Guardar y seguir no pasó al importe")

        app.buttons["Atrás"].tap()
        let addPayee = app.buttons["Añadir contacto"]
        scrollTo(addPayee)
        addPayee.tap()
        let nameField = app.textFields["move-inline-payee-name"]
        scrollTo(nameField)
        nameField.tap()
        nameField.typeText("Marta (demo)\n")
        let phoneField = app.textFields["move-inline-payee-phone"]
        scrollTo(phoneField)
        phoneField.tap()
        phoneField.typeText("+34 611 222 333")
        let savePayee = app.buttons["Guardar contacto"]
        scrollTo(savePayee)
        savePayee.tap()
        XCTAssertTrue(app.staticTexts["Para Marta (demo)"].waitForExistence(timeout: 8), "U24: el contacto en línea no quedó como destino")
    }

    /// U24 #10: destino por teléfono llega a «Teléfono copiado».
    func testMoveSheetPhonePath() throws {
        launch(["-MiBancoDemoCard", "ima"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15))
        app.buttons["Mover dinero"].tap()

        let ana = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Ana (demo)'")).firstMatch
        scrollTo(ana)
        ana.tap()
        XCTAssertTrue(app.buttons["2"].waitForExistence(timeout: 5))
        app.buttons["2"].tap()
        app.buttons["0"].tap()

        let slider = element("move-slide")
        scrollTo(slider)
        XCTAssertTrue(dragSlide(slider, until: app.staticTexts["Teléfono copiado"]), "U24: no apareció Teléfono copiado")
    }

    /// U24 #11 + U26: teclas «,» y «⌫» muestran «12,50 €» y luego «12,5 €».
    func testKeypadCommaAndBackspace() throws {
        launch(["-MiBancoDemoCard", "ima"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15))
        app.buttons["Mover dinero"].tap()

        let rev = element("move-target-rev")
        scrollTo(rev)
        rev.tap()

        XCTAssertTrue(app.buttons["1"].waitForExistence(timeout: 8))
        app.buttons["1"].tap()
        app.buttons["2"].tap()
        app.buttons[","].tap()
        app.buttons["5"].tap()
        app.buttons["0"].tap()
        XCTAssertTrue(app.staticTexts["12,50\(nbsp)€"].waitForExistence(timeout: 5), "U26: debe mostrar 12,50 €")

        app.buttons["keypad-backspace"].tap()
        XCTAssertTrue(app.staticTexts["12,5\(nbsp)€"].waitForExistence(timeout: 5), "U26: tras ⌫ debe mostrar 12,5 €")
    }

    /// U28: un fallo de lectura del cuaderno no permite pisar el Llavero con un cuaderno vacío.
    func testAccountBookLoadFailureDoesNotOverwrite() throws {
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoAccounts", "-MiBancoDemoKeychainFails"])
        XCTAssertTrue(app.navigationBars["Cuentas y contactos"].waitForExistence(timeout: 15), "No abrió Cuentas")

        // Tras el fallo inicial de lectura, Revolut aparece sin IBAN («Añadir IBAN»).
        let editRev = app.buttons["accounts-edit-iban-rev"]
        scrollTo(editRev)
        XCTAssertTrue(editRev.waitForExistence(timeout: 8))
        editRev.tap()

        let field = app.textFields["accounts-iban-field-rev"]
        scrollTo(field)
        field.tap()
        field.typeText("GB82WEST12345698765432")
        let save = app.buttons["Guardar"]
        save.tap()

        // 2.ª lectura también falla → texto único de error y no sobrescribe el Llavero.
        let errorMsg = app.staticTexts["No se pudo guardar. Inténtalo de nuevo."]
        XCTAssertTrue(errorMsg.waitForExistence(timeout: 5), "U28: debe avisar del fallo al guardar")

        // 3.ª lectura funciona → lee el cuaderno de demo (con el IBAN de imagin intacto) y aplica el cambio.
        save.tap()
        let imaIban = app.staticTexts["ES91 •••• 1332"]
        scrollTo(imaIban)
        XCTAssertTrue(imaIban.waitForExistence(timeout: 8), "U28: el IBAN de imagin de demo se perdió al guardar tras fallo")
    }

    /// U30: Trade Republic como origen hacia un contacto queda bloqueado con aviso en ámbar y sin deslizador.
    func testTradeRepublicToPayeeIsBlocked() throws {
        launch(["-MiBancoDemoCard", "ima"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15))
        app.buttons["Mover dinero"].tap()

        let ana = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Ana (demo)'")).firstMatch
        scrollTo(ana)
        ana.tap()
        XCTAssertTrue(app.buttons["2"].waitForExistence(timeout: 5))
        app.buttons["2"].tap()
        app.buttons["0"].tap()

        let trChip = app.buttons["move-from-tr"]
        XCTAssertTrue(trChip.waitForExistence(timeout: 5), "Falta ficha Trade Republic")
        trChip.tap()

        let blockedMsg = app.staticTexts["Desde Trade Republic solo puedes enviar dinero a tu cuenta de referencia. Elige otro banco."]
        scrollTo(blockedMsg)
        XCTAssertTrue(blockedMsg.waitForExistence(timeout: 5), "U30: falta el aviso de bloqueo desde Trade Republic")
        XCTAssertFalse(element("move-slide").exists, "U30: no debe existir move-slide cuando Trade Republic está bloqueado")
    }
}
