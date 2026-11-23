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

    /// Prueba de toques: ojo, ojo, pago, y la etiqueta dice el importe con el pago. No prueba un cambio DURANTE el
    /// barajado (`tap()` espera a que la app esté quieta y la etiqueta sale de `cents`, no de lo dibujado): eso lo
    /// prueba `AmountRevealTests` en Core. La primera espera es larga porque es la prueba del arranque más frío.
    func testEyeTapsThenPaymentUpdateTheLabel() throws {
        launchGallery()
        tap("gallery.eye")
        XCTAssertTrue(labelled("importe oculto").waitForExistence(timeout: 30), "El ojo no ocultó el importe")
        XCTAssertTrue(waitUntil { amountLabel() == "importe oculto" }, "Queda un importe a la vista: \(amountLabel())")
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

    /// Las filas `.plain` de la galería existen con su importe (VoiceOver lee el importe, no el signo de la maqueta). Lee
    /// solo etiquetas: no prueba la tipografía de K14 (eso lo enseña la captura) ni el color (`testPlainIncome…`).
    func testPlainRowsShowTheirAmounts() throws {
        launchGallery()
        for (id, label) in [("gallery.row.expense", "-4,80 euros"), ("gallery.row.income", "1.250,00 euros"),
                            ("gallery.row.plain", "61,20 euros")] {
            let row = any(id)
            XCTAssertTrue(row.waitForExistence(timeout: 5), "No existe \(id)")
            XCTAssertEqual(row.label, label, "\(id)")
        }
    }

    // MARK: Bloqueos antes de la fase B

    /// Tinta de una franja de la pantalla (en puntos): píxeles del verde de los ingresos (#30D158), píxeles casi blancos
    /// y dónde empieza y acaba (x, en puntos) lo verde. Se mide sobre la captura de la pantalla, no del elemento: el
    /// marco de un elemento puede ser mayor que lo que se ve.
    private struct Ink {
        var green = 0, white = 0, greenMinX = CGFloat.infinity, greenMaxX = -CGFloat.infinity
        /// El borde derecho (x, en puntos) de cualquier tinta clara.
        var inkMaxX = -CGFloat.infinity
        /// El borde derecho (x, en puntos) de la tinta gris de los títulos (`Theme.label2`), sin contar el verde.
        var greyMaxX = -CGFloat.infinity
    }

    private func ink(in band: CGRect) -> Ink {
        let shot = XCUIScreen.main.screenshot().image
        let scale = shot.scale
        guard let full = shot.cgImage else { return Ink() }
        let px = CGRect(x: band.minX * scale, y: band.minY * scale, width: band.width * scale, height: band.height * scale)
            .integral.intersection(CGRect(x: 0, y: 0, width: full.width, height: full.height))
        guard !px.isEmpty, let image = full.cropping(to: px) else { return Ink() }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return Ink() }
        var out = Ink()
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
            if g > 150, r < 120, b < 160, g - r > 70 {
                out.green += 1
                let x = (px.minX + CGFloat((i / 4) % width)) / scale
                out.greenMinX = min(out.greenMinX, x)
                out.greenMaxX = max(out.greenMaxX, x)
            }
            if r > 225, g > 225, b > 225 { out.white += 1 }
            if max(r, g, b) > 150 { out.inkMaxX = max(out.inkMaxX, (px.minX + CGFloat((i / 4) % width)) / scale) }
            if max(r, g, b) > 90, abs(r - g) < 25, abs(g - b) < 25 {
                out.greyMaxX = max(out.greyMaxX, (px.minX + CGFloat((i / 4) % width)) / scale)
            }
        }
        return out
    }

    /// La franja del importe de una fila: a la derecha del título, a su altura (las filas centran título e importe).
    private func amountBand(rightOf title: XCUIElement, halfHeight: CGFloat = 14) -> CGRect {
        let window = app.windows.firstMatch.frame
        let t = title.frame
        return CGRect(x: t.maxX, y: t.midY - halfHeight, width: window.maxX - t.maxX, height: halfHeight * 2)
    }

    /// Abre la galería bajada hasta «Filas» (debajo de la barra de estado, sin barridos) y espera a que llegue.
    private func launchRows(_ extra: [String] = []) {
        launchGallery(["-MiBancoMotionGalleryPage", "filas"] + extra)
        let title = app.staticTexts["Nómina"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let window = app.windows.firstMatch.frame
        _ = waitUntil { title.frame.minY < window.midY }
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// B-1: una fila `.plain` se dibuja con el color de quien la coloca: el ingreso sale verde (`Theme.income`), no
    /// blanco. Con `.foregroundStyle(.foreground)` en cada celda, todos sus píxeles eran blancos (255, 255, 255).
    func testPlainIncomeKeepsTheCallerColour() throws {
        launchRows()
        let income = app.staticTexts["Nómina"]
        revealWhole(income)
        let incomeInk = ink(in: amountBand(rightOf: income))
        XCTAssertGreaterThan(incomeInk.green, 40, "El ingreso no sale en verde: \(incomeInk)")
        XCTAssertLessThan(incomeInk.white, max(1, incomeInk.green / 10), "El ingreso tiene tinta blanca: \(incomeInk)")
        // Control: el gasto pide blanco y sale blanco.
        let expense = app.staticTexts["Café"]
        revealWhole(expense)
        let expenseInk = ink(in: amountBand(rightOf: expense))
        XCTAssertGreaterThan(expenseInk.white, 40, "El gasto no sale en blanco: \(expenseInk)")
        XCTAssertEqual(expenseInk.green, 0, "El gasto tiene tinta verde: \(expenseInk)")
    }

    /// B-2 sin efectos a tamaño normal: los importes de una columna acaban en el mismo borde derecho, dentro del margen
    /// de 20 pt. (Con el marco centrado y medido a mano cada fila acababa en un sitio: 422,7 y 425,3 pt de 440.)
    func testPlainRowsShareTheirRightEdge() throws {
        launchRows()
        let window = app.windows.firstMatch.frame
        let edges = ["Café", "Nómina", "Saldo"].map { name -> CGFloat in
            let title = app.staticTexts[name]
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            return ink(in: amountBand(rightOf: title)).inkMaxX
        }
        XCTAssertLessThanOrEqual((edges.max() ?? 0) - (edges.min() ?? 0), 1.5, "Bordes derechos distintos: \(edges)")
        for edge in edges {
            XCTAssertLessThanOrEqual(edge, window.maxX - 19, "Un importe se sale del margen: \(edges)")
        }
    }

    /// B-1: oculto, el ingreso conserva el color («+•••,•• €» en verde, como en el prototipo).
    func testHiddenPlainIncomeKeepsTheCallerColour() throws {
        launchRows(["-MiBancoDemoPrivate"])
        XCTAssertEqual(any("gallery.row.income").label, "importe oculto")
        let income = app.staticTexts["Nómina"]
        revealWhole(income)
        let incomeInk = ink(in: amountBand(rightOf: income))
        XCTAssertGreaterThan(incomeInk.green, 20, "El ingreso oculto no sale en verde: \(incomeInk)")
        XCTAssertLessThan(incomeInk.white, max(1, incomeInk.green / 10), "El ingreso oculto tiene tinta blanca: \(incomeInk)")
    }

    /// B-2: con el texto más grande, el importe de una fila se encoge y deja sitio al título: «Nómina» cabe en una línea
    /// (tan alta como «Café», cuya fila sí cabe) y el importe, entero, va a su derecha sin tocar el borde. Con
    /// `fixedSize()` el importe pedía ~310 pt y el título se partía en varias líneas.
    func testPlainRowLeavesRoomForTheTitleAtLargestText() throws {
        launchRows(Self.hugeText)
        let title = app.staticTexts["Nómina"]
        let reference = app.staticTexts["Café"]
        revealWhole(title)
        XCTAssertTrue(reference.exists)
        XCTAssertEqual(title.frame.height, reference.frame.height, accuracy: 2,
                       "«Nómina» se parte en varias líneas: \(title.frame) frente a «Café» \(reference.frame)")
        let window = app.windows.firstMatch.frame
        let row = CGRect(x: window.minX, y: title.frame.minY, width: window.width, height: title.frame.height)
        let rowInk = ink(in: row)
        XCTAssertGreaterThan(rowInk.green, 40, "No se ve el importe: \(rowInk)")
        // K18: al menos 8 pt de tinta a tinta entre el título y el importe (el `Spacer` pide 12; en `db9d6c8` quedaban 6,7).
        XCTAssertGreaterThanOrEqual(rowInk.greenMinX - rowInk.greyMaxX, 8, "Título e importe casi se tocan: \(rowInk)")
        XCTAssertLessThanOrEqual(rowInk.greenMaxX, window.maxX - 19, "El importe se sale del margen: \(rowInk)")
    }

    /// K18: con el texto más grande, un título largo («Nómina de noviembre») y un importe largo («+12.345,67 €»): el
    /// importe encoge lo que haga falta, queda entero dentro del margen derecho y separado del título al menos 8 pt.
    func testLongPlainRowKeepsItsGapAtLargestText() throws {
        launchRows(Self.hugeText)
        let title = app.staticTexts["Nómina de noviembre"]
        revealWhole(title)
        let window = app.windows.firstMatch.frame
        let row = CGRect(x: window.minX, y: title.frame.minY, width: window.width, height: title.frame.height)
        let rowInk = ink(in: row)
        XCTAssertGreaterThan(rowInk.green, 40, "No se ve el importe: \(rowInk)")
        XCTAssertGreaterThanOrEqual(rowInk.greenMinX - rowInk.greyMaxX, 8, "Título e importe casi se tocan: \(rowInk)")
        XCTAssertLessThanOrEqual(rowInk.greenMaxX, window.maxX - 19, "El importe se sale del margen: \(rowInk)")
        XCTAssertEqual(any("gallery.row.long").label, "12.345,67 euros")
    }

    /// K19 / K20: el elemento de VoiceOver de un importe mide su línea, no la de las tiras «0…9,0» de cada dígito (que
    /// se dibujan desplazadas y hacían el marco de 16 líneas: 325 pt a tamaño normal y 693 pt con el texto más grande).
    private func assertAmountFrameIsOneLine(_ extra: [String]) {
        launchRows(extra)
        let title = app.staticTexts["Nómina"]
        revealWhole(title)
        let amount = any("gallery.row.income").frame
        let line = title.frame.height
        XCTAssertLessThanOrEqual(amount.height, line * 1.6, "Marco del importe: \(amount), una línea: \(line)")
        XCTAssertLessThan(abs(amount.midY - title.frame.midY), line, "Marco del importe fuera de su fila: \(amount), \(title.frame)")
    }

    func testRowAmountAccessibilityFrameIsOneLine() throws {
        assertAmountFrameIsOneLine([])
    }

    func testRowAmountAccessibilityFrameIsOneLineAtLargestText() throws {
        assertAmountFrameIsOneLine(Self.hugeText)
    }

    /// K19: tres filas-botón pegadas («Hucha», «Ahorro», «Alquiler»), cada una con su importe. La del medio recibe el
    /// toque en toda su forma visible (título e importe) y ninguna roba toques a sus vecinas: un toque sobre la fila de
    /// arriba o la de abajo, a la altura de cada cifra del importe del medio y a 4 pt del borde común, cuenta en la
    /// vecina y no en ella. Su importe (marco de VoiceOver) cabe en su fila.
    ///
    /// Lo que NO se puede pedir: que un toque en un hueco VACÍO a menos de ~20 pt de un botón no lo active. Eso lo hace
    /// el sistema con cualquier botón (sonda del 23-11, ejecución 45165248227: una fila de solo `Text`, igual que una con
    /// `RollingAmount` y que una con el importe sin toques, cuentan hasta 20 pt fuera en un hueco vacío y nada a 24 pt).
    /// Por eso aquí los toques «de fuera» caen sobre vecinas de verdad, y el hueco vacío se prueba a 32 pt.
    private func assertRowButtonsKeepTheirTaps(_ extra: [String]) {
        launchRows(extra)
        let above = app.buttons["gallery.row.buttonAbove"]
        let button = app.buttons["gallery.row.button"]
        let below = app.buttons["gallery.row.buttonBelow"]
        revealWhole(above)
        revealWhole(below)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(above.frame), "«Hucha» no se ve entera: \(above.frame)")
        Thread.sleep(forTimeInterval: 0.5)
        let up = above.frame, mid = button.frame, down = below.frame
        let amount = any("gallery.row.buttonAmount").frame
        let title = app.staticTexts["Ahorro"].frame
        // Las filas no se pisan y el importe del medio (lo que lee VoiceOver) está dentro de su fila, en una línea.
        XCTAssertLessThanOrEqual(up.maxY, mid.minY + 0.5, "«Hucha» pisa «Ahorro»: \(up) \(mid)")
        XCTAssertLessThanOrEqual(mid.maxY, down.minY + 0.5, "«Ahorro» pisa «Alquiler»: \(mid) \(down)")
        XCTAssertGreaterThanOrEqual(amount.minY, mid.minY - 0.5, "El importe sube fuera de su fila: \(amount) \(mid)")
        XCTAssertLessThanOrEqual(amount.maxY, mid.maxY + 0.5, "El importe baja fuera de su fila: \(amount) \(mid)")
        XCTAssertLessThanOrEqual(amount.height, max(title.height, 1) * 1.6, "Importe de más de una línea: \(amount), título \(title)")
        func count(_ e: XCUIElement) -> Int { Int(e.value as? String ?? "") ?? -1 }
        XCTAssertEqual([count(above), count(button), count(below)], [0, 0, 0])
        let origin = app.coordinate(withNormalizedOffset: .zero)
        func tapAt(_ x: CGFloat, _ y: CGFloat) { origin.withOffset(CGVector(dx: x, dy: y)).tap() }
        // Dentro: título e importe cuentan.
        tapAt(mid.minX + 20, mid.midY)
        XCTAssertTrue(waitUntil { count(button) == 1 }, "El título de la fila no recibe el toque")
        tapAt(amount.midX, amount.midY)
        XCTAssertTrue(waitUntil { count(button) == 2 }, "El importe de la fila no recibe el toque")
        // Vecinas: a la altura de la primera cifra, del centro y del final del importe, y del título.
        let xs = [amount.minX + 4, amount.midX, amount.maxX - 4, mid.minX + 20]
        var expected = (above: 0, below: 0)
        for x in xs {
            for y in [up.midY, up.maxY - 4] {
                tapAt(x, y)
                expected.above += 1
                XCTAssertTrue(waitUntil { count(above) == expected.above },
                              "Un toque sobre «Hucha» (\(x), \(y)) no cayó en ella: \(count(above)) de \(expected.above)")
            }
            for y in [down.minY + 4, down.midY] {
                tapAt(x, y)
                expected.below += 1
                XCTAssertTrue(waitUntil { count(below) == expected.below },
                              "Un toque sobre «Alquiler» (\(x), \(y)) no cayó en ella: \(count(below)) de \(expected.below)")
            }
        }
        // Un hueco vacío lejos de todo botón (32 pt bajo la última fila) no activa ninguna.
        XCTAssertLessThan(down.maxY + 40, app.windows.firstMatch.frame.maxY, "El hueco bajo «Alquiler» no se ve: \(down)")
        tapAt(amount.midX, down.maxY + 32)
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(count(button), 2, "Un toque sobre una vecina o en un hueco cayó en «Ahorro»")
        XCTAssertEqual(count(above), expected.above)
        XCTAssertEqual(count(below), expected.below)
    }

    func testRowButtonTakesTapsOnlyOnItsRow() throws {
        assertRowButtonsKeepTheirTaps([])
    }

    func testRowButtonTakesTapsOnlyOnItsRowAtLargestText() throws {
        assertRowButtonsKeepTheirTaps(Self.hugeText)
    }

    /// B-4: sin preferencias, el ojo guardado se observa en vivo. Con el ojo abierto se ve el importe; si se cierra lo
    /// guardado (como haría Ajustes desde otra pantalla), el importe se oculta sin que nada más lo vuelva a dibujar.
    func testWithoutPreferencesTheStoredEyeIsObservedLive() throws {
        launchGallery(["-MiBancoMotionGalleryNoPrefs"])
        XCTAssertTrue(waitUntil(8) { amountLabel() == "3.774,75 euros" }, "No se ve el importe: \(amountLabel())")
        tap("gallery.storedEye.close")
        XCTAssertTrue(labelled("importe oculto").waitForExistence(timeout: 10), "El importe no se ocultó al cerrar el ojo guardado")
        XCTAssertTrue(waitUntil { moneyLabelCount() == 0 }, "Sigue habiendo una cifra real con el ojo cerrado")
    }

    /// B2 (K9): un hermano `Spacer` en un hueco de 300 pt no estira el botón que se transforma.
    func testMorphingButtonIsNotStretchedBySpacer() throws {
        launchGallery()
        let button = app.buttons["Probar en hueco"]
        revealWhole(button)
        XCTAssertLessThan(button.frame.height, 60, "Mide \(button.frame.height) pt")
        XCTAssertGreaterThanOrEqual(button.frame.height, 44)
    }

    /// Ajustes › Animaciones arranca en «Expresivo» (lo que aprobó el dueño): sin nada guardado, el nivel de las
    /// preferencias es `AppPreferences.defaultMotionLevel` y la galería lo enseña elegido.
    func testMotionLevelStartsExpressive() throws {
        launchGallery()
        let expressive = app.buttons["Expresivo"]
        XCTAssertTrue(expressive.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil { expressive.isSelected }, "«Expresivo» no es el nivel de partida")
        XCTAssertFalse(app.buttons["Equilibrado"].isSelected)
        XCTAssertFalse(app.buttons["Sutil"].isSelected)
    }
}
