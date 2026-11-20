import XCTest

/// Toca todos los controles de la galería de movimiento (solo DEBUG, `-MiBancoMotionGallery`): cada toque se comprueba
/// con su efecto (valores, etiquetas, estados), no solo que el elemento exista. La galería enseña el kit de movimiento
/// sin estar enlazado a las pantallas.
final class MotionGalleryTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-MiBancoDemo", "-MiBancoMotionGallery", "-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()
        XCTAssertTrue(app.staticTexts["gallery.title"].waitForExistence(timeout: 15), "La galería no aparece")
    }

    // MARK: Ayudas

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

    private func any(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    private func labelled(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", text)).firstMatch
    }

    /// Espera (hasta 5 s) a que se cumpla la condición.
    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return condition()
    }

    /// La etiqueta del importe de la galería («3.774,75 euros» u «importe oculto»).
    private func amountLabel() -> String {
        let spoken = app.descendants(matching: .any).matching(NSPredicate(format: "label ENDSWITH %@", " euros")).firstMatch
        if spoken.exists { return spoken.label }
        return labelled("importe oculto").exists ? "importe oculto" : ""
    }

    private func stepValue(_ number: Int, _ title: String) -> String {
        (labelled("Paso \(number): \(title)").value as? String) ?? ""
    }

    private func reduceSwitch() -> XCUIElement {
        let byId = app.switches["gallery.reduce"]
        return byId.exists ? byId : app.switches["Reducir movimiento"]
    }

    private func moneyLabelCount() -> Int {
        let money = NSPredicate(format: "label MATCHES %@", #".*[0-9]{1,3}(\.[0-9]{3})*,[0-9]{2}.*"#)
        return app.descendants(matching: .any).matching(money).count
    }

    // MARK: Pruebas

    func testEveryControlResponds() throws {
        // Intensidad: los tres niveles se pueden elegir y quedan seleccionados.
        for level in ["Sutil", "Equilibrado", "Expresivo"] {
            let button = app.buttons[level]
            reveal(button)
            button.tap()
            XCTAssertTrue(waitUntil { button.isSelected }, "\(level) no quedó seleccionado")
        }

        // Reducir movimiento: el valor del interruptor cambia en cada toque.
        let reduce = reduceSwitch()
        reveal(reduce)
        XCTAssertEqual(reduce.value as? String, "0", "Reducir movimiento debe empezar apagado")
        reduce.tap()
        XCTAssertTrue(waitUntil { (reduce.value as? String) == "1" }, "Reducir movimiento no se encendió")
        reduce.tap()
        XCTAssertTrue(waitUntil { (reduce.value as? String) == "0" }, "Reducir movimiento no se apagó")

        tap("gallery.mark.replay")

        // Cifras: un pago y un ingreso cambian el importe; el ojo lo oculta y lo devuelve.
        XCTAssertEqual(amountLabel(), "3.774,75 euros")
        tap("gallery.pay")
        XCTAssertTrue(waitUntil { amountLabel() == "3.769,95 euros" }, "El pago no cambió el importe: \(amountLabel())")
        tap("gallery.income")
        XCTAssertTrue(waitUntil { amountLabel() == "5.014,95 euros" }, "El ingreso no cambió el importe: \(amountLabel())")
        tap("gallery.eye")
        XCTAssertTrue(waitUntil { amountLabel() == "importe oculto" }, "El ojo no ocultó el importe")
        tap("gallery.eye")
        XCTAssertTrue(waitUntil { amountLabel() == "5.014,95 euros" }, "El ojo no devolvió el importe: \(amountLabel())")

        tap("gallery.glass")

        // Levantar: el botón cambia de «Levantar» a «Soltar» y vuelve.
        XCTAssertEqual(app.buttons["gallery.lift"].label, "Levantar")
        tap("gallery.lift")
        XCTAssertTrue(waitUntil { app.buttons["gallery.lift"].label == "Soltar" }, "No quedó levantada")
        tap("gallery.lift")
        XCTAssertTrue(waitUntil { app.buttons["gallery.lift"].label == "Levantar" }, "No se soltó")
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
            XCTAssertTrue(waitUntil { button.isSelected }, "\(title) no quedó seleccionado")
        }

        // Barra de presupuesto: 45 % -> 95 % -> 45 %.
        let fill = any("gallery.fill")
        reveal(fill)
        XCTAssertEqual(fill.value as? String, "45 %")
        tap("gallery.fill.up")
        XCTAssertTrue(waitUntil { (fill.value as? String) == "95 %" }, "La barra no subió a 95 %")
        tap("gallery.fill.down")
        XCTAssertTrue(waitUntil { (fill.value as? String) == "45 %" }, "La barra no bajó a 45 %")

        // Pasos: empieza en el primero; cada toque avanza uno y el último los deja todos hechos.
        XCTAssertEqual(stepValue(1, "Autorizar"), "en curso")
        XCTAssertEqual(stepValue(2, "Leer cuentas"), "pendiente")
        tap("gallery.step.next")
        XCTAssertTrue(waitUntil { stepValue(1, "Autorizar") == "hecho" }, "El paso 1 no quedó hecho")
        XCTAssertEqual(stepValue(2, "Leer cuentas"), "en curso")
        XCTAssertEqual(stepValue(3, "Listo"), "pendiente")
        for _ in 0..<3 { tap("gallery.step.next") }
        XCTAssertTrue(waitUntil { stepValue(3, "Listo") == "hecho" }, "El último paso no quedó hecho")
        tap("gallery.step.reset")
        XCTAssertTrue(waitUntil { stepValue(1, "Autorizar") == "en curso" }, "Reiniciar no volvió al primer paso")
    }

    /// Con el ojo cerrado, ninguna cifra real está en pantalla ni en el árbol de accesibilidad, ni durante un cambio.
    func testHiddenAmountNeverExposesDigits() throws {
        tap("gallery.eye")
        for _ in 0..<8 {
            XCTAssertTrue(labelled("importe oculto").waitForExistence(timeout: 3))
            XCTAssertEqual(moneyLabelCount(), 0, "Hay una cifra real con el ojo cerrado")
            Thread.sleep(forTimeInterval: 0.3)
        }
        tap("gallery.pay")
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertEqual(moneyLabelCount(), 0, "Un pago con el ojo cerrado enseñó la cifra")
        // Al mostrarlo vuelve con el importe de ahora (el pago incluido).
        tap("gallery.eye")
        XCTAssertTrue(waitUntil { amountLabel() == "3.769,95 euros" }, "Al mostrar no salió el importe actual: \(amountLabel())")
    }

    /// Un pago que llega mientras el ojo está cambiando no se pierde.
    func testChangeDuringEyeToggleIsNotLost() throws {
        tap("gallery.eye")
        XCTAssertTrue(waitUntil { amountLabel() == "importe oculto" })
        tap("gallery.eye")
        tap("gallery.pay")
        XCTAssertTrue(waitUntil(8) { amountLabel() == "3.769,95 euros" }, "Se perdió el pago: \(amountLabel())")
    }
}
