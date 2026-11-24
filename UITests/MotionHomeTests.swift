import XCTest

/// Toques reales sobre lo que la fase de animaciones cambia en Inicio: importes que ruedan (y que no se ven con el ojo
/// cerrado), la marca de la barra, los botones de cristal y las tarjetas. Cada toque se comprueba por su efecto.
/// Las pruebas que miran dentro de una tarjeta usan `-MiBancoDemoCardElements` (solo DEBUG): el carrusel deja ver sus
/// piezas a XCUITest (para VoiceOver sigue siendo un solo elemento).
final class MotionHomeTests: XCTestCase {
    var app: XCUIApplication!

    /// Una etiqueta con forma de dinero: «1.284,55», «23,45»…
    private static let money = #".*[0-9]{1,3}(\.[0-9]{3})*,[0-9]{2}.*"#

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

    // MARK: Ayudas

    /// Abre Inicio con la demo y los argumentos extra, y espera a «Tu dinero».
    private func launchHome(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-MiBancoDemo", "-AppleLanguages", "(es)", "-AppleLocale", "es_ES"] + extra
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for name in ["Permitir", "Allow"] {
            let b = springboard.alerts.buttons[name]
            if b.waitForExistence(timeout: 1) { b.tap(); break }
        }
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")
    }

    private func any(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    /// El carrusel de tarjetas (su etiqueta acaba en «N de 4»).
    private func carousel() -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label ENDSWITH %@", " de 4")).firstMatch
    }

