import XCTest

/// Recorrido pensado para GRABARLO en vídeo (workflow `motion-video`): no comprueba comportamiento, solo recorre la app
/// con pausas para que cada animación se vea. Aserciones mínimas (que el elemento exista); lo único que debe pasar es no romper.
/// Solo `-MiBancoDemo`: la demo no desactiva el telón de arranque ni ningún movimiento (el telón, el montaje por capas,
/// las cifras que cuentan y el carrusel dependen solo de Reducir movimiento, que el simulador trae apagado).
/// El recorrido va a tiempo real (escala 1) para que el vídeo enseñe la velocidad de verdad; las ráfagas, a cámara lenta.
final class MotionTourTests: MotionTourCase {

    /// Pausa entre pasos, para que se vea cada animación en el vídeo.
    private func beat(_ seconds: TimeInterval = 1.2) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func hasKeyboardFocus(_ el: XCUIElement) -> Bool {
        (el.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }

    /// El carrusel es un único elemento de accesibilidad cuya etiqueta acaba en "N de 4".
    private func carousel() -> XCUIElement {
        let predicate = NSPredicate(format: "label MATCHES %@", ".* [0-9] de 4$")
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    /// Ráfaga de prueba de la tubería: en la galería de movimiento, un ingreso hace rodar las cifras del importe grande.
    /// A ×4 la cuenta dura varios segundos: 16 fotogramas cada 0,4 s la enseñan a medias en varios de ellos.
    func testGalleryBurst() throws {
        launch(["-MiBancoMotionGallery", "-MiBancoMotionGalleryPage", "cifras"])
        XCTAssertTrue(app.staticTexts["gallery.title"].waitForExistence(timeout: 15), "La galería no aparece")
        let income = app.buttons["gallery.income"]
        XCTAssertTrue(income.waitForExistence(timeout: 10), "No aparece el botón Ingreso")
        let deadline = Date().addingTimeInterval(10)
        while !income.isHittable, Date() < deadline { Thread.sleep(forTimeInterval: 0.25) }
        XCTAssertTrue(income.isHittable, "El botón Ingreso no se puede tocar")
        income.tap()
        burst("gallery-burst", frames: 16, every: 0.4)
    }

    func testTour() throws {
        launch(scale: 1)
        // Lo que se ve de la llegada: el vídeo lo graba entero; aquí solo se espera.
        beat(3)

        let card = carousel()
        XCTAssertTrue(card.waitForExistence(timeout: 10), "No aparece el carrusel de tarjetas")

        // Carrusel: tres a la izquierda, una a la derecha.
        for _ in 0..<3 {
            card.swipeLeft()
            beat()
        }
        card.swipeRight()
        beat()

        // Volteo de la tarjeta visible y vuelta.
        card.tap()
        beat(1.6)
        card.tap()
        beat(1.6)

        // El ojo, dos veces (oculta y muestra).
        let hide = app.buttons["Ocultar importes"]
        XCTAssertTrue(hide.waitForExistence(timeout: 5))
        hide.tap()
        beat()
        let show = app.buttons["Mostrar importes"]
        XCTAssertTrue(show.waitForExistence(timeout: 5))
        show.tap()
        beat()

        // Búsqueda: abrir, escribir "a", cancelar.
        let search = app.buttons["Buscar movimientos"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        beat()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "No apareció el campo de búsqueda")
        let deadline = Date().addingTimeInterval(5)
        while !hasKeyboardFocus(field), Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        field.typeText("a")
        beat()
        let cancel = app.buttons["Cancelar"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        beat()

        // Primera fila: hoja de detalle, dos segundos, y se cierra.
        let row = app.buttons.matching(identifier: "movementRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "No hay filas de movimientos")
        row.tap()
        let close = app.buttons["Cerrar"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "No se abrió la hoja de detalle")
        beat(2)
        close.tap()
        beat()

        // Pestañas.
        let tabs = app.tabBars.buttons
        for name in ["Avisos", "Ajustes", "Inicio"] {
            XCTAssertTrue(tabs[name].waitForExistence(timeout: 5), "Falta la pestaña \(name)")
            tabs[name].tap()
            beat()
        }

        // Inicio hacia abajo y de vuelta arriba.
        let list = app.buttons.matching(identifier: "movementRow").firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        for _ in 0..<2 {
            app.swipeUp()
            beat()
        }
        for _ in 0..<2 {
            app.swipeDown()
            beat()
        }
        beat(2)
    }
}
