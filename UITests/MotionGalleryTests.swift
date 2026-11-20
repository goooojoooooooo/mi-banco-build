import XCTest

/// Toca todos los controles de la galería de movimiento (solo DEBUG, `-MiBancoMotionGallery`): cada toque se comprueba
/// con su efecto (valores, etiquetas, estados), no solo que el elemento exista. La galería enseña el kit de movimiento
/// sin estar enlazado a las pantallas.
final class MotionGalleryTests: XCTestCase {
    var app: XCUIApplication!

    private static let hugeText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Abre la galería (con argumentos extra: tamaño de texto, modo privado, sin preferencias…).
    private func launchGallery(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-MiBancoDemo", "-MiBancoMotionGallery", "-AppleLanguages", "(es)", "-AppleLocale", "es_ES"] + extra
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

    /// Baja hasta que el elemento esté ENTERO dentro de la ventana.
    private func revealWhole(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "No existe \(element)")
        var swipes = 0
        while !app.windows.firstMatch.frame.contains(element.frame) && swipes < 14 {
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
        launchGallery()
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
        launchGallery()
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
        launchGallery()
        tap("gallery.eye")
        XCTAssertTrue(waitUntil { amountLabel() == "importe oculto" })
        tap("gallery.eye")
        tap("gallery.pay")
        XCTAssertTrue(waitUntil(8) { amountLabel() == "3.769,95 euros" }, "Se perdió el pago: \(amountLabel())")
    }

    // MARK: Ronda de revisión 2 (K9 a K12, K14)

    /// K9: con el texto más grande de accesibilidad, los dos botones que se transforman caben ENTEROS en la pantalla.
    func testMorphingButtonsFitTheScreenAtLargestText() throws {
        launchGallery(Self.hugeText)
        let window = app.windows.firstMatch
        for title in ["Probar aviso", "Probar fallo"] {
            let button = app.buttons[title]
            revealWhole(button)
            let frame = button.frame
            XCTAssertTrue(window.frame.contains(frame), "\(title) se sale de la pantalla: \(frame) en \(window.frame)")
            XCTAssertGreaterThanOrEqual(frame.minX, 8, "\(title) sin margen a la izquierda")
            XCTAssertLessThanOrEqual(frame.maxX, window.frame.maxX - 8, "\(title) sin margen a la derecha")
        }
    }

    /// K9: a tamaño normal el botón mide su alto de siempre (no se estira con el hueco).
    func testMorphingButtonHeightAtDefaultSize() throws {
        launchGallery()
        for title in ["Probar aviso", "Probar fallo"] {
            let button = app.buttons[title]
            revealWhole(button)
            XCTAssertLessThan(button.frame.height, 60, "\(title) mide \(button.frame.height) pt")
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        }
    }

    /// K10: con el texto más grande, las tres opciones de «Intensidad» se apilan, igual de altas, dentro de la pantalla,
    /// y cada una se elige al tocarla.
    func testSegmentedStacksAtLargestText() throws {
        launchGallery(Self.hugeText)
        let options = ["Sutil", "Equilibrado", "Expresivo"].map { app.buttons[$0] }
        revealWhole(options[0])
        revealWhole(options[2])
        let window = app.windows.firstMatch.frame
        let frames = options.map { $0.frame }
        for (i, frame) in frames.enumerated() {
            XCTAssertTrue(window.contains(frame), "Opción \(i) fuera de la pantalla: \(frame)")
            XCTAssertGreaterThanOrEqual(frame.height, 44)
            XCTAssertEqual(frame.height, frames[0].height, accuracy: 1, "Alturas distintas: \(frames)")
        }
        XCTAssertLessThan(frames[0].minY, frames[1].minY, "No están apiladas: \(frames)")
        XCTAssertLessThan(frames[1].minY, frames[2].minY, "No están apiladas: \(frames)")
        for button in options.reversed() {
            revealWhole(button)
            button.tap()
            XCTAssertTrue(waitUntil { button.isSelected }, "\(button.label) no quedó seleccionado")
        }
    }

    /// K10: a tamaño normal las tres opciones van en una fila (misma y) y del mismo alto.
    func testSegmentedIsOneRowAtDefaultSize() throws {
        launchGallery()
        let frames = ["Sutil", "Equilibrado", "Expresivo"].map { app.buttons[$0].frame }
        XCTAssertEqual(frames[0].minY, frames[1].minY, accuracy: 1)
        XCTAssertEqual(frames[1].minY, frames[2].minY, accuracy: 1)
        XCTAssertEqual(frames[0].height, frames[2].height, accuracy: 1)
        XCTAssertLessThan(frames[0].minX, frames[1].minX)
        XCTAssertLessThan(frames[1].minX, frames[2].minX)
    }

    /// K12: fuera del entorno de preferencias y con el ojo cerrado guardado, el importe sigue oculto (no se cierra en
    /// falso hacia «visible») y el chip «Ojo», que ahí no puede funcionar, no está.
    func testWithoutPreferencesAHiddenAmountStaysHidden() throws {
        launchGallery(["-MiBancoMotionGalleryNoPrefs", "-MiBancoDemoPrivate"])
        XCTAssertTrue(labelled("importe oculto").waitForExistence(timeout: 5), "El importe no está oculto")
        for _ in 0..<5 {
            XCTAssertEqual(moneyLabelCount(), 0, "Hay una cifra real con el ojo cerrado y sin preferencias")
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertFalse(app.buttons["gallery.eye"].exists, "El chip «Ojo» no debe estar sin preferencias")
    }

    /// K12 (control positivo): sin preferencias y con el ojo abierto, el importe se ve.
    func testWithoutPreferencesAnOpenEyeShowsTheAmount() throws {
        launchGallery(["-MiBancoMotionGalleryNoPrefs"])
        XCTAssertTrue(waitUntil(8) { amountLabel() == "3.774,75 euros" }, "No se ve el importe: \(amountLabel())")
    }

    /// K14: las filas `.plain` de la galería existen con su importe (VoiceOver lee el importe, no el signo de la maqueta).
    func testPlainRowsShowTheirAmounts() throws {
        launchGallery()
        for (id, label) in [("gallery.row.expense", "-4,80 euros"), ("gallery.row.income", "1.250,00 euros"),
                            ("gallery.row.plain", "61,20 euros")] {
            let row = any(id)
            XCTAssertTrue(row.waitForExistence(timeout: 5), "No existe \(id)")
            XCTAssertEqual(row.label, label, "\(id)")
        }
    }
}
