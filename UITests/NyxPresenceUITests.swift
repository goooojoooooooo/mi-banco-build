import XCTest

/// Pruebas de interfaz de Nyx Fase 2 — N10 (botón flotante de presencia de Nyx y aviso dentro de la app).
final class NyxPresenceUITests: XCTestCase {
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

    private func waitFor(_ predicate: NSPredicate, _ object: Any, timeout: TimeInterval) -> Bool {
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: object)
        return XCTWaiter().wait(for: [exp], timeout: timeout) == .completed
    }

    private func assertNyxButtonClearOfTabBar(tabName: String) {
        let nyx = app.buttons["nyx-button"]
        XCTAssertTrue(nyx.waitForExistence(timeout: 12), "Falta nyx-button en \(tabName)")
        XCTAssertTrue(nyx.isHittable, "nyx-button no es tocable en \(tabName)")
        let nyxFrame = nyx.frame
        XCTAssertGreaterThanOrEqual(nyxFrame.width, 44, "nyx-button mide menos de 44 pt de ancho en \(tabName)")
        XCTAssertGreaterThanOrEqual(nyxFrame.height, 44, "nyx-button mide menos de 44 pt de alto en \(tabName)")

        let tabBarButtons = app.tabBars.firstMatch.buttons
        for i in 0..<tabBarButtons.count {
            let tb = tabBarButtons.element(boundBy: i)
            guard tb.exists, !tb.frame.isEmpty else { continue }
            XCTAssertFalse(
                nyxFrame.intersects(tb.frame),
                "nyx-button (\(nyxFrame)) se solapa con la pestaña \(tb.label) (\(tb.frame)) en \(tabName)"
            )
        }
    }

    /// N10: el botón de Nyx aparece en las cuatro pestañas, es tocable y nunca se solapa con la barra de pestañas.
    func testElBotonEstaEnLasCuatroPestanas() throws {
        launch()
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 20), "No cargó Inicio")
        assertNyxButtonClearOfTabBar(tabName: "Inicio")

        for tabName in ["Gasto", "Avisos", "Ajustes", "Inicio"] {
            let tab = app.tabBars.buttons[tabName]
            XCTAssertTrue(tab.waitForExistence(timeout: 6), "Falta la pestaña \(tabName)")
            tab.tap()
            assertNyxButtonClearOfTabBar(tabName: tabName)
        }
    }

    /// N10: tocar el botón flotante abre la hoja de Nyx en «Pregúntame» (`assistant-question-field`).
    func testElBotonAbreLaHojaEnPreguntame() throws {
        launch()
        let nyx = app.buttons["nyx-button"]
        XCTAssertTrue(nyx.waitForExistence(timeout: 20), "Falta nyx-button")
        nyx.tap()

        XCTAssertTrue(element("nyx-sheet-title").waitForExistence(timeout: 8), "No se abrió la hoja de Nyx")
        XCTAssertTrue(element("assistant-question-field").waitForExistence(timeout: 8),
                      "La hoja abierta desde nyx-button no muestra el campo Pregúntame")
        // Con la hoja abierta el botón flotante se oculta.
        XCTAssertFalse(nyx.exists && nyx.isHittable, "nyx-button no puede seguir tocable con la hoja abierta")
    }

    /// N10: el botón no aparece con el bloqueo delante ni dentro de los pasos de la guía de avisos.
    func testElBotonNoSaleEnLaGuiaNiConElBloqueo() throws {
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "6"])
        let nyx = app.buttons["nyx-button"]
        let unlock = app.buttons["Desbloquear"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 8), "No apareció la pantalla de bloqueo")
        XCTAssertFalse(nyx.exists && nyx.isHittable, "nyx-button no puede aparecer con el bloqueo delante")
        XCTAssertTrue(waitFor(NSPredicate(format: "exists == false"), unlock, timeout: 20), "El bloqueo de demo no se quitó")
        XCTAssertTrue(nyx.waitForExistence(timeout: 10), "Tras desbloquear debe aparecer nyx-button")

        app.terminate()

        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoAlertsGuide", "rev", "1"])
        XCTAssertTrue(app.buttons["guide-next"].waitForExistence(timeout: 20), "No se abrió la guía de avisos")
        XCTAssertFalse(nyx.exists && nyx.isHittable, "nyx-button no debe aparecer en los pasos de la guía")
    }

    /// N10: el aviso de Nyx dentro de la app (`nyx-banner`) se toca y abre la hoja en su mensaje.
    func testElAvisoDeNyxSeTocaYAbreSuMensaje() throws {
        launch(["-MiBancoDemoNyx", "banner", "-MiBancoMotionScale", "2"])
        let banner = element("nyx-banner")
        XCTAssertTrue(banner.waitForExistence(timeout: 20), "No apareció nyx-banner")

        let openBtn = element("nyx-banner-open")
        XCTAssertTrue(openBtn.waitForExistence(timeout: 6), "Falta el botón principal del banner de Nyx")
        openBtn.tap()

        XCTAssertTrue(element("nyx-sheet-title").waitForExistence(timeout: 8), "Tocar nyx-banner no abrió la hoja de Nyx")
        XCTAssertTrue(element("nyx-seen-list").waitForExistence(timeout: 8), "Falta «Lo que he visto» tras tocar el banner")
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'nyx-message-shortfall|'"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "No se mostró el mensaje del aviso tocado")
    }

    /// N10: el aviso de Nyx dentro de la app se descarta deslizándolo hacia arriba.
    func testElAvisoDeNyxSeDescartaDeslizando() throws {
        launch(["-MiBancoDemoNyx", "banner"])
        let banner = element("nyx-banner")
        XCTAssertTrue(banner.waitForExistence(timeout: 20), "No apareció nyx-banner")

        banner.swipeUp()
        XCTAssertTrue(waitFor(NSPredicate(format: "exists == false"), banner, timeout: 4),
                      "Deslizar hacia arriba no descartó nyx-banner")
    }

    /// N10 (privacidad ojo cerrado): con el ojo cerrado el aviso dentro de la app no expone ningún dígito, «€» ni «%».
    func testElAvisoDeNyxConOjoCerradoNoLlevaCifras() throws {
        launch(["-MiBancoDemoNyx", "banner", "-MiBancoDemoPrivate"])
        let banner = element("nyx-banner")
        XCTAssertTrue(banner.waitForExistence(timeout: 20), "No apareció nyx-banner en modo privado")

        let lbl = banner.label
        XCTAssertFalse(lbl.contains(where: \.isNumber), "nyx-banner expone dígitos con ojo cerrado: \(lbl)")
        XCTAssertFalse(lbl.contains("€"), "nyx-banner expone € con ojo cerrado: \(lbl)")
        XCTAssertFalse(lbl.contains("%"), "nyx-banner expone % con ojo cerrado: \(lbl)")
        let children = banner.descendants(matching: .any)
        XCTAssertGreaterThan(children.count, 0, "nyx-banner debe exponer sus elementos internos")
        for i in 0..<children.count {
            let child = children.element(boundBy: i)
            let cLbl = child.label
            XCTAssertFalse(cLbl.contains(where: \.isNumber), "Elemento del banner expone dígitos con ojo cerrado: \(cLbl)")
            XCTAssertFalse(cLbl.contains("€"), "Elemento del banner expone € con ojo cerrado: \(cLbl)")
            XCTAssertFalse(cLbl.contains("%"), "Elemento del banner expone % con ojo cerrado: \(cLbl)")
        }
    }
}
