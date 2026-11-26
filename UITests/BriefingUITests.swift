import XCTest

/// Toques reales sobre «Tu resumen», Onyx («Te puede interesar», «Pregúntame»), lectura en voz alta y ajustes del asistente
/// (Plan 4b, tareas 9, 10 y 13 ampliada A1–A6). Siempre en modo demo, sin red ni escritura persistente.
final class BriefingUITests: XCTestCase {
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

    /// Desplaza hacia abajo dentro de una pantalla estándar (Ajustes / Avisos) sin salir de rango.
    private func scrollTo(_ el: XCUIElement, swipes: Int = 8) {
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

    private func isClearOfBottomBar(_ el: XCUIElement) -> Bool {
        guard el.exists && el.isHittable else { return false }
        let frame = el.frame
        let screenH = app.windows.firstMatch.frame.height
        guard screenH > 0, !frame.isEmpty else { return true }
        return frame.minY >= 80 && frame.maxY <= screenH - 125
    }

    /// Desplaza dentro del `ScrollView` de la hoja del resumen sin tirar desde el borde superior (evita cerrar la hoja)
    /// y dejando el elemento libre de la barra inferior («Vale»).
    private func scrollInBriefingSheet(to el: XCUIElement, maxSwipes: Int = 10) {
        if el.waitForExistence(timeout: 2), isClearOfBottomBar(el) { return }
        let scroller = app.scrollViews["briefing-scroll"].exists ? app.scrollViews["briefing-scroll"] : app.scrollViews.firstMatch
        for _ in 0..<maxSwipes {
            if isClearOfBottomBar(el) { return }
            if el.exists && el.isHittable {
                // Está visible pero cerca de la barra inferior («Vale»): un arrastre corto lo sube al centro.
                let start = scroller.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.68))
                let end = scroller.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.38))
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

    /// Review Focus 2: el resumen aparece una vez solo al abrir y luego se puede volver a abrir con «Tu resumen».
    func testBriefingOnceThenFromButton() throws {
        launch(["-MiBancoDemoBriefing", "busy"])

        let doneButton = app.buttons["Vale"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 12), "El resumen automático no apareció al abrir")
        doneButton.tap()

        XCTAssertTrue(
            waitFor(NSPredicate(format: "exists == false"), doneButton, timeout: 8),
            "La hoja del resumen no se cerró al pulsar Vale"
        )