    private func moneyLabelCount() -> Int {
        app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES %@", Self.money)).count
    }

    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return condition()
    }

    // MARK: A1 — importes que ruedan, marca y cristal

    /// Con el ojo cerrado, ningún importe real está a la vista de VoiceOver en Inicio: ni al abrir, ni mientras llega
    /// un pago (`-MiBancoDemoArrival`, a los ~4 s), ni justo después de volver a cerrar el ojo.
    func testPrivateModeNeverShowsRollingDigits() throws {
        launchHome(["-MiBancoDemoPrivate", "-MiBancoDemoArrival", "-MiBancoDemoCardElements"])
        let hidden = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ AND label ENDSWITH %@", "importe oculto", " de 4")).firstMatch
        XCTAssertTrue(hidden.waitForExistence(timeout: 8), "El carrusel no dice «importe oculto»")
        let hero = any("card-hero-all")
        XCTAssertTrue(hero.waitForExistence(timeout: 5), "Falta la cifra grande de «Todo»")

        // 6,5 s: cubre el montaje de Inicio y la llegada del pago.
        let end = Date().addingTimeInterval(6.5)
        var samples = 0
        while Date() < end {
            XCTAssertEqual(moneyLabelCount(), 0, "Hay un importe a la vista con el ojo cerrado (muestra \(samples))")
            XCTAssertEqual(hero.label, "importe oculto", "La cifra grande no dice «importe oculto»")
            samples += 1
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertGreaterThanOrEqual(samples, 6, "Muy pocas muestras: \(samples)")
        for bank in ["rev", "ima", "tr"] {
            XCTAssertEqual(any("card-bank-\(bank)").label, "importe oculto", "El saldo de \(bank) no está oculto")
        }

        // Abrir el ojo enseña la cifra; cerrarlo otra vez la quita al momento.
        app.buttons["Mostrar importes"].tap()
        XCTAssertTrue(waitUntil { hero.label.hasSuffix(" euros") }, "Al abrir el ojo no salió la cifra: \(hero.label)")
        app.buttons["Ocultar importes"].tap()
        var after: [Int] = []
        for _ in 0..<6 {
            after.append(moneyLabelCount())
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertEqual(after, Array(repeating: 0, count: after.count), "Importes a la vista al cerrar el ojo: \(after)")
        XCTAssertEqual(hero.label, "importe oculto")
    }

    /// Con el texto grande de accesibilidad, la cifra que rueda cabe dentro de su tarjeta: ni se sale ni queda diminuta,
    /// y los saldos de los tres bancos tampoco se salen ni se pisan con ella.
    private func assertAmountsFitTheCard(_ category: String) {
        launchHome(["-MiBancoDemoCardElements", "-UIPreferredContentSizeCategoryName", category])
        let hero = any("card-hero-all")
        XCTAssertTrue(hero.waitForExistence(timeout: 8), "Falta la cifra grande de «Todo»")
        XCTAssertTrue(waitUntil { hero.label.hasSuffix(" euros") }, "La cifra grande no está a la vista: \(hero.label)")
        // Que acabe de contar desde 0.
        Thread.sleep(forTimeInterval: 2.5)
        let card = app.buttons["card-front-all"]
        XCTAssertTrue(card.exists, "Falta la cara delantera de «Todo»")
        let cardFrame = card.frame.insetBy(dx: -1, dy: -1)
        let heroFrame = hero.frame
        XCTAssertTrue(cardFrame.contains(heroFrame), "\(category): la cifra \(heroFrame) se sale de la tarjeta \(card.frame)")
        XCTAssertGreaterThanOrEqual(heroFrame.height, 24, "\(category): la cifra grande queda diminuta: \(heroFrame)")
        for bank in ["rev", "ima", "tr"] {
            let amount = any("card-bank-\(bank)")
            XCTAssertTrue(amount.exists, "Falta el saldo de \(bank)")
            XCTAssertTrue(amount.label.hasSuffix(" euros"), "El saldo de \(bank) no está a la vista: \(amount.label)")
            XCTAssertTrue(cardFrame.contains(amount.frame),
                          "\(category): el saldo de \(bank) \(amount.frame) se sale de la tarjeta \(card.frame)")
            XCTAssertGreaterThanOrEqual(amount.frame.minY, heroFrame.maxY - 1,
                                        "\(category): el saldo de \(bank) \(amount.frame) pisa la cifra grande \(heroFrame)")
        }
    }

    func testRollingAmountFitsAtAccessibilitySize() throws {
        assertAmountsFitTheCard("UICTContentSizeCategoryAccessibilityL")
    }

    func testRollingAmountFitsAtLargestAccessibilitySize() throws {
        assertAmountsFitTheCard("UICTContentSizeCategoryAccessibilityXXXL")
    }

    /// La marca de la barra (marca + nombre de la app) es el botón de «Tu resumen»: un toque abre el resumen.
    func testBrandSlotOpensBriefing() throws {
        launchHome()
        let brand = app.buttons["home-briefing-button"]
        XCTAssertTrue(brand.waitForExistence(timeout: 5), "Falta la marca en la barra de Inicio")
        XCTAssertEqual(brand.label, "Tu resumen")
        XCTAssertGreaterThanOrEqual(brand.frame.height, 44, "La marca no llega a 44 pt de alto: \(brand.frame)")
        // Lejos del centro también responde (el área de toque es toda la ranura).
        brand.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Vale"].waitForExistence(timeout: 10), "Tocar la marca no abrió «Tu resumen»")
    }

    /// Los botones de cristal del ojo y de la lupa (ahora se hunden y rebotan) siguen respondiendo a un toque, también
    /// lejos del centro.
    func testGlassButtonsStillRespond() throws {
        launchHome()
        let hide = app.buttons["Ocultar importes"]
        XCTAssertTrue(hide.waitForExistence(timeout: 5))
        XCTAssertEqual(hide.value as? String, "Importes visibles")
        hide.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        let show = app.buttons["Mostrar importes"]
        XCTAssertTrue(show.waitForExistence(timeout: 5), "El ojo no cambió a «Mostrar importes»")
        XCTAssertEqual(show.value as? String, "Importes ocultos")
        show.tap()
        XCTAssertTrue(app.buttons["Ocultar importes"].waitForExistence(timeout: 5), "El ojo no volvió")

        let search = app.buttons["Buscar movimientos"]
        search.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5), "La lupa no abrió la búsqueda")
        app.buttons["Cancelar"].tap()
        XCTAssertTrue(app.buttons["Buscar movimientos"].waitForExistence(timeout: 5), "Cancelar no cerró la búsqueda")
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 5), "El título no volvió al cerrar la búsqueda")
    }

    // MARK: A2 — Inicio se monta por capas

    /// Abre con el bloqueo de demo (largo, para que no se quite solo) y lo quita con un toque en «Desbloquear»: es lo
    /// que dispara el montaje por capas de Inicio.
    private func launchLockedAndUnlock(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-MiBancoDemo", "-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "60",
                               "-AppleLanguages", "(es)", "-AppleLocale", "es_ES"] + extra
        app.launch()
        let unlock = app.buttons["Desbloquear"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 15), "Falta la pantalla de bloqueo")
        unlock.tap()
    }

    /// Tras desbloquear, Inicio se monta por capas y nada se queda sin aparecer ni sin poder tocarse: la marca, el ojo,
    /// el título, la cifra de la tarjeta y la primera fila (que abre su detalle).
    private func assertHomeBuildsAndResponds(_ extra: [String]) {
        launchLockedAndUnlock(["-MiBancoDemoCardElements"] + extra)
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 10), "Inicio no aparece tras desbloquear")
        let eye = app.buttons["Ocultar importes"]
        XCTAssertTrue(waitUntil(6) { eye.exists && eye.isHittable }, "El ojo no se puede tocar tras el montaje")
        XCTAssertTrue(app.buttons["home-briefing-button"].isHittable, "La marca no se puede tocar tras el montaje")
        let hero = any("card-hero-all")
        XCTAssertTrue(waitUntil(6) { hero.exists && hero.label.hasSuffix(" euros") }, "La cifra grande no aparece")
        let row = app.buttons.matching(identifier: "movementRow").firstMatch
        XCTAssertTrue(waitUntil(6) { row.exists && row.isHittable }, "La primera fila no se puede tocar tras el montaje")
        // El montaje ha terminado: cada pieza ocupa su sitio (nada se quedó desplazado ni encogido).
        Thread.sleep(forTimeInterval: 2.5)
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(eye.frame.width, 43, "El botón del ojo se quedó encogido: \(eye.frame)")
        XCTAssertTrue(window.contains(app.staticTexts["Tu dinero"].frame), "El título quedó fuera de la pantalla")
        eye.tap()
        XCTAssertTrue(app.buttons["Mostrar importes"].waitForExistence(timeout: 5), "El ojo no respondió tras el montaje")
        app.buttons["Mostrar importes"].tap()
        row.tap()
        XCTAssertTrue(app.buttons["Cerrar"].waitForExistence(timeout: 8), "La fila no abrió su detalle tras el montaje")
    }

    func testHomeBuildsInLayersAfterUnlock() throws {
        assertHomeBuildsAndResponds([])
    }

    /// Con Reducir movimiento el montaje es un fundido: todo aparece y responde igual.
    func testHomeBuildsWithReduceMotion() throws {
        assertHomeBuildsAndResponds(["-MiBancoReduceMotion"])
    }

    /// A cámara lenta (como en las grabaciones) el montaje dura más pero termina: ninguna pieza se queda a medias.
    func testHomeBuildFinishesInSlowMotion() throws {
        launchLockedAndUnlock(["-MiBancoMotionScale", "3"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 10), "Inicio no aparece tras desbloquear")
        // 1,4 s × 1,12 × 3 ≈ 4,7 s de ventana; después todo está en su sitio y se puede tocar.
        Thread.sleep(forTimeInterval: 7)
        let search = app.buttons["Buscar movimientos"]
        XCTAssertTrue(search.isHittable, "La lupa no se puede tocar tras el montaje a cámara lenta")
        XCTAssertGreaterThanOrEqual(search.frame.width, 43, "La lupa se quedó encogida: \(search.frame)")
        let row = app.buttons.matching(identifier: "movementRow").firstMatch
        XCTAssertTrue(row.isHittable, "La primera fila no se puede tocar tras el montaje a cámara lenta")
    }

    // MARK: A3 — tarjetas

    /// El botón del segmentado con ese título exacto.
    private func segment(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    /// El número de la tarjeta de delante (1…4), leído de la etiqueta del carrusel («…, 2 de 4»).
    private func frontCardNumber() -> Int {
        let label = carousel().label
        guard let range = label.range(of: #"([0-9]) de 4$"#, options: .regularExpression) else { return 0 }
        return Int(String(label[range].prefix(1))) ?? 0
    }

    /// Carrusel, segmentado y etiqueta dicen la misma tarjeta.
    private func assertEverythingAgrees(on number: Int, _ message: String) {
        let titles = ["Todo", "Revolut", "imagin", "Trade Rep."]
        let names = ["Todo", "Revolut", "imagin", "Trade Republic"]
        XCTAssertTrue((1...4).contains(number), "\(message): tarjeta \(number)")
        guard (1...4).contains(number) else { return }
        XCTAssertTrue(carousel().label.contains(names[number - 1]), "\(message): la etiqueta no nombra la tarjeta \(number): \(carousel().label)")
        for (index, title) in titles.enumerated() {
            let button = segment(title)
            guard button.exists else { continue }
            XCTAssertEqual(button.isSelected, index == number - 1, "\(message): el segmento «\(title)» no está de acuerdo con la tarjeta \(number)")
        }
    }

    /// Deslizar con el dedo mientras el carrusel se desliza solo (`-MiBancoDemoSwitch`: a los 2 s pasa de «Todo» a
    /// Revolut; a cámara lenta ×3 ese deslizamiento dura unos 2 s): el carrusel acaba en la tarjeta que dejó el dedo
    /// (nunca vuelve a «Todo»), carrusel y segmentado dicen lo mismo, y se queda ahí. Si XCUITest llega cuando el
    /// deslizamiento ya ha terminado, el dedo avanza una tarjeta desde Revolut: imagin (3 de 4). Después, otro
    /// deslizamiento del dedo avanza exactamente una tarjeta: el carrusel sigue respondiendo.
    func testSwipeDuringGlideEndsOnTouchedCard() throws {
        launchHome(["-MiBancoDemoSwitch", "-MiBancoMotionScale", "3"])
        let card = carousel()
        XCTAssertTrue(card.waitForExistence(timeout: 5), "Falta el carrusel")
        XCTAssertTrue(waitUntil(8) { self.frontCardNumber() == 2 }, "El deslizamiento programado no empezó: \(card.label)")
        card.swipeLeft()
        XCTAssertTrue(waitUntil(8) { self.frontCardNumber() >= 2 }, "El carrusel volvió atrás: \(carousel().label)")
        // Que termine lo que esté en marcha y se asiente.
        Thread.sleep(forTimeInterval: 4)
        let landed = frontCardNumber()
        XCTAssertTrue(landed == 2 || landed == 3, "El carrusel no acabó en la tarjeta del dedo: \(carousel().label)")
        assertEverythingAgrees(on: landed, "Tras deslizar a medias")
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(frontCardNumber(), landed, "El carrusel se movió solo después de asentarse: \(carousel().label)")
        // Con todo quieto, un deslizamiento avanza exactamente una tarjeta.
        carousel().swipeLeft()
        XCTAssertTrue(waitUntil(8) { self.frontCardNumber() == landed + 1 }, "El dedo no avanzó una tarjeta: \(carousel().label)")
        Thread.sleep(forTimeInterval: 3)
        assertEverythingAgrees(on: landed + 1, "Tras el segundo deslizamiento")
    }

    /// Sin cámara lenta: un deslizamiento del dedo pasa a la tarjeta siguiente y otro hacia atrás vuelve (el gesto de
    /// levantar la tarjeta no le quita el deslizamiento al carrusel).
    func testFingerSwipesMoveOneCardEachWay() throws {
        launchHome()
        XCTAssertTrue(carousel().waitForExistence(timeout: 5), "Falta el carrusel")
        XCTAssertEqual(frontCardNumber(), 1)
        carousel().swipeLeft()
        XCTAssertTrue(waitUntil(6) { self.frontCardNumber() == 2 }, "Deslizar no pasó a Revolut: \(carousel().label)")
        assertEverythingAgrees(on: 2, "Tras deslizar a la izquierda")
        carousel().swipeRight()
        XCTAssertTrue(waitUntil(6) { self.frontCardNumber() == 1 }, "Deslizar no volvió a «Todo»: \(carousel().label)")
        assertEverythingAgrees(on: 1, "Tras deslizar a la derecha")
    }

    /// Mantener pulsada la tarjeta de delante la levanta (lo cuenta `card-lift-count`, solo en DEBUG) y soltarla NO la
    /// voltea; después, un toque corto sí la voltea y otro la devuelve.
    func testLongPressLiftsWithoutFlipping() throws {
        launchHome(["-MiBancoDemoCardElements"])
        let lifts = any("card-lift-count")
        XCTAssertTrue(lifts.waitForExistence(timeout: 8), "Falta el contador de levantadas")
        XCTAssertEqual(lifts.label, "0")
        let backButton = app.buttons["Editar saldos"]
        XCTAssertFalse(backButton.exists, "El reverso ya estaba a la vista")
        let middle = carousel().coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))

        middle.press(forDuration: 1.3)
        XCTAssertTrue(waitUntil(5) { lifts.label == "1" }, "La pulsación larga no levantó la tarjeta: \(lifts.label)")
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertFalse(backButton.exists, "Soltar la tarjeta levantada la volteó")
        XCTAssertEqual(frontCardNumber(), 1, "Levantar la tarjeta movió el carrusel")

        middle.tap()
        XCTAssertTrue(backButton.waitForExistence(timeout: 8), "Un toque corto no volteó la tarjeta")
        XCTAssertEqual(lifts.label, "1", "Un toque corto contó como levantar")
        // En el reverso, lejos del botón: vuelve la cara delantera.
        carousel().coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: backButton)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 8), .completed, "El reverso no volvió a la cara delantera")
    }

    /// Con Reducir movimiento el cambio de tarjeta es un fundido: tras tocar un segmento el carrusel queda en esa
    /// tarjeta, a la vista y respondiendo (un toque la voltea), y mantenerla pulsada no la levanta.
    func testReduceMotionCarouselStaysUsable() throws {
        launchHome(["-MiBancoReduceMotion", "-MiBancoDemoCardElements"])
        segment("Revolut").tap()
        XCTAssertTrue(waitUntil(6) { self.frontCardNumber() == 2 }, "El segmento no cambió de tarjeta: \(carousel().label)")
        Thread.sleep(forTimeInterval: 1.5)
        assertEverythingAgrees(on: 2, "Con Reducir movimiento")
        let hero = any("card-hero-rev")
        XCTAssertTrue(waitUntil(5) { hero.exists && hero.isHittable }, "La tarjeta de Revolut no quedó a la vista")
        let middle = carousel().coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        middle.tap()
        XCTAssertTrue(app.buttons["Editar saldo"].waitForExistence(timeout: 8), "Un toque no volteó la tarjeta con Reducir movimiento")
        XCTAssertEqual(any("card-lift-count").label, "0")
        // Vuelve con el segmentado a «Todo»: el fundido de vuelta tampoco deja el carrusel escondido.
        segment("Todo").tap()
        XCTAssertTrue(waitUntil(6) { self.frontCardNumber() == 1 }, "No volvió a «Todo»: \(carousel().label)")
        Thread.sleep(forTimeInterval: 1.5)
        let all = any("card-hero-all")
        XCTAssertTrue(waitUntil(5) { all.exists && all.isHittable }, "La tarjeta «Todo» no quedó a la vista")
    }
}
