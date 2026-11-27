import XCTest

/// Pruebas de interfaz de Nyx Fase 2 — N14 (accesibilidad VoiceOver con ojo cerrado y tamaño de letra AX-XXXL).
final class NyxAccessibilityUITests: XCTestCase {
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
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func waitUntil(_ timeout: TimeInterval = 12, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.15)
        }
        return condition()
    }

    private func isClearlyVisible(_ target: XCUIElement) -> Bool {
        guard target.exists, target.isHittable else { return false }
        let frame = target.frame
        guard !frame.isEmpty else { return false }
        let done = app.buttons["briefing-done"]
        let bottomLimit = (done.exists && !done.frame.isEmpty) ? done.frame.minY - 16 : app.windows.firstMatch.frame.height - 140
        return frame.minY > 100 && frame.maxY < bottomLimit
    }

    private func scrollTo(_ target: XCUIElement, in container: XCUIElement? = nil, swipes: Int = 10) {
        let scroller: XCUIElement = container ?? (app.scrollViews["briefing-scroll"].exists ? app.scrollViews["briefing-scroll"] : app.scrollViews.firstMatch)
        for _ in 0..<swipes {
            if isClearlyVisible(target) { return }
            if target.exists && !target.frame.isEmpty && target.frame.minY <= 100 {
                scroller.swipeDown()
            } else {
                scroller.swipeUp()
            }
        }
        for _ in 0..<swipes {
            if isClearlyVisible(target) { return }
            scroller.swipeDown()
        }
    }

    private func assertNoDigits(_ text: String, context: String) {
        XCTAssertFalse(text.contains(where: \.isNumber), "\(context) contiene dígitos con el ojo cerrado: \(text)")
        XCTAssertFalse(text.contains("€"), "\(context) contiene € con el ojo cerrado: \(text)")
        XCTAssertFalse(text.contains("%"), "\(context) contiene % con el ojo cerrado: \(text)")
    }

    private func assertNoCurrencyDigits(_ text: String, context: String) {
        XCTAssertFalse(text.contains("€"), "\(context) contiene € con el ojo cerrado: \(text)")
        XCTAssertFalse(text.contains("%"), "\(context) contiene % con el ojo cerrado: \(text)")
        let hasDigitNextToEuro = text.range(of: "[0-9][0-9.,]*\\s*(?:€|euros|%)", options: [.regularExpression, .caseInsensitive]) != nil
        XCTAssertFalse(hasDigitNextToEuro, "\(context) expone cifras junto a €/% con el ojo cerrado: \(text)")
    }

    /// N14: con el ojo cerrado, ninguna etiqueta de VoiceOver en el resumen de la mañana, la hoja de Nyx ni el aviso
    /// lleva cifras ni símbolos de dinero (y ningún elemento `nyx-*` lleva dígito alguno).
    func testVoiceOverNoLeeCifrasConElOjoCerradoEnNyx() throws {
        // 1. Resumen de la mañana + hoja de Nyx («Para tener en cuenta», contador y «Lo que he visto») en privado.
        launch(["-MiBancoDemoBriefing", "busy", "-MiBancoDemoNyx", "seen-list", "-MiBancoDemoPrivate"])
        let title = element("nyx-sheet-title")
        XCTAssertTrue(title.waitForExistence(timeout: 20), "No se abrió la hoja de Nyx en modo privado")
        XCTAssertEqual(title.label, "Nyx", "El título de la hoja del asistente debe ser Nyx")

        let debugProbeIDs: Set<String> = ["briefing-drawn-line", "briefing-entrance", "nyx-spoken-text", "nyx-engine-probe"]
        let all = app.descendants(matching: .any)
        var checkedNyx = 0
        var checkedBriefing = 0
        for i in 0..<all.count {
            let el = all.element(boundBy: i)
            let id = el.identifier
            guard !id.isEmpty, !debugProbeIDs.contains(id) else { continue }
            let label = el.label
            if id.hasPrefix("nyx-") {
                checkedNyx += 1
                if !label.isEmpty {
                    assertNoDigits(label, context: "Etiqueta \(id)")
                }
            } else if id.hasPrefix("briefing-") {
                checkedBriefing += 1
                if !label.isEmpty {
                    assertNoCurrencyDigits(label, context: "Etiqueta \(id)")
                }
            }
        }
        XCTAssertGreaterThan(checkedNyx, 0, "No se inspeccionó ningún elemento nyx-*")
        XCTAssertGreaterThan(checkedBriefing, 0, "No se inspeccionó ningún elemento briefing-*")

        // Comprobar también que el botón flotante tras cerrar la hoja no expone dígitos en su valor.
        app.buttons["briefing-close"].tap()
        let nyxButton = app.buttons["nyx-button"]
        XCTAssertTrue(nyxButton.waitForExistence(timeout: 10), "Falta nyx-button tras cerrar la hoja")
        XCTAssertEqual(nyxButton.label, "Nyx")
        if let val = nyxButton.value as? String, !val.isEmpty {
            assertNoDigits(val, context: "Valor de nyx-button")
        }

        // 2. Aviso de Nyx dentro de la app con el ojo cerrado: cero dígitos en todos sus elementos.
        app.terminate()
        launch(["-MiBancoDemoNyx", "banner", "-MiBancoDemoPrivate", "-MiBancoMotionScale", "2"])
        let banner = element("nyx-banner")
        XCTAssertTrue(banner.waitForExistence(timeout: 20), "No apareció nyx-banner en privado")
        let bannerChildren = banner.descendants(matching: .any)
        var checkedBanner = 0
        for i in 0..<bannerChildren.count {
            let child = bannerChildren.element(boundBy: i)
            let label = child.label
            if !label.isEmpty {
                checkedBanner += 1
                assertNoDigits(label, context: "Aviso \(child.identifier)")
            }
        }
        XCTAssertGreaterThan(checkedBanner, 0, "No se inspeccionó ningún texto dentro de nyx-banner")
    }

    /// N14: en tamaño de letra de accesibilidad máximo (AX-XXXL), `nyx-button` mantiene su tamaño y es tocable,
    /// el botón «Escuchar» del foco pasa debajo del título sin recorte horizontal y las acciones de los mensajes
    /// son tocables sin salirse de la pantalla.
    func testTamanoDeLetraDeAccesibilidad() throws {
        let axArgs = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

        // 1. Puesta al día con foco en AX-XXXL: botón «Escuchar» debajo del título y sin recorte horizontal.
        launch(["-MiBancoDemoBriefing", "busy", "-MiBancoDemoNyx", "daily-focus"] + axArgs)
        XCTAssertTrue(element("nyx-sheet-title").waitForExistence(timeout: 20), "No se abrió la hoja de Nyx en AX-XXXL")
        let windowFrame = app.windows.firstMatch.frame

        let focusListen = app.buttons["nyx-listen-focus"]
        scrollTo(focusListen)
        XCTAssertTrue(focusListen.waitForExistence(timeout: 8), "Falta nyx-listen-focus en AX-XXXL")
        XCTAssertTrue(focusListen.isHittable, "nyx-listen-focus no es tocable en AX-XXXL")
        XCTAssertLessThanOrEqual(focusListen.frame.maxX, windowFrame.maxX + 1, "nyx-listen-focus se recorta por la derecha en AX-XXXL")
        XCTAssertGreaterThanOrEqual(focusListen.frame.minX, windowFrame.minX - 1, "nyx-listen-focus se recorta por la izquierda en AX-XXXL")

        let focusTitle = element("nyx-focus").staticTexts["Un cobro que no cabe"]
        XCTAssertTrue(focusTitle.waitForExistence(timeout: 6), "Falta el título del foco en AX-XXXL")
        XCTAssertGreaterThanOrEqual(
            focusListen.frame.minY,
            focusTitle.frame.maxY - 4,
            "En AX-XXXL nyx-listen-focus debería apilarse debajo del título para no apretarlo (título: \(focusTitle.frame), botón: \(focusListen.frame))"
        )

        // Cerrar la hoja y verificar que nyx-button conserva 52 pt y es tocable sin recorte.
        app.buttons["briefing-close"].tap()
        let nyxButton = app.buttons["nyx-button"]
        XCTAssertTrue(nyxButton.waitForExistence(timeout: 10), "Falta nyx-button en AX-XXXL")
        XCTAssertTrue(nyxButton.isHittable, "nyx-button no es tocable en AX-XXXL")
        XCTAssertGreaterThanOrEqual(nyxButton.frame.width, 44, "nyx-button mide menos de 44 pt en AX-XXXL")
        XCTAssertLessThanOrEqual(nyxButton.frame.width, 64, "nyx-button creció por encima de 52 pt en AX-XXXL")
        XCTAssertLessThanOrEqual(nyxButton.frame.maxX, windowFrame.maxX + 1, "nyx-button se sale de la pantalla en AX-XXXL")

        // 2. Lista «Lo que he visto» en AX-XXXL: los botones de acción y Descartar son tocables sin recorte horizontal.
        app.terminate()
        launch(["-MiBancoDemoNyx", "seen-list"] + axArgs)
        let nyxBtn2 = app.buttons["nyx-button"]
        XCTAssertTrue(nyxBtn2.waitForExistence(timeout: 20), "Falta nyx-button en seen-list AX-XXXL")
        nyxBtn2.tap()
        XCTAssertTrue(element("nyx-sheet-title").waitForExistence(timeout: 8), "No se abrió la hoja de Nyx en seen-list AX-XXXL")

        let win2 = app.windows.firstMatch.frame
        let firstAction = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'nyx-action-'")).firstMatch
        scrollTo(firstAction)
        XCTAssertTrue(firstAction.waitForExistence(timeout: 8), "Falta un botón nyx-action-* en AX-XXXL")
        XCTAssertTrue(firstAction.isHittable, "nyx-action-* no es tocable en AX-XXXL")
        XCTAssertLessThanOrEqual(firstAction.frame.maxX, win2.maxX + 1, "nyx-action-* se recorta horizontalmente en AX-XXXL")
        XCTAssertGreaterThanOrEqual(firstAction.frame.minX, win2.minX - 1, "nyx-action-* se sale por la izquierda en AX-XXXL")

        let firstDismiss = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'nyx-dismiss-'")).firstMatch
        scrollTo(firstDismiss)
        XCTAssertTrue(firstDismiss.waitForExistence(timeout: 8), "Falta nyx-dismiss-* en AX-XXXL")
        XCTAssertTrue(firstDismiss.isHittable, "nyx-dismiss-* no es tocable en AX-XXXL")
        XCTAssertLessThanOrEqual(firstDismiss.frame.maxX, win2.maxX + 1, "nyx-dismiss-* se recorta horizontalmente en AX-XXXL")
    }
}
