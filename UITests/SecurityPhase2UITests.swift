import XCTest

/// Pruebas de interfaz de Seguridad Fase 2:
/// - SEC-05: `PositionDetailSheet` y `AccountsView` con `MaskedAmountTextField` (ojo cerrado, vacío al abrir,
///   conservar valor al salir vacío, soltar foco sin animación al cerrar el ojo, y prueba en rojo con `issueMatcher`).
/// - SEC-07: descarga de logos apagada por defecto en instalación limpia y explicación clara de Google.
/// - SEC-08: bloqueo sin código ni Face ID no desbloquea en silencio, muestra el mensaje exacto e impide ver o tocar
///   Inicio hasta desactivar a conciencia.
/// - SEC-13: cerrar el ojo mientras el resumen habla para la voz de inmediato.
final class SecurityPhase2UITests: XCTestCase {
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

    private func value(_ el: XCUIElement) -> String {
        (el.value as? String) ?? ""
    }

    private func waitFor(_ predicate: NSPredicate, _ object: Any, timeout: TimeInterval) -> Bool {
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: object)
        return XCTWaiter().wait(for: [exp], timeout: timeout) == .completed
    }

    private func waitUntil(_ timeout: TimeInterval = 8, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return condition()
    }

    private func scrollTo(_ el: XCUIElement, in container: XCUIElement? = nil, swipes: Int = 8) {
        if el.waitForExistence(timeout: 2), el.isHittable { return }
        let target: XCUIElement = container ?? app!
        for _ in 0..<swipes {
            if el.exists && el.isHittable { return }
            target.swipeUp()
        }
        for _ in 0..<swipes {
            if el.exists && el.isHittable { return }
            target.swipeDown()
        }
    }

    private func drawsDigits(_ text: String) -> Bool {
        text.range(of: "dibujado: .*[0-9]", options: .regularExpression) != nil
    }

    private func drawsNothing(_ text: String) -> Bool {
        text.range(of: "dibujado: $", options: .regularExpression) != nil
    }

    private func probe() -> [String: String] {
        let raw = value(element("launch-probe"))
        var out: [String: String] = [:]
        for pair in raw.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 { out[String(parts[0])] = String(parts[1]) }
        }
        return out
    }

    private func sendToBackgroundAndReturn() {
        func inBackground() -> Bool {
            app.state == .runningBackground || app.state == .runningBackgroundSuspended
        }
        func backgrounds() -> Int { Int(probe()["fondos"] ?? "") ?? 0 }
        let before = backgrounds()
        for _ in 1...3 {
            let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
            settings.activate()
            _ = settings.wait(for: .runningForeground, timeout: 20)
            if !waitUntil(10, inBackground) {
                XCUIDevice.shared.press(.home)
                _ = waitUntil(10, inBackground)
            }
            Thread.sleep(forTimeInterval: 1.5)
            app.activate()
            guard app.wait(for: .runningForeground, timeout: 15) else { continue }
            if waitUntil(10, { self.probe()["escena"] == "activa" && backgrounds() > before }) { return }
        }
        XCTFail("La app no completó el paso por segundo plano y vuelta a activa")
    }

    // MARK: - SEC-05 · PositionDetailSheet con MaskedAmountTextField

    private func checkPositionManualPriceHidden(_ extra: [String]) {
        launch(["-MiBancoDemoCard", "inv", "-MiBancoDemoPosition", "-MiBancoDemoPrivate", "-MiBancoDemoDrawnAmounts"] + extra)
        let scroll = app.scrollViews["position-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 20), "No se abrió la hoja de posición")

        let manualButton = app.buttons["Poner precio a mano"]
        scrollTo(manualButton, in: scroll)
        XCTAssertTrue(manualButton.waitForExistence(timeout: 8), "Falta el botón Poner precio a mano")
        manualButton.tap()

        let field = app.textFields["manualPriceField"]
        scrollTo(field, in: scroll)
        XCTAssertTrue(field.waitForExistence(timeout: 8), "Falta manualPriceField")

        let closedVal = value(field)
        XCTAssertTrue(closedVal.hasPrefix("importe oculto"), "Con el ojo cerrado el campo expone el precio: \(closedVal)")
        XCTAssertFalse(drawsDigits(closedVal), "Con el ojo cerrado el campo sigue dibujando una cifra: \(closedVal)")
    }

    func testPositionDetailManualPriceObeysClosedEyeAndPreservesValue() throws {
        checkPositionManualPriceHidden([])
        let scroll = app.scrollViews["position-scroll"]
        let field = app.textFields["manualPriceField"]

        // 1. Al enfocar con el ojo cerrado se abre vacío y nunca enseña el precio guardado (200,00).
        field.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5), "El campo de precio no abrió el teclado")
        XCTAssertTrue(drawsNothing(value(field)), "Al editar con el ojo cerrado el campo no se abre vacío: \(value(field))")
        XCTAssertTrue(value(field).hasPrefix("importe oculto"), "Al editar vacío con el ojo cerrado se lee la cifra: \(value(field))")

        // 2. Guardar sin teclear nada conserva el precio de mercado original sin borrarlo ni convertirlo en manual.
        let save = app.buttons["Guardar"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "Falta Guardar")
        save.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "exists == false"), field, timeout: 8),
                      "Guardar vacío con ojo cerrado no cerró el editor")

        // Abrir el ojo en Inicio y volver a abrir Apple para confirmar que conserva 200,00 € · mercado.
        app.buttons["Cerrar"].tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "exists == false"), scroll, timeout: 8), "No se cerró la hoja de posición")
        let showEye = app.buttons["Mostrar importes"]
        XCTAssertTrue(showEye.waitForExistence(timeout: 8), "Falta el ojo cerrado en Inicio")
        showEye.tap()

        let appleRow = app.buttons["Apple"]
        scrollTo(appleRow)
        XCTAssertTrue(appleRow.waitForExistence(timeout: 10), "Falta Apple tras abrir el ojo")
        appleRow.tap()
        let marketPrice = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Precio:' AND label CONTAINS '200,00' AND label CONTAINS 'mercado'"))
            .firstMatch
        XCTAssertTrue(marketPrice.waitForExistence(timeout: 8),
                      "Entrar y salir vacío con el ojo cerrado alteró el precio guardado de Apple")
    }

    func testPositionDetailManualPriceCatchesRegressedTransparentDigits() throws {
        let options = XCTExpectedFailure.Options()
        options.isStrict = true
        options.issueMatcher = { issue in
            issue.compactDescription.contains("sigue dibujando una cifra")
        }
        XCTExpectFailure("Con -MiBancoDemoRegressMaskedField el campo dibuja la cifra en transparente y la prueba debe fallar",
                         options: options) {
            checkPositionManualPriceHidden(["-MiBancoDemoRegressMaskedField"])
        }
    }

    func testPositionDetailClosingEyeWhileEditingReleasesFocus() throws {
        launch(["-MiBancoDemoPosition", "-MiBancoDemoDrawnAmounts", "-MiBancoDemoCloseEyeWhenFocused", "8"])
        let scroll = app.scrollViews["position-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 20), "No se abrió la hoja de posición")

        let manualButton = app.buttons["Poner precio a mano"]
        scrollTo(manualButton, in: scroll)
        XCTAssertTrue(manualButton.waitForExistence(timeout: 8), "Falta Poner precio a mano")
        manualButton.tap()

        let field = app.textFields["manualPriceField"]
        XCTAssertTrue(field.waitForExistence(timeout: 8), "Falta manualPriceField")
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5), "Con el ojo abierto el editor no enfocó el campo")
        XCTAssertTrue(drawsDigits(value(field)), "Control: con el ojo abierto el campo debe dibujar su cifra: \(value(field))")

        // A los 8 s se cierra el ojo: el teclado se va y el campo pasa a máscara sin cifras dibujadas.
        XCTAssertTrue(waitFor(NSPredicate(format: "value BEGINSWITH %@", "importe oculto"), field, timeout: 18),
                      "Al cerrarse el ojo el campo de precio no pasó a máscara: \(value(field))")
        XCTAssertTrue(waitFor(NSPredicate(format: "exists == false"), app.keyboards.element, timeout: 8),
                      "Al cerrarse el ojo el teclado no desapareció del campo de precio")
        XCTAssertFalse(drawsDigits(value(field)), "Tras cerrarse el ojo el campo sigue dibujando una cifra: \(value(field))")
    }

    // MARK: - SEC-05 · AccountsView (colchón mínimo) con MaskedAmountTextField

    private func checkAccountsFloorHidden(_ extra: [String]) {
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoAccounts", "-MiBancoDemoFloor",
                "-MiBancoDemoPrivate", "-MiBancoDemoDrawnAmounts"] + extra)
        XCTAssertTrue(app.navigationBars["Cuentas y contactos"].waitForExistence(timeout: 20),
                      "No se abrió Cuentas y contactos")
        let floor = app.textFields["accounts-floor-field-rev"]
        scrollTo(floor)
        XCTAssertTrue(floor.waitForExistence(timeout: 8), "Falta el colchón mínimo de Revolut")

        let closedVal = value(floor)
        XCTAssertTrue(closedVal.hasPrefix("importe oculto"), "Con el ojo cerrado el colchón expone su valor: \(closedVal)")
        XCTAssertFalse(drawsDigits(closedVal), "Con el ojo cerrado el colchón sigue dibujando una cifra: \(closedVal)")
    }

    func testAccountsFloorObeysClosedEyeAndPreservesValue() throws {
        checkAccountsFloorHidden([])
        let floor = app.textFields["accounts-floor-field-rev"]

        // 1. Al enfocar con el ojo cerrado se abre vacío (nunca 341,20).
        floor.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5), "El colchón mínimo no abrió el teclado")
        XCTAssertTrue(drawsNothing(value(floor)), "Al editar con el ojo cerrado el colchón no se abre vacío: \(value(floor))")
        XCTAssertTrue(value(floor).hasPrefix("importe oculto"), "Al editar vacío con el ojo cerrado se lee el colchón: \(value(floor))")

        // 2. Salir sin teclear conserva el valor guardado (341,20 €).
        floor.typeText("\n")
        XCTAssertTrue(waitFor(NSPredicate(format: "value BEGINSWITH %@", "importe oculto"), floor, timeout: 5),
                      "Al salir sin teclear el colchón no volvió a la máscara: \(value(floor))")
        XCTAssertFalse(drawsDigits(value(floor)), "Al salir sin teclear el colchón dibuja cifras: \(value(floor))")

        // Volver a Ajustes, abrir el ojo y reabrir Cuentas para comprobar que 341,20 sigue intacto.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 10), "No volvió a Ajustes")
        let eyeToggle = element("settings-private-mode")
        scrollTo(eyeToggle)
        XCTAssertTrue(eyeToggle.waitForExistence(timeout: 8), "Falta el interruptor Modo privado")
        eyeToggle.tap()

        let accountsRow = element("settings-accounts")
        scrollTo(accountsRow)
        XCTAssertTrue(accountsRow.waitForExistence(timeout: 8), "Falta Cuentas y contactos")
        accountsRow.tap()
        XCTAssertTrue(app.navigationBars["Cuentas y contactos"].waitForExistence(timeout: 10), "No reabrió Cuentas y contactos")
        scrollTo(floor)
        XCTAssertTrue(waitFor(NSPredicate(format: "value CONTAINS %@", "341,20"), floor, timeout: 8),
                      "Salir vacío con el ojo cerrado borró o cambió el colchón guardado: \(value(floor))")
    }

    func testAccountsFloorCatchesRegressedTransparentDigits() throws {
        let options = XCTExpectedFailure.Options()
        options.isStrict = true
        options.issueMatcher = { issue in
            issue.compactDescription.contains("sigue dibujando una cifra")
        }
        XCTExpectFailure("Con -MiBancoDemoRegressMaskedField el colchón dibuja la cifra en transparente y la prueba debe fallar",
                         options: options) {
            checkAccountsFloorHidden(["-MiBancoDemoRegressMaskedField"])
        }
    }

    func testAccountsFloorClosingEyeWhileEditingReleasesFocus() throws {
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoAccounts", "-MiBancoDemoFloor",
                "-MiBancoDemoDrawnAmounts", "-MiBancoDemoCloseEyeWhenFocused", "6"])
        XCTAssertTrue(app.navigationBars["Cuentas y contactos"].waitForExistence(timeout: 20),
                      "No se abrió Cuentas y contactos")
        let floor = app.textFields["accounts-floor-field-rev"]
        scrollTo(floor)
        XCTAssertTrue(floor.waitForExistence(timeout: 8), "Falta el colchón mínimo de Revolut")
        XCTAssertTrue(drawsDigits(value(floor)), "Control: con el ojo abierto el colchón debe dibujar 341,20: \(value(floor))")

        floor.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5), "El colchón no enfocó el teclado")
        XCTAssertTrue(waitFor(NSPredicate(format: "value BEGINSWITH %@", "importe oculto"), floor, timeout: 16),
                      "Al cerrarse el ojo el colchón en edición no pasó a máscara: \(value(floor))")
        XCTAssertTrue(waitFor(NSPredicate(format: "exists == false"), app.keyboards.element, timeout: 8),
                      "Al cerrarse el ojo el teclado no desapareció del colchón")
        XCTAssertFalse(drawsDigits(value(floor)), "Tras cerrarse el ojo el colchón sigue dibujando una cifra: \(value(floor))")
    }

    // MARK: - SEC-07 · Descarga de logos apagada por defecto + explicación de Google

    func testLogoDownloadsOffByDefaultWithGoogleExplanation() throws {
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoResetLogoDefault"])
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 20), "No se ve Ajustes")

        let toggle = element("settings-logo-downloads")
        scrollTo(toggle, swipes: 12)
        XCTAssertTrue(toggle.waitForExistence(timeout: 8), "Falta el interruptor de descarga de logos")
        XCTAssertEqual(value(toggle), "0", "SEC-07: la descarga de logos debe empezar apagada por defecto en instalación limpia")

        let googleText = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Google"))
            .firstMatch
        XCTAssertTrue(googleText.waitForExistence(timeout: 5),
                      "SEC-07: falta la explicación clara de que activar los logos consulta en Google")

        // Comprobar que el interruptor funciona y dejarlo de nuevo apagado.
        toggle.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "value == '1'"), toggle, timeout: 5), "El interruptor de logos no se activó")
        toggle.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "value == '0'"), toggle, timeout: 5), "El interruptor de logos no volvió a apagarse")
    }

    // MARK: - SEC-08 · Sin código ni Face ID no desbloquea en silencio

    func testLockWithoutPasscodeBlocksUntilConsciouslyDisabled() throws {
        launch(["-MiBancoDemoNoPasscode"])

        let message = element("lock-no-passcode-message")
        XCTAssertTrue(message.waitForExistence(timeout: 20), "SEC-08: falta el aviso de falta de código en el bloqueo")
        XCTAssertEqual(
            message.label,
            "Para proteger Onyx, pon un código en el iPhone (Ajustes > Face ID y código)",
            "SEC-08: el mensaje del bloqueo sin código no coincide exactamente"
        )

        let disableButton = app.buttons["lock-disable-button"]
        XCTAssertTrue(disableButton.waitForExistence(timeout: 5), "SEC-08: falta el botón para desactivar el bloqueo")
        XCTAssertEqual(disableButton.label, "Desactivar bloqueo de Onyx")
        XCTAssertFalse(app.buttons["Desbloquear"].exists, "Sin código no debe mostrarse el botón de Face ID")
        XCTAssertFalse(element("launch-layer").exists, "La capa del arranque no puede existir con el bloqueo puesto")

        // Verificar durante >5 s que NO desbloquea en silencio y que Inicio no es tocable ni visible encima.
        let eye = app.buttons["Ocultar importes"]
        let homeTitle = app.staticTexts["Tu dinero"]
        for look in 0..<10 {
            XCTAssertTrue(message.exists, "Mirada \(look): el bloqueo sin código desapareció en silencio")
            XCTAssertTrue(disableButton.exists, "Mirada \(look): el botón de desactivar desapareció")
            XCTAssertFalse(homeTitle.exists && homeTitle.isHittable, "Mirada \(look): Inicio es tocable bajo el bloqueo")
            XCTAssertFalse(eye.exists && eye.isHittable, "Mirada \(look): el ojo de Inicio es tocable bajo el bloqueo")
            Thread.sleep(forTimeInterval: 0.5)
        }

        // Tocar sobre el centro de la pantalla tampoco desbloquea ni atraviesa hacia Inicio.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertTrue(message.exists, "Un toque fuera del botón desbloqueó sin código")
        XCTAssertFalse(app.buttons["Mostrar importes"].exists, "Un toque sobre el bloqueo llegó al ojo de Inicio")

        // Solo al pulsar «Desactivar bloqueo de Onyx» a conciencia se entra limpiamente en Inicio.
        disableButton.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "exists == false"), disableButton, timeout: 10),
                      "Pulsar Desactivar bloqueo de Onyx no quitó el bloqueo")
        XCTAssertTrue(waitUntil(10) { self.probe()["fundido"] != "1" }, "El fundido del bloqueo no terminó")
        XCTAssertTrue(homeTitle.waitForExistence(timeout: 10), "Tras desactivar el bloqueo no aparece Inicio")
        XCTAssertTrue(eye.waitForExistence(timeout: 8), "Tras desactivar el bloqueo falta el ojo")
        eye.tap()
        XCTAssertTrue(app.buttons["Mostrar importes"].waitForExistence(timeout: 5),
                      "Tras desactivar el bloqueo, Inicio no responde al toque")

        // Tras pasar por segundo plano, el bloqueo queda desactivado (no vuelve a aparecer).
        sendToBackgroundAndReturn()
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertFalse(disableButton.exists, "Tras desactivar el bloqueo a conciencia volvió a bloquear al volver")
        XCTAssertFalse(app.buttons["Desbloquear"].exists, "Tras desactivar el bloqueo apareció Face ID al volver")
    }

    // MARK: - SEC-13 · Cerrar el ojo para la voz del resumen de inmediato

    func testClosingEyeStopsBriefingSpeechImmediately() throws {
        launch(["-MiBancoDemoBriefing", "busy", "-MiBancoDemoCloseEyeWhenSpeaking", "2"])
        let listen = app.buttons["briefing-listen"]
        XCTAssertTrue(listen.waitForExistence(timeout: 25), "Falta el botón Escuchar del resumen")
        XCTAssertEqual(listen.label, "Escuchar")

        listen.tap()
        XCTAssertTrue(waitUntil(8) { listen.label == "Parar" && self.value(listen) != "-" },
                      "La lectura en voz alta del resumen no empezó: label=\(listen.label) value=\(value(listen))")

        // A los 2 s se cierra el ojo: la voz debe pararse de inmediato y no volver sola.
        XCTAssertTrue(waitUntil(10) { listen.label == "Escuchar" && self.value(listen) == "-" },
                      "SEC-13: al cerrarse el ojo la voz no se paró: label=\(listen.label) value=\(value(listen))")
        Thread.sleep(forTimeInterval: 2.0)
        XCTAssertEqual(listen.label, "Escuchar", "SEC-13: la voz volvió a arrancar sola tras cerrarse el ojo")
        XCTAssertEqual(value(listen), "-", "SEC-13: volvió a resaltarse una línea con el ojo cerrado")

        // Confirmar que el resumen quedó en modo privado sin cifras expuestas.
        let sheet = app.scrollViews["briefing-scroll"]
        XCTAssertTrue(sheet.exists, "Falta el resumen")
        let leaks = sheet.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '€' OR label MATCHES '.*[0-9]+,[0-9]{2}.*'"))
            .count
        XCTAssertEqual(leaks, 0, "Tras cerrar el ojo durante la lectura quedaron cifras visibles en el resumen")
    }
}
