import XCTest

/// Pruebas de interfaz de Nyx Fase 2 — N13 (Ajustes › Nyx: «Cuánto te hablo», «Leerte la puesta al día…» y «Olvidar»).
final class NyxSettingsUITests: XCTestCase {
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
        let windowHeight = app.windows.firstMatch.frame.height
        return frame.minY > 110 && frame.maxY < windowHeight - 150
    }

    private func scrollTo(_ target: XCUIElement, in container: XCUIElement? = nil, swipes: Int = 10) {
        let scroller: XCUIElement = container ?? (app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.scrollViews.firstMatch)
        for _ in 0..<swipes {
            if isClearlyVisible(target) { return }
            if target.exists && !target.frame.isEmpty && target.frame.minY <= 110 {
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

    /// N13: elegir «Solo lo urgente» en Ajustes › Nyx se guarda y se mantiene al relanzar la app.
    func testElegirSoloLoUrgenteSeGuarda() throws {
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoPersistNyx", "-MiBancoDemoNyxReset"])
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 20), "Ajustes no apareció")

        let urgent = app.buttons["nyx-talk-urgentOnly"]
        scrollTo(urgent)
        XCTAssertTrue(urgent.waitForExistence(timeout: 8), "Falta la opción nyx-talk-urgentOnly")

        let whenItMatters = app.buttons["nyx-talk-whenItMatters"]
        XCTAssertTrue(whenItMatters.isSelected, "«Cuando importe» debe empezar seleccionada por defecto")

        urgent.tap()
        XCTAssertTrue(waitUntil(6) { urgent.exists && urgent.isSelected }, "«Solo lo urgente» no quedó seleccionada")

        app.terminate()
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoPersistNyx"])
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 20), "Ajustes no apareció al relanzar")

        let urgentAfter = app.buttons["nyx-talk-urgentOnly"]
        scrollTo(urgentAfter)
        XCTAssertTrue(urgentAfter.waitForExistence(timeout: 8), "Falta nyx-talk-urgentOnly tras relanzar")
        XCTAssertTrue(urgentAfter.isSelected, "«Solo lo urgente» no se conservó tras relanzar")
    }

    /// N13: activar «Leerte la puesta al día al abrir si llevas auriculares» se guarda y se mantiene al relanzar.
    func testLeerConAuricularesSeGuarda() throws {
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoPersistNyx", "-MiBancoDemoNyxReset"])
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 20), "Ajustes no apareció")

        let toggle = app.switches["nyx-read-aloud"]
        scrollTo(toggle)
        XCTAssertTrue(toggle.waitForExistence(timeout: 8), "Falta el interruptor nyx-read-aloud")
        XCTAssertEqual(toggle.value as? String, "0", "«Leerte la puesta al día…» debe empezar apagado")

        toggle.tap()
        XCTAssertTrue(waitUntil(6) { (toggle.value as? String) == "1" }, "nyx-read-aloud no se encendió")

        app.terminate()
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoPersistNyx"])
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 20), "Ajustes no apareció al relanzar")

        let toggleAfter = app.switches["nyx-read-aloud"]
        scrollTo(toggleAfter)
        XCTAssertTrue(toggleAfter.waitForExistence(timeout: 8), "Falta nyx-read-aloud tras relanzar")
        XCTAssertEqual(toggleAfter.value as? String, "1", "nyx-read-aloud no se conservó encendido tras relanzar")
    }

    /// N13: «Olvidar lo que he aprendido» pide confirmación en la hoja única; cancelar conserva la lista y confirmar la vacía.
    func testOlvidarVaciaLaLista() throws {
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoNyx", "seen-list"])
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 20), "Ajustes no apareció")

        // 1. Abrir la hoja de Nyx y comprobar que «Lo que he visto» tiene elementos (no está vacía).
        let nyxButton = app.buttons["nyx-button"]
        XCTAssertTrue(nyxButton.waitForExistence(timeout: 12), "Falta nyx-button en Ajustes")
        nyxButton.tap()
        XCTAssertTrue(element("nyx-sheet-title").waitForExistence(timeout: 8), "No se abrió la hoja de Nyx")
        XCTAssertFalse(element("nyx-seen-empty").exists, "La lista no debería estar vacía antes de olvidar")
        app.buttons["briefing-close"].tap()
        XCTAssertTrue(waitUntil(8) { !app.buttons["briefing-close"].exists }, "No se cerró la hoja de Nyx")

        // 2. Tocar «Olvidar lo que he aprendido» y cancelar: la lista se conserva.
        let forget = app.buttons["nyx-forget"]
        scrollTo(forget)
        XCTAssertTrue(forget.waitForExistence(timeout: 8), "Falta el botón nyx-forget")
        forget.tap()

        let cancel = app.buttons["nyx-forget-cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 8), "Falta nyx-forget-cancel en la confirmación")
        XCTAssertTrue(app.buttons["nyx-forget-confirm"].exists, "Falta nyx-forget-confirm en la confirmación")
        cancel.tap()
        XCTAssertTrue(waitUntil(8) { !cancel.exists }, "No se cerró la confirmación al cancelar")

        nyxButton.tap()
        XCTAssertTrue(element("nyx-sheet-title").waitForExistence(timeout: 8), "No se reabrió la hoja de Nyx tras cancelar")
        XCTAssertFalse(element("nyx-seen-empty").exists, "Cancelar no debería haber vaciado la lista")
        app.buttons["briefing-close"].tap()
        XCTAssertTrue(waitUntil(8) { !app.buttons["briefing-close"].exists })

        // 3. Tocar «Olvidar lo que he aprendido» y confirmar: la lista queda vacía con su frase exacta.
        scrollTo(forget)
        forget.tap()
        let confirm = app.buttons["nyx-forget-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 8), "Falta nyx-forget-confirm")
        confirm.tap()
        XCTAssertTrue(waitUntil(8) { !confirm.exists }, "No se cerró la confirmación al confirmar")

        nyxButton.tap()
        XCTAssertTrue(element("nyx-sheet-title").waitForExistence(timeout: 8), "No se reabrió la hoja de Nyx tras olvidar")
        let sheetScroll = app.scrollViews["briefing-scroll"].exists ? app.scrollViews["briefing-scroll"] : app.scrollViews.firstMatch
        let empty = element("nyx-seen-empty")
        scrollTo(empty, in: sheetScroll)
        XCTAssertTrue(empty.waitForExistence(timeout: 8), "Tras confirmar «Olvidar», la lista no muestra el mensaje vacío")
    }
}