        // U35 #3: tras «Vale», salir y volver a la app NO vuelve a abrir el resumen automático en 5 s.
        Thread.sleep(forTimeInterval: 2.0)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1.0)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "La app no volvió a primer plano")
        XCTAssertFalse(doneButton.waitForExistence(timeout: 5), "U35: el resumen volvió a abrirse solo el mismo día")

        let reopenButton = app.buttons["Tu resumen"]
        XCTAssertTrue(reopenButton.waitForExistence(timeout: 8), "Falta el botón «Tu resumen» en la barra de Inicio")
        reopenButton.tap()

        XCTAssertTrue(doneButton.waitForExistence(timeout: 8), "El resumen no se volvió a abrir desde «Tu resumen»")
    }

    /// Review Focus 3 + U36: con modo privado activo, ninguna etiqueta expone «€», «%», cifras `,dd` ni «•».
    func testBriefingPrivateHidesAmounts() throws {
        launch(["-MiBancoDemoBriefing", "busy", "-MiBancoDemoShortfall", "-MiBancoDemoPrivate"])

        let doneButton = app.buttons["Vale"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 12), "El resumen en modo privado no apareció")

        let sheet = app.scrollViews["briefing-scroll"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 8), "Falta el contenedor del resumen")

        let spokenMasked = sheet.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'importe oculto'"))
            .firstMatch
        XCTAssertTrue(spokenMasked.waitForExistence(timeout: 8), "U36: falta «importe oculto» en las etiquetas de VoiceOver")

        XCTAssertEqual(sheet.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '€'")).count, 0, "El resumen expuso '€' en modo privado")
        XCTAssertEqual(sheet.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '%'")).count, 0, "El resumen expuso '%' en modo privado")
        XCTAssertEqual(sheet.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES '.*[0-9]+,[0-9]{2}.*'")).count, 0, "U36: el resumen expuso cifras con decimales en privado")
        XCTAssertEqual(sheet.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '•'")).count, 0, "U36: ninguna etiqueta de VoiceOver debe contener '•'")

        let tipButton = element("briefing-tip-action")
        scrollInBriefingSheet(to: tipButton)
        XCTAssertTrue(tipButton.waitForExistence(timeout: 6), "Falta el botón de consejo en modo privado")
        XCTAssertEqual(tipButton.label, "Preparar traspaso", "El botón del consejo expuso importe en modo privado")

        let balancesChip = element("assistant-chip-balances")
        scrollInBriefingSheet(to: balancesChip)
        XCTAssertTrue(balancesChip.waitForExistence(timeout: 6), "Falta la ficha «¿Cuánto tengo?» en modo privado")
        balancesChip.tap()

        let answerCard = element("assistant-answer-card")
        scrollInBriefingSheet(to: answerCard)
        XCTAssertTrue(answerCard.waitForExistence(timeout: 8), "No apareció la respuesta del asistente en modo privado")

        XCTAssertEqual(sheet.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '€'")).count, 0, "La respuesta del asistente expuso '€' en modo privado")
        XCTAssertEqual(sheet.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '%'")).count, 0, "La respuesta del asistente expuso '%' en modo privado")
        XCTAssertEqual(sheet.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES '.*[0-9]+,[0-9]{2}.*'")).count, 0, "U36: la respuesta expuso cifras en privado")
        XCTAssertEqual(sheet.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '•'")).count, 0, "U36: la respuesta expuso '•' en VoiceOver")
    }

    /// Tocar la acción del consejo de falta de saldo abre «Mover dinero» con el importe ya rellenado.
    func testBriefingActionOpensMoveMoney() throws {
        launch(["-MiBancoDemoBriefing", "busy", "-MiBancoDemoShortfall"])

        let doneButton = app.buttons["Vale"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 12), "El resumen con falta de saldo no apareció")

        let tipAction = app.buttons["Pasar 10,00\(nbsp)€"]
        scrollInBriefingSheet(to: tipAction)
        XCTAssertTrue(tipAction.waitForExistence(timeout: 8), "Falta el botón «Pasar 10,00 €» en el consejo")
        tipAction.tap()

        XCTAssertTrue(app.navigationBars["Mover dinero"].waitForExistence(timeout: 10), "No se abrió la hoja Mover dinero")
        XCTAssertTrue(
            // U26: el teclado enseña lo tecleado sin decimales que nadie escribió: «10 €».
            app.staticTexts["10\(nbsp)€"].waitForExistence(timeout: 8),
            "Mover dinero no llegó con 10,00 € pre-rellenado"
        )
    }

    /// Tarea 10: el botón «Escuchar» cambia a «Parar» y vuelve a «Escuchar».
    func testListenToggles() throws {
        launch(["-MiBancoDemoBriefing", "busy"])

        let doneButton = app.buttons["Vale"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 12), "El resumen no apareció")

        let listen = app.buttons["Escuchar"]
        XCTAssertTrue(listen.waitForExistence(timeout: 8), "Falta el botón «Escuchar»")
        listen.tap()

        let stop = app.buttons["Parar"]
        XCTAssertTrue(stop.waitForExistence(timeout: 6), "El botón no pasó a «Parar» al escuchar")
        stop.tap()

        XCTAssertTrue(listen.waitForExistence(timeout: 6), "El botón no volvió a «Escuchar» al parar")
    }

    /// A1–A4: «Te puede interesar» descarta una tarjeta concreta y «Pregúntame» rechaza consejos de inversión literalmente y contesta hechos.
    func testAssistantAskAndInterestCards() throws {
        launch(["-MiBancoDemoBriefing", "busy"])

        let doneButton = app.buttons["Vale"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 12), "El resumen no apareció")

        // La subida de Spotify en la demo garantiza siempre la tarjeta de cambio de suscripción.
        let subDislike = element("card-dislike-subscriptionPriceChange")
        scrollInBriefingSheet(to: subDislike)
        XCTAssertTrue(subDislike.waitForExistence(timeout: 8), "Falta la tarjeta de cambio de suscripción en «Te puede interesar»")
        subDislike.tap()
        XCTAssertTrue(
            waitFor(NSPredicate(format: "exists == false"), subDislike, timeout: 15),
            "La tarjeta descartada no desapareció al pulsar «No me interesa»"
        )

        let questionField = element("assistant-question-field")
        scrollInBriefingSheet(to: questionField)
        XCTAssertTrue(questionField.waitForExistence(timeout: 8), "Falta el campo «Pregúntame algo de tu dinero…»")
        questionField.tap()
        // U34 #1: sin `\n`, se exige tocar `assistant-send` habilitado.
        questionField.typeText("¿Debo comprar Apple?")
        let sendButton = element("assistant-send")
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5), "U34: falta assistant-send")
        XCTAssertTrue(sendButton.isEnabled, "U34: assistant-send debe estar activo antes de tocarlo")
        sendButton.tap()

        let refusal = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'asesor financiero autorizado'")
        ).firstMatch
        scrollInBriefingSheet(to: refusal)
        XCTAssertTrue(refusal.waitForExistence(timeout: 8), "No apareció la negativa de consejo financiero")

        // Tras responder, el chip «¿Cuánto tengo?» puede estar en el carrusel horizontal encima de la respuesta.
        let balancesChip = element("assistant-chip-balances")
        let chipsScroll = app.scrollViews["assistant-chips-scroll"]
        scrollInBriefingSheet(to: chipsScroll)
        if !balancesChip.isHittable && chipsScroll.exists {
            chipsScroll.swipeLeft()
        }
        XCTAssertTrue(balancesChip.waitForExistence(timeout: 6), "Falta la ficha sugerida «¿Cuánto tengo?»")
        balancesChip.tap()

        let totalAnswer = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'En total tienes'")
        ).firstMatch
        scrollInBriefingSheet(to: totalAnswer)
        XCTAssertTrue(totalAnswer.waitForExistence(timeout: 8), "No apareció la respuesta factual de saldos")
    }

    /// A4 + Tarea 10: Ajustes › Asistente muestra y cambia los interruptores de temas; Avisos muestra y cambia «Resumen cada mañana».
    func testAssistantSettingsAndMorningRule() throws {
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoAssistantSettings"])
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 15), "Ajustes no apareció")

        let firstTopic = element("assistant-topic-unusualPayment")
        scrollTo(firstTopic)
        XCTAssertTrue(firstTopic.waitForExistence(timeout: 10), "Falta el interruptor de tema en Ajustes › Asistente")
        XCTAssertEqual(firstTopic.value as? String, "1", "El tema debería empezar activo")
        firstTopic.tap()
        XCTAssertTrue(
            waitFor(NSPredicate(format: "value == '0'"), firstTopic, timeout: 6),
            "El interruptor del tema no se apagó al tocarlo"
        )

        let lastTopic = element("assistant-topic-portfolioMover")
        scrollTo(lastTopic)
        XCTAssertTrue(lastTopic.waitForExistence(timeout: 8), "Falta el sexto tema en Ajustes › Asistente")

        launch(["-MiBancoDemoScreen", "avisos", "-MiBancoDemoRules"])
        XCTAssertTrue(app.navigationBars["Avisos"].waitForExistence(timeout: 15), "Avisos no apareció")

        let morningRule = element("alert-rule-morningBriefing")
        scrollTo(morningRule)
        XCTAssertTrue(morningRule.waitForExistence(timeout: 10), "Falta la regla «Resumen cada mañana» en Avisos")
        // U41: comprobar el subtítulo nuevo del aviso de la mañana.
        XCTAssertTrue(
            app.staticTexts["A las 08:30, si aún no has visto el resumen."].waitForExistence(timeout: 5),
            "U41: falta el subtítulo actualizado de Resumen cada mañana"
        )
        let morningTime = element("morning-briefing-time")
        scrollTo(morningTime)
        XCTAssertTrue(morningTime.waitForExistence(timeout: 6), "Falta el selector de hora de «Resumen cada mañana»")

        morningRule.tap()
        XCTAssertTrue(
            waitFor(NSPredicate(format: "exists == false"), morningTime, timeout: 6),
            "El selector de hora no se ocultó al apagar «Resumen cada mañana»"
        )
        morningRule.tap()
        XCTAssertTrue(morningTime.waitForExistence(timeout: 6), "El selector de hora no volvió al encender la regla")
    }

    /// Al salir a segundo plano, la hoja del resumen abierta a mano se cierra sola y nunca queda abierta al volver.
    func testBriefingDismissesOnBackground() throws {
        launch([])

        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no apareció")
        let button = app.buttons["Tu resumen"]
        XCTAssertTrue(button.waitForExistence(timeout: 8), "Falta el botón «Tu resumen»")
        button.tap()

        let doneButton = app.buttons["Vale"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 8), "La hoja del resumen no se abrió")

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1.0)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "La app no volvió a primer plano")

        XCTAssertTrue(
            waitFor(NSPredicate(format: "exists == false"), doneButton, timeout: 8),
            "La hoja del resumen siguió abierta tras volver de segundo plano"
        )
    }

    /// U33: el selector de hora de «Resumen cada mañana» nunca puede quedar encima del bloqueo al volver de segundo plano.
    func testMorningTimePickerNeverAboveLock() throws {
        launch(["-MiBancoDemoLock", "-MiBancoDemoScreen", "avisos", "-MiBancoDemoRules"])

        // Esperar a que el bloqueo de demo se quite solo (~4 s) y aparezca Avisos.
        XCTAssertTrue(app.navigationBars["Avisos"].waitForExistence(timeout: 18), "Avisos no apareció tras el bloqueo")

        let morningTime = element("morning-briefing-time")
        scrollTo(morningTime)
        XCTAssertTrue(morningTime.waitForExistence(timeout: 8), "Falta morning-briefing-time")
        morningTime.tap()

        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 6), "No apareció ninguna rueda de hora al tocar morning-briefing-time")
        XCTAssertGreaterThan(app.pickerWheels.count, 0, "Debe haber ruedas de hora visibles")

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1.0)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "La app no volvió a primer plano")

        // Mientras se ve el bloqueo (primeros ~4 s), no debe haber ruedas ni selectores tocables por encima.
        let unlock = app.buttons["Desbloquear"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 5), "No se mostró el bloqueo al volver de segundo plano")
        XCTAssertEqual(app.pickerWheels.count, 0, "U33: quedaron ruedas de hora encima del bloqueo (\(app.pickerWheels.count))")
        let hittablePickers = app.datePickers.allElementsBoundByIndex.filter { $0.isHittable }
            + app.pickerWheels.allElementsBoundByIndex.filter { $0.isHittable }
        XCTAssertEqual(hittablePickers.count, 0, "U33: quedó un selector de hora tocable encima del bloqueo")
    }

    /// U33: cambiar la hora en la rueda en línea actualiza el subtítulo de «Resumen cada mañana».
    func testMorningTimeChangesSubtitle() throws {
        launch(["-MiBancoDemoScreen", "avisos", "-MiBancoDemoRules"])
        XCTAssertTrue(app.navigationBars["Avisos"].waitForExistence(timeout: 15), "Avisos no apareció")

        let morningTime = element("morning-briefing-time")
        scrollTo(morningTime)
        XCTAssertTrue(morningTime.waitForExistence(timeout: 8), "Falta morning-briefing-time")
        morningTime.tap()

        let hourWheel = app.pickerWheels.element(boundBy: 0)
        XCTAssertTrue(hourWheel.waitForExistence(timeout: 6), "U33: no apareció la rueda de hora")
        hourWheel.adjust(toPickerWheelValue: "9")

        XCTAssertTrue(
            app.staticTexts["A las 09:30, si aún no has visto el resumen."].waitForExistence(timeout: 8),
            "U33/U41: el subtítulo no se actualizó a las 09:30"
        )
    }

    /// U34 #1: escribir sin `\n` y tocar `assistant-send` devuelve la tarjeta de respuesta.
    func testAssistantSendButton() throws {
        launch(["-MiBancoDemoBriefing", "busy"])
        XCTAssertTrue(app.buttons["Vale"].waitForExistence(timeout: 12))

        let field = element("assistant-question-field")
        scrollInBriefingSheet(to: field)
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        field.typeText("¿Cuánto tengo?")

        let send = element("assistant-send")
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertTrue(send.isEnabled, "U34: assistant-send debe estar habilitado")
        send.tap()

        let answerCard = element("assistant-answer-card")
        scrollInBriefingSheet(to: answerCard)
        XCTAssertTrue(answerCard.waitForExistence(timeout: 8), "U34: falta assistant-answer-card")
        let totalLine = answerCard.staticTexts.matching(NSPredicate(format: "label CONTAINS 'En total tienes'")).firstMatch
        XCTAssertTrue(totalLine.waitForExistence(timeout: 6), "U34: la respuesta no contiene «En total tienes»")
    }

    /// U34 #2 + U38: «Me interesa» lleva el título en su etiqueta y queda seleccionado sin quitar la tarjeta.
    func testInterestedMarksCard() throws {
        launch(["-MiBancoDemoBriefing", "busy"])
        XCTAssertTrue(app.buttons["Vale"].waitForExistence(timeout: 12))

        let likeBtn = app.buttons["Me interesa: Cambio en una suscripción"]
        scrollInBriefingSheet(to: likeBtn)
        XCTAssertTrue(likeBtn.waitForExistence(timeout: 8), "U34/U38: falta «Me interesa: Cambio en una suscripción»")
        likeBtn.tap()

        XCTAssertTrue(waitFor(NSPredicate(format: "selected == true"), likeBtn, timeout: 6), "U34: Me interesa no quedó seleccionado")
        XCTAssertTrue(likeBtn.exists, "U34: la tarjeta debe permanecer tras Me interesa")
    }

    /// U34 #3: tocar `briefing-close` cierra la hoja del resumen.
    func testBriefingCloseButton() throws {
        launch(["-MiBancoDemoBriefing", "busy"])
        let done = element("briefing-done")
        XCTAssertTrue(done.waitForExistence(timeout: 12))

        let close = element("briefing-close")
        XCTAssertTrue(close.waitForExistence(timeout: 5), "U34: falta briefing-close")
        close.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "exists == false"), done, timeout: 8), "U34: briefing-close no cerró el resumen")
    }

    /// U34 #4: tocar la acción de presupuestos del resumen selecciona la pestaña Gasto y abre Presupuestos.
    func testBriefingLineActionOpensBudgets() throws {
        launch(["-MiBancoDemoBriefing", "busy"])
        XCTAssertTrue(app.buttons["Vale"].waitForExistence(timeout: 12))

        let tipAction = element("briefing-tip-action")
        scrollInBriefingSheet(to: tipAction)
        XCTAssertTrue(tipAction.waitForExistence(timeout: 8), "U34: falta la acción de presupuestos del resumen")
        tipAction.tap()

        XCTAssertTrue(app.tabBars.buttons["Gasto"].waitForExistence(timeout: 8))
        XCTAssertTrue(
            waitFor(NSPredicate(format: "selected == true"), app.tabBars.buttons["Gasto"], timeout: 8),
            "U34: la pestaña Gasto no quedó seleccionada"
        )
    }

    /// U78 (U34 #4, B-M3): tocar una FILA del resumen con acción (`briefing-line-<id>`), no el consejo. El resumen `busy` no
    /// tiene fila de presupuestos (los presupuestos solo salen en el consejo, probado arriba); su fila con acción es el aviso
    /// «La conexión con Revolut caduca el 30 nov» (`attention-1`), que lleva a Ajustes › Revolut.
    func testBriefingRowActionOpensBank() throws {
        launch(["-MiBancoDemoBriefing", "busy"])
        XCTAssertTrue(app.buttons["Vale"].waitForExistence(timeout: 12))
        XCTAssertFalse(app.buttons["bank-import-statement"].exists, "U34: la pantalla del banco ya estaba abierta antes del toque")

        let row = element("briefing-line-attention-1")
        scrollInBriefingSheet(to: row)
        XCTAssertTrue(row.waitForExistence(timeout: 8), "U34: falta la fila briefing-line-attention-1")
        XCTAssertTrue(row.label.contains("Revolut"), "U34: la fila con acción no es la de Revolut: \(row.label)")
        row.tap()

        XCTAssertTrue(waitFor(NSPredicate(format: "exists == false"), element("briefing-done"), timeout: 8),
                      "U34: tocar la fila no cerró el resumen")
        XCTAssertTrue(waitFor(NSPredicate(format: "selected == true"), app.tabBars.buttons["Ajustes"], timeout: 8),
                      "U34: tocar la fila no llevó a Ajustes")
        XCTAssertTrue(app.buttons["bank-import-statement"].waitForExistence(timeout: 10),
                      "U34: tocar la fila no abrió la pantalla de Revolut")
    }

    /// U34 #5: tocar la cabecera de la tarjeta `subscriptionPriceChange` abre el detalle del movimiento de Spotify.
    func testInterestCardHeaderOpensAction() throws {
        launch(["-MiBancoDemoBriefing", "busy"])
        XCTAssertTrue(app.buttons["Vale"].waitForExistence(timeout: 12))

        let cardOpen = element("card-open-subscriptionPriceChange")
        scrollInBriefingSheet(to: cardOpen)
        XCTAssertTrue(cardOpen.waitForExistence(timeout: 8), "U34: falta card-open-subscriptionPriceChange")
        cardOpen.tap()

        XCTAssertTrue(
            app.staticTexts["Spotify"].waitForExistence(timeout: 10),
            "U34: tocar la cabecera de la tarjeta no abrió el detalle de Spotify"
        )
    }

    /// U34 #6: preguntar por inversiones y tocar `answer-line-inv-value` cierra la hoja y enseña Apple.
    func testAnswerLineActionOpensInvestments() throws {
        launch(["-MiBancoDemoBriefing", "busy"])
        XCTAssertTrue(app.buttons["Vale"].waitForExistence(timeout: 12))

        let field = element("assistant-question-field")
        scrollInBriefingSheet(to: field)
        field.tap()
        field.typeText("¿Cómo van mis inversiones?")
        element("assistant-send").tap()

        let invLine = element("answer-line-inv-value")
        scrollInBriefingSheet(to: invLine)
        XCTAssertTrue(invLine.waitForExistence(timeout: 8), "U34: falta answer-line-inv-value")
        invLine.tap()

        XCTAssertTrue(waitFor(NSPredicate(format: "exists == false"), element("briefing-done"), timeout: 8), "U34: no se cerró el resumen")
        let apple = app.buttons["Apple"]
        scrollTo(apple)
        XCTAssertTrue(apple.waitForExistence(timeout: 10), "U34: no se abrió Cartera con Apple")
    }

    /// U35 #1: el resumen nunca aparece encima del bloqueo; aparece tras desbloquear.
    func testBriefingNeverAboveLock() throws {
        // `-MiBancoDemoLockSeconds 12` (DEBUG): el bloqueo de demo dura 12 s, no 4: el arranque de la prueba ya gasta ~9 s.
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "12", "-MiBancoDemoBriefing", "quiet"])

        let unlock = app.buttons["Desbloquear"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 8), "U35: falta la pantalla de bloqueo")
        // U78 (U35 #1, B-M4): se mira MIENTRAS dure el bloqueo, no una sola vez al verlo.
        var lockChecks = 0
        while unlock.exists {
            XCTAssertFalse(element("briefing-done").exists, "U35: el resumen subió encima del bloqueo")
            lockChecks += 1
            if lockChecks > 80 { break }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertGreaterThan(lockChecks, 0, "U35: no se llegó a mirar con el bloqueo delante")

        XCTAssertTrue(element("briefing-done").waitForExistence(timeout: 16), "U35: el resumen no apareció tras desbloquear")
    }

    /// U35 #2: «Escuchar» se para al pasar a segundo plano y vuelve a decir «Escuchar» al volver.
    func testListenStopsOnBackground() throws {
        launch(["-MiBancoDemoBriefing", "busy"])
        XCTAssertTrue(app.buttons["Vale"].waitForExistence(timeout: 12))

        let listen = app.buttons["Escuchar"]
        XCTAssertTrue(listen.waitForExistence(timeout: 8))
        listen.tap()
        XCTAssertTrue(app.buttons["Parar"].waitForExistence(timeout: 6), "U35: no cambió a Parar")

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1.0)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))

        XCTAssertTrue(listen.waitForExistence(timeout: 8), "U35: la voz no se paró al salir a segundo plano")
    }

    /// U35 #4: apagar «Cambios en suscripciones» en Ajustes › Asistente oculta su tarjeta al abrir «Tu resumen».
    func testAssistantTopicSwitchHidesCards() throws {
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoAssistantSettings"])
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 15))

        let subTopic = element("assistant-topic-subscriptionPriceChange")
        scrollTo(subTopic)
        XCTAssertTrue(subTopic.waitForExistence(timeout: 10))
        subTopic.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "value == '0'"), subTopic, timeout: 6))

        app.tabBars.buttons["Inicio"].tap()
        let openBriefing = app.buttons["Tu resumen"]
        XCTAssertTrue(openBriefing.waitForExistence(timeout: 8))
        openBriefing.tap()
        XCTAssertTrue(app.buttons["Vale"].waitForExistence(timeout: 8))

        XCTAssertFalse(element("card-dislike-subscriptionPriceChange").exists, "U35: la tarjeta apareció con su tema apagado")
    }

    /// U37: entrar por la ruta del aviso de la mañana abre el resumen aunque hoy ya se hubiera visto.
    func testBriefingRouteOpensEvenIfSeen() throws {
        launch(["-MiBancoDemoRoute", "briefing"])
        XCTAssertTrue(element("briefing-done").waitForExistence(timeout: 12), "U37: la ruta del aviso de la mañana no abrió el resumen")
    }

    /// U82 (I2): se entra por el aviso con el resumen de hoy SIN ver; tras «Vale», volver a la app no lo abre otra vez.
    func testBriefingRouteDoesNotReopenAfterDone() throws {
        launch(["-MiBancoDemoBriefing", "quiet", "-MiBancoDemoRoute", "briefing", "-MiBancoDemoRouteUnseen"])
        let done = element("briefing-done")
        XCTAssertTrue(done.waitForExistence(timeout: 12), "U82: la ruta del aviso no abrió el resumen pendiente")
        done.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "exists == false"), done, timeout: 8), "U82: «Vale» no cerró el resumen")

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        app.activate()
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 10), "U82: no se volvió a Inicio")
        let end = Date().addingTimeInterval(6)
        while Date() < end {
            XCTAssertFalse(done.exists, "U82: el resumen volvió a salir tras verlo desde el aviso")
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    /// U89: tras «Mis inversiones», la primera línea de la respuesta es un dato y la nota va al final, como pie.
    func testInvestmentsAnswerShowsDataFirstAndNoteLast() throws {
        launch(["-MiBancoDemoBriefing", "busy"])
        XCTAssertTrue(app.buttons["Vale"].waitForExistence(timeout: 12))

        let field = element("assistant-question-field")
        scrollInBriefingSheet(to: field)
        field.tap()
        field.typeText("Mis inversiones")
        element("assistant-send").tap()

        let card = element("assistant-answer-card")
        scrollInBriefingSheet(to: card)
        XCTAssertTrue(card.waitForExistence(timeout: 8), "U89: falta la respuesta")
        let firstLine = card.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'answer-line-'")).firstMatch
        XCTAssertTrue(firstLine.waitForExistence(timeout: 8), "U89: la respuesta no tiene líneas")
        XCTAssertNotEqual(firstLine.identifier, "answer-line-inv-data-only", "U89: la nota va delante")
        XCTAssertFalse(firstLine.label.contains("Son datos, no una recomendación."), "U89: la primera línea es la nota")

        let note = card.descendants(matching: .any).matching(identifier: "answer-note-inv-data-only").firstMatch
        scrollInBriefingSheet(to: note)
        XCTAssertTrue(note.waitForExistence(timeout: 5), "U89: falta la nota «Son datos, no una recomendación.»")
        XCTAssertEqual(note.label, "Son datos, no una recomendación.")
        XCTAssertGreaterThan(note.frame.minY, firstLine.frame.minY, "U89: la nota no va detrás del dato")
    }

    /// U39: si falla guardar preferencias, «No me interesa» conserva la tarjeta en pantalla.
    func testDislikeKeepsCardWhenSaveFails() throws {
        launch(["-MiBancoDemoBriefing", "busy", "-MiBancoDemoPrefsFail"])
        XCTAssertTrue(app.buttons["Vale"].waitForExistence(timeout: 12))

        let subDislike = element("card-dislike-subscriptionPriceChange")
        scrollInBriefingSheet(to: subDislike)
        XCTAssertTrue(subDislike.waitForExistence(timeout: 8))
        subDislike.tap()
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertTrue(subDislike.exists, "U39: la tarjeta desapareció aunque falló el guardado de preferencias")
    }
}
