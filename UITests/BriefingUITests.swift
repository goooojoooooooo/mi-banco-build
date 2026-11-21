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

        let reopenButton = app.buttons["Tu resumen"]
        XCTAssertTrue(reopenButton.waitForExistence(timeout: 8), "Falta el botón «Tu resumen» en la barra de Inicio")
        reopenButton.tap()

        XCTAssertTrue(doneButton.waitForExistence(timeout: 8), "El resumen no se volvió a abrir desde «Tu resumen»")
    }

    /// Review Focus 3: con el modo privado activo, el contenido tapado («•••») aparece y ningún elemento expone «€» ni «%»,
    /// tampoco tras hacer una pregunta en «Pregúntame».
    func testBriefingPrivateHidesAmounts() throws {
        launch(["-MiBancoDemoBriefing", "busy", "-MiBancoDemoShortfall", "-MiBancoDemoPrivate"])

        let doneButton = app.buttons["Vale"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 12), "El resumen en modo privado no apareció")

        let sheet = app.scrollViews["briefing-scroll"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 8), "Falta el contenedor del resumen")

        let masked = sheet.staticTexts.matching(NSPredicate(format: "label CONTAINS '•••'")).firstMatch
        XCTAssertTrue(masked.waitForExistence(timeout: 8), "Las líneas tapadas («•••») del resumen no aparecieron")

        let euroElements = sheet.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '€'"))
        XCTAssertEqual(euroElements.count, 0, "El resumen expuso '€' en modo privado")

        let percentElements = sheet.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '%'"))
        XCTAssertEqual(percentElements.count, 0, "El resumen expuso '%' en modo privado")

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

        XCTAssertEqual(euroElements.count, 0, "La respuesta del asistente expuso '€' en modo privado")
        XCTAssertEqual(percentElements.count, 0, "La respuesta del asistente expuso '%' en modo privado")
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
            app.staticTexts["10,00\(nbsp)€"].waitForExistence(timeout: 8),
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
            waitFor(NSPredicate(format: "exists == false"), subDislike, timeout: 6),
            "La tarjeta descartada no desapareció al pulsar «No me interesa»"
        )

        let questionField = element("assistant-question-field")
        scrollInBriefingSheet(to: questionField)
        XCTAssertTrue(questionField.waitForExistence(timeout: 8), "Falta el campo «Pregúntame algo de tu dinero…»")
        questionField.tap()
        questionField.typeText("¿Debo comprar Apple?\n")
        let sendButton = element("assistant-send")
        if sendButton.exists && sendButton.isEnabled && sendButton.isHittable {
            sendButton.tap()
        }

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
}
