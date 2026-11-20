import XCTest

/// Toca todos los controles de la galería de movimiento (solo DEBUG, `-MiBancoMotionGallery`): comprueba que existen,
/// que responden y que nada se rompe. La galería enseña el kit de movimiento sin estar enlazado a las pantallas.
final class MotionGalleryTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-MiBancoDemo", "-MiBancoMotionGallery", "-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()
        XCTAssertTrue(app.staticTexts["gallery.title"].waitForExistence(timeout: 15), "La galería no aparece")
    }

    /// Baja hasta que el elemento se pueda tocar.
    private func reveal(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "No existe \(element)")
        var swipes = 0
        while !element.isHittable && swipes < 12 {
            app.swipeUp()
            swipes += 1
        }
    }

    private func tap(_ id: String) {
        let element = app.buttons[id]
        reveal(element)
        element.tap()
    }

    private func labelled(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", text)).firstMatch
    }

    func testEveryControlResponds() throws {
        // Intensidad: los tres niveles se pueden elegir.
        for level in ["Sutil", "Equilibrado", "Expresivo"] {
            let button = app.buttons[level]
            reveal(button)
            button.tap()
            XCTAssertTrue(button.isSelected, "\(level) no quedó seleccionado")
        }
        // Reducir movimiento y volver.
        let reduce = app.switches["gallery.reduce"].exists ? app.switches["gallery.reduce"] : app.descendants(matching: .any)["gallery.reduce"]
        reveal(reduce)
        reduce.tap()
        reduce.tap()

        tap("gallery.mark.replay")
        tap("gallery.pay")
        tap("gallery.income")
        tap("gallery.eye")
        tap("gallery.eye")
        tap("gallery.glass")
        tap("gallery.lift")
        tap("gallery.lift")
        tap("gallery.sheen")
        tap("gallery.burst")

        // Botón que se transforma: llega a «Enviado»; el que falla enseña su error.
        let ok = app.buttons["Probar aviso"]
        reveal(ok)
        ok.tap()
        XCTAssertTrue(app.buttons["Enviado"].waitForExistence(timeout: 5), "El botón no llegó a Enviado")
        let fail = app.buttons["Probar fallo"]
        reveal(fail)
        fail.tap()
        XCTAssertTrue(app.staticTexts["No se ha podido. Inténtalo otra vez."].waitForExistence(timeout: 5), "No salió el error")

        // Segmentado propio.
        for title in ["Semana", "Mes", "Hoy"] {
            let button = app.buttons[title]
            reveal(button)
            button.tap()
            XCTAssertTrue(button.isSelected, "\(title) no quedó seleccionado")
        }

        // Barra de presupuesto y pasos.
        XCTAssertTrue(app.descendants(matching: .any)["gallery.fill"].exists)
        tap("gallery.fill.up")
        tap("gallery.fill.down")
        for _ in 0..<4 { tap("gallery.step.next") }
        XCTAssertTrue(labelled("Paso 1: Autorizar").exists)
        tap("gallery.step.reset")
    }

    /// Con el ojo cerrado, ninguna cifra real está en pantalla ni en el árbol de accesibilidad.
    func testHiddenAmountNeverExposesDigits() throws {
        tap("gallery.eye")
        let money = NSPredicate(format: "label MATCHES %@", #".*[0-9]{1,3}(\.[0-9]{3})*,[0-9]{2}.*"#)
        for _ in 0..<8 {
            XCTAssertTrue(labelled("importe oculto").waitForExistence(timeout: 3))
            XCTAssertEqual(app.descendants(matching: .any).matching(money).count, 0, "Hay una cifra real con el ojo cerrado")
            Thread.sleep(forTimeInterval: 0.3)
        }
        tap("gallery.pay")
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertEqual(app.descendants(matching: .any).matching(money).count, 0, "Un pago con el ojo cerrado enseñó la cifra")
    }
}
