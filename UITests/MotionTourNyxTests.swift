import XCTest

/// Ráfagas visuales de Nyx Fase 2 (`motion-video -f tour_class=MotionTourNyxTests`):
/// - Puesta al día de Nyx (abierta y con ojo cerrado).
/// - Lista «Lo que he visto» (abierta y con ojo cerrado).
/// - Botón flotante de presencia (sin novedades y con punto de novedades).
/// - Aviso de Nyx dentro de la app (caída, ojo cerrado y Reducir movimiento).
/// - Voz de Nyx con `VoiceWave` (normal y con Reducir movimiento).
/// - Ajustes › Nyx (normal y con tamaño de letra de accesibilidad AX-XXXL).
final class MotionTourNyxTests: MotionTourCase {

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func scrollTo(_ target: XCUIElement, in container: XCUIElement? = nil, swipes: Int = 8) {
        let scroller: XCUIElement = container ?? (app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.scrollViews.firstMatch)
        for _ in 0..<swipes {
            if target.exists && target.isHittable { return }
            scroller.swipeUp()
        }
        for _ in 0..<swipes {
            if target.exists && target.isHittable { return }
            scroller.swipeDown()
        }
    }

    /// Hoja de puesta al día de Nyx con «Para tener en cuenta» (normal y ojo cerrado).
    func testNyxPuestaAlDia() throws {
        launch(["-MiBancoDemoBriefing", "busy", "-MiBancoDemoNyx", "daily-focus"], scale: 2)
        XCTAssertTrue(element("nyx-sheet-title").waitForExistence(timeout: 20), "Falta la hoja de Nyx")
        Thread.sleep(forTimeInterval: 1.5)
        burst("nyx-puesta-al-dia", frames: 4, every: 0.4)

        app.terminate()
        launch(["-MiBancoDemoBriefing", "busy", "-MiBancoDemoNyx", "daily-focus", "-MiBancoDemoPrivate"], scale: 2)
        XCTAssertTrue(element("nyx-sheet-title").waitForExistence(timeout: 20), "Falta la hoja de Nyx en privado")
        Thread.sleep(forTimeInterval: 1.5)
        burst("nyx-puesta-al-dia-ojo-cerrado", frames: 4, every: 0.4)
    }

    /// Lista «Lo que he visto» abierta desde el botón de Nyx (normal y ojo cerrado).
    func testNyxLista() throws {
        launch(["-MiBancoDemoNyx", "seen-list"], scale: 2)
        let nyx = app.buttons["nyx-button"]
        XCTAssertTrue(nyx.waitForExistence(timeout: 20), "Falta nyx-button")
        nyx.tap()
        XCTAssertTrue(element("nyx-sheet-title").waitForExistence(timeout: 10), "No se abrió la hoja de Nyx")
        Thread.sleep(forTimeInterval: 1.0)
        burst("nyx-lista", frames: 4, every: 0.4)

        app.terminate()
        launch(["-MiBancoDemoNyx", "seen-list", "-MiBancoDemoPrivate"], scale: 2)
        let nyxPrivate = app.buttons["nyx-button"]
        XCTAssertTrue(nyxPrivate.waitForExistence(timeout: 20), "Falta nyx-button en privado")
        nyxPrivate.tap()
        XCTAssertTrue(element("nyx-sheet-title").waitForExistence(timeout: 10), "No se abrió la hoja de Nyx en privado")
        Thread.sleep(forTimeInterval: 1.0)
        burst("nyx-lista-ojo-cerrado", frames: 4, every: 0.4)
    }

    /// Botón flotante de presencia en Inicio (en reposo y con punto de novedades).
    func testNyxBoton() throws {
        launch([], scale: 2)
        XCTAssertTrue(app.buttons["nyx-button"].waitForExistence(timeout: 20), "Falta nyx-button en Inicio")
        Thread.sleep(forTimeInterval: 1.0)
        burst("nyx-boton", frames: 3, every: 0.4)

        app.terminate()
        launch(["-MiBancoDemoNyx", "shortfall", "-MiBancoDemoPersistNyx", "-MiBancoDemoNyxReset"], scale: 2)
        XCTAssertTrue(app.buttons["nyx-button"].waitForExistence(timeout: 20), "Falta nyx-button con novedades")
        Thread.sleep(forTimeInterval: 1.2)
        burst("nyx-boton-punto", frames: 4, every: 0.4)
    }

    /// Aviso de Nyx dentro de la app: caída (muelle), ojo cerrado y Reducir movimiento (fundido sin recorrido).
    func testNyxAviso() throws {
        launch(["-MiBancoDemoNyx", "banner"], scale: 4)
        XCTAssertTrue(element("nyx-banner").waitForExistence(timeout: 20), "No apareció nyx-banner")
        burst("nyx-aviso-caida", frames: 6, every: 0.3)

        app.terminate()
        launch(["-MiBancoDemoNyx", "banner", "-MiBancoDemoPrivate"], scale: 4)
        XCTAssertTrue(element("nyx-banner").waitForExistence(timeout: 20), "No apareció nyx-banner en privado")
        burst("nyx-aviso-ojo-cerrado", frames: 4, every: 0.35)

        app.terminate()
        launch(["-MiBancoDemoNyx", "banner", "-MiBancoReduceMotion"], scale: 4)
        XCTAssertTrue(element("nyx-banner").waitForExistence(timeout: 20), "No apareció nyx-banner con Reducir movimiento")
        burst("nyx-aviso-reducir-movimiento", frames: 5, every: 0.3)
    }

    /// Voz de Nyx (`VoiceWave`): normal y con Reducir movimiento.
    func testNyxVoz() throws {
        launch(["-MiBancoDemoBriefing", "busy", "-MiBancoDemoNyx", "daily-focus"], scale: 2)
        let listen = app.buttons["briefing-listen"]
        XCTAssertTrue(listen.waitForExistence(timeout: 20), "Falta briefing-listen")
        listen.tap()
        burst("nyx-voz", frames: 6, every: 0.35)
        listen.tap()

        app.terminate()
        launch(["-MiBancoDemoBriefing", "busy", "-MiBancoDemoNyx", "daily-focus", "-MiBancoReduceMotion"], scale: 2)
        let listenRM = app.buttons["briefing-listen"]
        XCTAssertTrue(listenRM.waitForExistence(timeout: 20), "Falta briefing-listen con Reducir movimiento")
        listenRM.tap()
        burst("nyx-voz-reducir-movimiento", frames: 4, every: 0.35)
        listenRM.tap()
    }

    /// Ajustes › Nyx: tamaño normal y tamaño de accesibilidad AX-XXXL.
    func testNyxAjustes() throws {
        launch(["-MiBancoDemoScreen", "ajustes"], scale: 2)
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 20), "No cargó Ajustes")
        let talk = app.buttons["nyx-talk-whenItMatters"]
        scrollTo(talk)
        XCTAssertTrue(talk.waitForExistence(timeout: 8), "Falta la sección Nyx en Ajustes")
        burst("nyx-ajustes", frames: 3, every: 0.4)

        app.terminate()
        launch([
            "-MiBancoDemoScreen", "ajustes",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ], scale: 2)
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 20), "No cargó Ajustes en AX-XXXL")
        let talkAX = app.buttons["nyx-talk-whenItMatters"]
        scrollTo(talkAX)
        XCTAssertTrue(talkAX.waitForExistence(timeout: 8), "Falta la sección Nyx en Ajustes AX-XXXL")
        burst("nyx-ajustes-letra-grande", frames: 3, every: 0.4)
    }
}
