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

    /// Etiquetas con forma de dinero DENTRO del carrusel de tarjetas (todas sus cifras son importes que ruedan). Las
    /// filas de la lista y la frase del ritmo del mes no entran: siguen siendo textos difuminados (su cifra queda en el
    /// árbol de elementos aunque VoiceOver no la lea); eso no lo cambia este lote.
    private func moneyLabelCount() -> Int {
        carousel().descendants(matching: .any).matching(NSPredicate(format: "label MATCHES %@", Self.money)).count
    }

    /// Para el mensaje de un fallo: qué elementos llevan una etiqueta con forma de dinero (los primeros).
    private func moneyLabels() -> String {
        let found = carousel().descendants(matching: .any).matching(NSPredicate(format: "label MATCHES %@", Self.money))
        return found.allElementsBoundByIndex.prefix(6)
            .map { "[\($0.elementType.rawValue) id=\($0.identifier) label=\($0.label)]" }
            .joined(separator: " ")
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
            let count = moneyLabelCount()
            XCTAssertEqual(count, 0, "Hay un importe a la vista con el ojo cerrado (muestra \(samples)): \(count > 0 ? moneyLabels() : "")")
            XCTAssertEqual(hero.label, "importe oculto", "La cifra grande no dice «importe oculto»")
            samples += 1
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertGreaterThanOrEqual(samples, 6, "Muy pocas muestras: \(samples)")
        for bank in ["rev", "ima", "tr"] {
            XCTAssertEqual(any("card-bank-\(bank)").label, "importe oculto", "El saldo de \(bank) no está oculto")
        }
        // El resumen de 7 días (también rueda) dice «importe oculto».
        let week = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Gastado en 7 días:")).firstMatch
        XCTAssertTrue(week.exists, "Falta el resumen de 7 días")
        XCTAssertTrue(week.label.contains("importe oculto"), "El resumen de 7 días no está oculto: \(week.label)")
        XCTAssertNil(week.label.range(of: #"[0-9],[0-9]{2}"#, options: .regularExpression), "El resumen de 7 días enseña una cifra: \(week.label)")

        // Abrir el ojo enseña la cifra; cerrarlo otra vez la quita al momento.
        app.buttons["Mostrar importes"].tap()
        XCTAssertTrue(waitUntil { hero.label.hasSuffix(" euros") }, "Al abrir el ojo no salió la cifra: \(hero.label)")
        app.buttons["Ocultar importes"].tap()
        var after: [Int] = []
        for _ in 0..<6 {
            after.append(moneyLabelCount())
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertEqual(after, Array(repeating: 0, count: after.count),
                       "Importes a la vista al cerrar el ojo: \(after) \(moneyLabelCount() > 0 ? moneyLabels() : "")")
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
        // Además, contra la pantalla: la tarjeta ocupa de 32 pt a (ancho − 32 pt); lo que mide XCUITest de una vista
        // dentro de un giro 3D no siempre es fiable, así que la cifra se comprueba también con esos márgenes.
        let screen = app.windows.firstMatch.frame
        var measured: [(name: String, frame: CGRect)] = [(name: "la cifra grande", frame: heroFrame)]
        for bank in ["rev", "ima", "tr"] {
            let frame: CGRect = any("card-bank-" + bank).frame
            measured.append((name: "el saldo de " + bank, frame: frame))
        }
        for item in measured {
            let left: CGFloat = item.frame.minX
            let right: CGFloat = item.frame.maxX
            let limit: CGFloat = screen.width - 31
            XCTAssertGreaterThanOrEqual(left, 31, "\(category): \(item.name) se sale por la izquierda de la tarjeta: \(item.frame)")
            XCTAssertLessThanOrEqual(right, limit, "\(category): \(item.name) se sale por la derecha de la tarjeta: \(item.frame)")
            XCTAssertGreaterThan(item.frame.width, 20, "\(category): \(item.name) no tiene ancho: \(item.frame)")
        }
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

    /// Abre con el bloqueo de demo y espera a que se quite solo (a los 6 s; en el simulador, tocar «Desbloquear» abre la
    /// hoja del código del sistema): al quitarse, Inicio se monta por capas. Con la máquina cargada (batería completa en
    /// dos simuladores) la primera mirada puede llegar cuando el bloqueo ya se ha quitado: vale igual, lo que se
    /// comprueba es cómo queda Inicio después.
    private func launchLockedAndUnlock(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-MiBancoDemo", "-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "6",
                               "-AppleLanguages", "(es)", "-AppleLocale", "es_ES"] + extra
        app.launch()
        let unlock = app.buttons["Desbloquear"]
        _ = unlock.waitForExistence(timeout: 10)
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: unlock)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 30), .completed, "El bloqueo de demo no se quitó")
    }

    /// Tras desbloquear, Inicio se monta por capas y nada se queda sin aparecer ni sin poder tocarse: la marca, el ojo,
    /// el título, la cifra de la tarjeta y la primera fila (que abre su detalle).
    private func assertHomeBuildsAndResponds(_ extra: [String]) {
        launchLockedAndUnlock(["-MiBancoDemoCardElements"] + extra)
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 10), "Inicio no aparece tras desbloquear")
        let eye = app.buttons["Ocultar importes"]
        XCTAssertTrue(eye.waitForExistence(timeout: 6), "Falta el ojo tras el montaje")
        XCTAssertTrue(app.buttons["home-briefing-button"].exists, "Falta la marca tras el montaje")
        let hero = any("card-hero-all")
        XCTAssertTrue(waitUntil(6) { hero.exists && hero.label.hasSuffix(" euros") }, "La cifra grande no aparece")
        let row = app.buttons.matching(identifier: "movementRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 6), "Falta la primera fila tras el montaje")
        // El montaje ha terminado: cada pieza ocupa su sitio (nada se quedó desplazado ni encogido).
        Thread.sleep(forTimeInterval: 2.5)
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(eye.frame.width, 43, "El botón del ojo se quedó encogido: \(eye.frame)")
        XCTAssertTrue(window.contains(app.staticTexts["Tu dinero"].frame), "El título quedó fuera de la pantalla")
        eye.tap()
        XCTAssertTrue(app.buttons["Mostrar importes"].waitForExistence(timeout: 5), "El ojo no respondió tras el montaje")
        app.buttons["Mostrar importes"].tap()
        row.tap()
        let close = app.buttons["Cerrar"]
        XCTAssertTrue(close.waitForExistence(timeout: 8), "La fila no abrió su detalle tras el montaje")
        close.tap()
        // Y la marca abre «Tu resumen».
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: close)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 8), .completed, "El detalle no se cerró")
        app.buttons["home-briefing-button"].tap()
        XCTAssertTrue(app.buttons["Vale"].waitForExistence(timeout: 10), "La marca no abrió «Tu resumen» tras el montaje")
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
        XCTAssertTrue(search.exists, "Falta la lupa tras el montaje a cámara lenta")
        XCTAssertGreaterThanOrEqual(search.frame.width, 43, "La lupa se quedó encogida: \(search.frame)")
        let row = app.buttons.matching(identifier: "movementRow").firstMatch
        XCTAssertTrue(row.exists, "Falta la primera fila tras el montaje a cámara lenta")
        row.tap()
        let close = app.buttons["Cerrar"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), "La fila no abrió su detalle tras el montaje a cámara lenta")
        close.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: close)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed, "El detalle no se cerró")
        search.tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 8), "La lupa no abrió la búsqueda tras el montaje a cámara lenta")
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

    /// Lo que no cuadra entre carrusel, segmentado y etiqueta para esa tarjeta (vacío = todos dicen lo mismo).
    private func agreementProblems(on number: Int, _ message: String) -> [String] {
        let titles = ["Todo", "Revolut", "imagin", "Trade Rep."]
        let names = ["Todo", "Revolut", "imagin", "Trade Republic"]
        guard (1...4).contains(number) else { return ["\(message): tarjeta \(number)"] }
        var problems: [String] = []
        let label = carousel().label
        if !label.contains(names[number - 1]) {
            problems.append("\(message): la etiqueta no nombra la tarjeta \(number): \(label)")
        }
        for (index, title) in titles.enumerated() {
            let button = segment(title)
            guard button.exists else { continue }
            if button.isSelected != (index == number - 1) {
                problems.append("\(message): el segmento «\(title)» no está de acuerdo con la tarjeta \(number)")
            }
        }
        return problems
    }

    /// Carrusel, segmentado y etiqueta dicen la misma tarjeta.
    private func assertEverythingAgrees(on number: Int, _ message: String) {
        let problems = agreementProblems(on: number, message)
        XCTAssertTrue(problems.isEmpty, problems.joined(separator: "; "))
    }

    /// El dedo desliza justo después de que el carrusel empiece a deslizarse solo (`-MiBancoDemoSwitch`: a los 2 s pasa
    /// de «Todo» a Revolut). Devuelve lo que NO cumple (vacío = todo bien):
    /// 1. el dedo movió de verdad el carrusel (sube `card-finger-landings`; un deslizamiento tragado no lo sube);
    /// 2. el carrusel acaba en imagin (3 de 4); Revolut (2 de 4) solo vale si el deslizamiento programado seguía en
    ///    curso cuando el dedo empezó (`card-glide-active`), porque entonces el dedo pudo pillarlo a medio camino;
    /// 3. el carrusel acaba en la tarjeta en la que lo dejó el dedo (`card-finger-landed-on`), no en otra;
    /// 4. carrusel y segmentado dicen lo mismo, y no se mueve después;
    /// 5. el siguiente deslizamiento del dedo avanza exactamente una tarjeta.
    /// El viaje programado dura lo que el scroll del sistema (unos 0,5 s) con cualquier cámara lenta; lo que la escala
    /// ×3 alarga es el rato en que el carrusel da el deslizamiento programado por «en curso» y no hace caso de lo que
    /// informa el scroll, que es justo cuando el programa podría ganarle al dedo.
    private func swipeDuringGlideProblems(_ extra: [String] = []) -> [String] {
        launchHome(["-MiBancoDemoSwitch", "-MiBancoMotionScale", "3", "-MiBancoDemoCardElements"] + extra)
        let landings = any("card-finger-landings")
        let landedOn = any("card-finger-landed-on")
        let glideActive = any("card-glide-active")
        guard carousel().waitForExistence(timeout: 5), landings.waitForExistence(timeout: 5) else {
            return ["Falta el carrusel o sus sondas"]
        }
        guard waitUntil(8, { self.frontCardNumber() == 2 }) else {
            return ["El deslizamiento programado no empezó: \(carousel().label)"]
        }
        let landingsBefore = Int(landings.label) ?? -1
        let wasGliding = glideActive.label == "1"
        carousel().swipeLeft()
        // Que termine lo que esté en marcha (a ×3 el deslizamiento programado se da por terminado a los ~3 s).
        Thread.sleep(forTimeInterval: 5)

        var problems: [String] = []
        let landed = frontCardNumber()
        let landingsAfter = Int(landings.label) ?? -1
        let fingerCard = Int(landedOn.label) ?? 0
        let context = "(en curso al tocar: \(wasGliding), aterrizajes \(landingsBefore) → \(landingsAfter), dedo en \(fingerCard), carrusel en \(landed): \(carousel().label))"
        if landingsAfter <= landingsBefore {
            problems.append("El dedo no movió el carrusel \(context)")
        }
        if landed != 3 && !(wasGliding && landed == 2) {
            problems.append("El carrusel no acabó donde debía \(context)")
        }
        if fingerCard != landed {
            problems.append("El carrusel no acabó en la tarjeta en la que lo dejó el dedo \(context)")
        }
        problems += agreementProblems(on: landed, "Tras deslizar a medias")
        Thread.sleep(forTimeInterval: 2)
        if frontCardNumber() != landed {
            problems.append("El carrusel se movió solo después de asentarse: \(carousel().label)")
        }
        // Con todo quieto, un deslizamiento avanza exactamente una tarjeta.
        carousel().swipeLeft()
        if !waitUntil(8, { self.frontCardNumber() == landed + 1 }) {
            problems.append("El siguiente deslizamiento no avanzó una tarjeta: \(carousel().label)")
        } else {
            Thread.sleep(forTimeInterval: 3)
            problems += agreementProblems(on: landed + 1, "Tras el segundo deslizamiento")
        }
        return problems
    }

    /// El carrusel acaba en la tarjeta que dejó el dedo y nunca le lleva la contraria (ver `swipeDuringGlideProblems`).
    func testSwipeDuringGlideEndsOnTouchedCard() throws {
        let problems = swipeDuringGlideProblems()
        XCTAssertTrue(problems.isEmpty, problems.joined(separator: " | "))
    }

    /// La prueba de la prueba: con `-MiBancoDemoFingerLoses` (solo DEBUG) el carrusel deja de seguir al dedo y vuelve a
    /// la tarjeta del programa, que es el fallo que vigila la prueba anterior. La MISMA comprobación tiene que dar
    /// problemas; si aquí saliera limpia, la prueba anterior no protegería nada.
    func testSwipeGuardGoesRedWhenTheProgramBeatsTheFinger() throws {
        let problems = swipeDuringGlideProblems(["-MiBancoDemoFingerLoses"])
        XCTAssertFalse(problems.isEmpty, "Con el programa ganándole al dedo, la comprobación debería fallar y no falla")
        XCTAssertTrue(problems.contains { $0.contains("no acabó") || $0.contains("no avanzó") },
                      "Falla, pero no por la tarjeta en la que acaba el carrusel: \(problems.joined(separator: " | "))")
    }

    /// Sin cámara lenta: un deslizamiento del dedo pasa a la tarjeta siguiente y otro hacia atrás vuelve (el gesto de
    /// levantar la tarjeta no le quita el deslizamiento al carrusel).
    func testFingerSwipesMoveOneCardEachWay() throws {
        launchHome(["-MiBancoDemoCardElements"])
        XCTAssertTrue(carousel().waitForExistence(timeout: 5), "Falta el carrusel")
        XCTAssertEqual(frontCardNumber(), 1)
        /// Dónde está cada tarjeta y los contadores de DEBUG, para el mensaje de un fallo.
        func snapshot() -> String {
            let frames = ["all", "rev", "ima", "tr"].map { name -> String in
                let front = self.any("card-front-\(name)")
                return front.exists ? "\(name)=\(Int(front.frame.minX))" : "\(name)=?"
            }.joined(separator: " ")
            let lifts = any("card-lift-count")
            let fixes = any("card-rest-fixes")
            return "\(frontCardNumber()) [\(frames) lev=\(lifts.exists ? lifts.label : "?") arr=\(fixes.exists ? fixes.label : "?")]"
        }
        // Tres a la izquierda y tres a la derecha, dejando que el carrusel se asiente entre uno y otro.
        var trace: [String] = []
        var numbers: [Int] = []
        for step in 0..<6 {
            if step < 3 { carousel().swipeLeft() } else { carousel().swipeRight() }
            Thread.sleep(forTimeInterval: 2.5)
            numbers.append(frontCardNumber())
            trace.append(snapshot())
        }
        XCTAssertEqual(numbers, [2, 3, 4, 3, 2, 1], "Cada deslizamiento debe mover una tarjeta: \(trace.joined(separator: " → "))")
        assertEverythingAgrees(on: 1, "Tras deslizar de vuelta")
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
        let middle = carousel().coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        middle.tap()
        XCTAssertTrue(app.buttons["Editar saldo"].waitForExistence(timeout: 8), "Un toque no volteó la tarjeta con Reducir movimiento")
        XCTAssertEqual(any("card-lift-count").label, "0")
        // Vuelve con el segmentado a «Todo»: el fundido de vuelta tampoco deja el carrusel escondido.
        segment("Todo").tap()
        XCTAssertTrue(waitUntil(6) { self.frontCardNumber() == 1 }, "No volvió a «Todo»: \(carousel().label)")
        Thread.sleep(forTimeInterval: 1.5)
        // A la vista de verdad: una vista invisible no recibe toques, y este toque voltea «Todo».
        middle.tap()
        XCTAssertTrue(app.buttons["Editar saldos"].waitForExistence(timeout: 8), "La tarjeta «Todo» no quedó a la vista tras el fundido")
    }
}
