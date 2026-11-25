import XCTest

/// Toques reales sobre lo que la fase de animaciones cambia en Inicio: importes que ruedan (y que no se ven con el ojo
/// cerrado), la marca de la barra, los botones de cristal y las tarjetas. Cada toque se comprueba por su efecto.
/// Las pruebas que miran dentro de una tarjeta usan `-MiBancoDemoCardElements` (solo DEBUG): el carrusel deja ver sus
/// piezas a XCUITest (para VoiceOver sigue siendo un solo elemento).
final class MotionHomeTests: XCTestCase {
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
    }

    // MARK: Ayudas

    /// Abre Inicio con la demo y los argumentos extra, y espera a «Tu dinero» y a que la capa del arranque se haya
    /// quitado (mientras está, un toque la salta en vez de llegar a Inicio).
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
        XCTAssertTrue(waitUntil(20) { !self.any("launch-layer").exists }, "El arranque no terminó")
    }

    /// Lo que publica una sonda de DEBUG con forma «clave=valor;clave=valor».
    private func pairs(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for pair in text.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 { out[String(parts[0])] = String(parts[1]) }
        }
        return out
    }

    /// Los contadores de Inicio (`-MiBancoDemoHomeProbes`).
    private func homeProbe() -> [String: String] {
        let probe = app.descendants(matching: .any).matching(identifier: "home-probe").firstMatch
        guard probe.exists else { return [:] }
        return pairs(probe.value as? String ?? "")
    }

    /// Cuántos importes en texto se han dibujado con el ojo cerrado y cuántos llevaban una cifra (`-MiBancoDemoDrawnText`).
    private func drawnAudit() -> [String: String] {
        // Con «Mover dinero» abierta hay dos (la de Inicio y la de la hoja): dicen lo mismo.
        let probe = app.descendants(matching: .any).matching(identifier: "drawn-text-audit").firstMatch
        guard probe.exists else { return [:] }
        return pairs(probe.label)
    }

    /// Vuelve a la pestaña «Inicio» (en iOS 26 un toque normal en una pestaña a veces no se registra: una pulsación
    /// de 0,25 s sí).
    private func backToHomeTab() {
        let tab = app.tabBars.buttons["Inicio"]
        for _ in 0..<3 {
            if app.staticTexts["Tu dinero"].exists { return }
            if tab.exists { tab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).press(forDuration: 0.25) }
            if app.staticTexts["Tu dinero"].waitForExistence(timeout: 4) { return }
        }
    }

    /// Un texto con forma de importe: una cifra pegada a «€», «12,50» o «… euros».
    private static let amountShape = ".*([0-9][\u{00A0} ]?€|[0-9],[0-9]{2}|[0-9] euros).*"

    /// Etiquetas con forma de importe en TODA la app (una sola consulta).
    private func amountLabels() -> [String] {
        let found = app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES %@", Self.amountShape))
        guard found.count > 0 else { return [] }
        return found.allElementsBoundByIndex.prefix(8).map { "[\($0.elementType.rawValue) id=\($0.identifier) «\($0.label)»]" }
    }

    /// Lo mismo mirando también los valores de accesibilidad, elemento a elemento (lento: una vez por pantalla).
    private func amountLabelsAndValues() -> [String] {
        func shaped(_ text: String) -> Bool {
            text.range(of: "[0-9][\u{00A0} ]?€|[0-9],[0-9]{2}|[0-9] euros", options: .regularExpression) != nil
        }
        var found: [String] = []
        for element in app.descendants(matching: .any).allElementsBoundByIndex {
            if shaped(element.label) { found.append("etiqueta «\(element.label)»") }
            if let value = element.value as? String, shaped(value) { found.append("valor «\(value)»") }
        }
        return found
    }

    private func any(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    /// El carrusel de tarjetas (su etiqueta acaba en «N de 4»).
    private func carousel() -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label ENDSWITH %@", " de 4")).firstMatch
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

    /// Con el ojo cerrado no hay ni un importe en TODA Inicio: ni al abrir, ni mientras llega un pago
    /// (`-MiBancoDemoArrival`, a los ~4 s), ni al bajar la lista, ni justo después de volver a cerrar el ojo.
    /// Dos comprobaciones distintas:
    /// - lo que ve un lector de pantalla o una prueba: ninguna etiqueta ni valor con forma de importe;
    /// - lo que se DIBUJA: los importes en texto (filas, frase del mes, cifra de las barras) llevan la cuenta de qué
    ///   cadena se pintó con el ojo cerrado (`drawn-text-audit`, solo DEBUG) y ninguna puede llevar una cifra.
    func testPrivateModeNeverShowsRollingDigits() throws {
        launchHome(["-MiBancoDemoPrivate", "-MiBancoDemoArrival", "-MiBancoDemoCardElements", "-MiBancoDemoHomeProbes",
                    "-MiBancoDemoDrawnText"])
        let hidden = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ AND label ENDSWITH %@", "importe oculto", " de 4")).firstMatch
        XCTAssertTrue(hidden.waitForExistence(timeout: 8), "El carrusel no dice «importe oculto»")
        let hero = any("card-hero-all")
        XCTAssertTrue(hero.waitForExistence(timeout: 5), "Falta la cifra grande de «Todo»")

        // Hasta que el pago ha llegado y su fila ha caído (la llegada sale a los ~4 s del arranque).
        let end = Date().addingTimeInterval(9)
        var samples = 0
        while Date() < end {
            let found = amountLabels()
            XCTAssertTrue(found.isEmpty, "Hay un importe a la vista con el ojo cerrado (muestra \(samples)): \(found)")
            XCTAssertFalse(any("arrival-feedback").exists, "La insignia de la llegada (con su importe) salió con el ojo cerrado")
            samples += 1
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertGreaterThanOrEqual(samples, 5, "Muy pocas muestras: \(samples)")
        XCTAssertEqual(hero.label, "importe oculto", "La cifra grande no dice «importe oculto»")
        for bank in ["rev", "ima", "tr"] {
            XCTAssertEqual(any("card-bank-\(bank)").label, "importe oculto", "El saldo de \(bank) no está oculto")
        }
        // La llegada pasó de verdad, y con el ojo cerrado solo hizo latir la cifra (sin insignia ni importe).
        XCTAssertTrue(waitUntil(8) { self.homeProbe()["latidos"] == "1" }, "La llegada no hizo latir la cifra: \(homeProbe())")
        XCTAssertEqual(homeProbe()["insignias"], "0", "La llegada enseñó su importe con el ojo cerrado")
        XCTAssertTrue(app.buttons.matching(identifier: "movementRow").firstMatch.label.contains("Carrefour"),
                      "La fila del pago que llegó no está la primera")
        // El resumen de 7 días (también rueda) dice «importe oculto».
        let week = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Gastado en 7 días:")).firstMatch
        XCTAssertTrue(week.exists, "Falta el resumen de 7 días")
        XCTAssertTrue(week.label.contains("importe oculto"), "El resumen de 7 días no está oculto: \(week.label)")

        // Más abajo en la lista tampoco.
        app.swipeUp()
        let lower = amountLabels()
        XCTAssertTrue(lower.isEmpty, "Hay importes a la vista al bajar la lista: \(lower)")
        let everything = amountLabelsAndValues()
        XCTAssertTrue(everything.isEmpty, "Hay importes en etiquetas o valores con el ojo cerrado: \(everything)")
        app.swipeDown()

        // Lo dibujado: los importes en texto pintaron máscaras, ninguna con una cifra.
        let audit = drawnAudit()
        XCTAssertGreaterThanOrEqual(Int(audit["ocultos"] ?? "") ?? 0, 8, "Apenas se dibujaron importes en texto con el ojo cerrado: \(audit)")
        XCTAssertEqual(audit["conCifras"], "0", "Se dibujó un importe con cifras con el ojo cerrado: \(audit)")

        // Abrir el ojo enseña la cifra; cerrarlo otra vez la quita al momento, en toda la pantalla.
        app.buttons["Mostrar importes"].tap()
        XCTAssertTrue(waitUntil { hero.label.hasSuffix(" euros") }, "Al abrir el ojo no salió la cifra: \(hero.label)")
        XCTAssertFalse(amountLabels().isEmpty, "Con el ojo abierto la comprobación no encuentra importes: no vigila nada")
        app.buttons["Ocultar importes"].tap()
        for look in 0..<4 {
            let found = amountLabels()
            XCTAssertTrue(found.isEmpty, "Importes a la vista al cerrar el ojo (mirada \(look)): \(found)")
        }
        XCTAssertEqual(hero.label, "importe oculto")
        XCTAssertEqual(drawnAudit()["conCifras"], "0", "Al cerrar el ojo se dibujó un importe con cifras: \(drawnAudit())")
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

    /// Abre con el bloqueo de demo y espera a que se quite solo (a los 15 s; en el simulador, tocar «Desbloquear» abre
    /// la hoja del código del sistema). La prueba DEMUESTRA el desbloqueo: el bloqueo tiene que verse, con él puesto
    /// Inicio no se ha montado ninguna vez (`montajes=0` en la sonda de DEBUG) y, al quitarse, se monta exactamente una.
    /// (15 s de bloqueo: con la máquina cargada, la primera mirada llegaba cuando uno de 6 s ya se había quitado.)
    private func launchLockedAndUnlock(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-MiBancoDemo", "-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "15", "-MiBancoDemoHomeProbes",
                               "-AppleLanguages", "(es)", "-AppleLocale", "es_ES"] + extra
        app.launch()
        let unlock = app.buttons["Desbloquear"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 12), "Falta la pantalla de bloqueo: la prueba no puede demostrar el desbloqueo")
        XCTAssertEqual(homeProbe()["montajes"], "0", "Inicio se montó por capas con el bloqueo puesto: \(homeProbe())")
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: unlock)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 40), .completed, "El bloqueo de demo no se quitó")
        XCTAssertTrue(waitUntil(8) { self.homeProbe()["montajes"] == "1" },
                      "Al quitarse el bloqueo Inicio no se montó por capas una vez: \(homeProbe())")
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

    /// El dedo desliza con el carrusel deslizándose solo (`-MiBancoDemoSwitch`: a los 2 s pasa de «Todo» a Revolut), o,
    /// con `afterGlide`, cuando ese deslizamiento ya ha terminado. Devuelve lo que NO cumple (vacío = todo bien):
    /// 1. el dedo movió de verdad el carrusel (sube `card-finger-landings`; un deslizamiento tragado no lo sube);
    /// 2. el carrusel acaba en imagin (3 de 4); Revolut (2 de 4) solo vale si el deslizamiento programado seguía en
    ///    curso cuando el dedo empezó (`card-glide-active`), porque entonces el dedo pudo pillarlo a medio camino;
    /// 3. el carrusel acaba en la tarjeta en la que lo dejó el dedo (`card-finger-landed-on`), no en otra;
    /// 4. carrusel y segmentado dicen lo mismo, y no se mueve después;
    /// 5. el siguiente deslizamiento del dedo avanza exactamente una tarjeta.
    /// El deslizamiento programado sigue a su muelle (a ×3 dura tres veces más) y se da por «en curso» hasta que el
    /// muelle termina: mientras tanto el carrusel no hace caso de lo que informa el scroll, que es justo cuando el
    /// programa podría ganarle al dedo. Por eso, sin `afterGlide`, casi siempre vale la excepción de la regla 2 y
    /// quien vigila la regresión es la regla 3; con `afterGlide` la regla 2 exige «3 de 4» sin excepción.
    private func swipeDuringGlideProblems(_ extra: [String] = [], afterGlide: Bool = false) -> [String] {
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
        if afterGlide {
            guard waitUntil(10, { glideActive.label == "0" }) else {
                return ["El deslizamiento programado no terminó: \(glideActive.label)"]
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        let landingsBefore = Int(landings.label) ?? -1
        let wasGliding = glideActive.label == "1"
        if afterGlide, wasGliding { return ["El deslizamiento programado volvió a estar en curso antes de deslizar"] }
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

    /// El caso sin excepciones: con el deslizamiento programado ya terminado (`card-glide-active` a 0), el dedo
    /// desliza una vez y el carrusel tiene que acabar en la tarjeta siguiente (3 de 4); aquí «2 de 4» no vale.
    func testSwipeAfterGlideLandsOnNextCard() throws {
        let problems = swipeDuringGlideProblems(afterGlide: true)
        XCTAssertTrue(problems.isEmpty, problems.joined(separator: " | "))
    }

    /// La prueba de la prueba, con la regresión EXACTA: con `-MiBancoDemoGlideWins` (solo DEBUG), cuando termina un
    /// deslizamiento programado que el dedo interrumpió, el carrusel vuelve a la tarjeta del programa en vez de
    /// quedarse donde lo dejó el dedo (fuera de ese caso el dedo manda como siempre). La MISMA comprobación tiene que
    /// fallar, y por la regla que vigila eso: «no acabó en la tarjeta en la que lo dejó el dedo».
    func testSwipeGuardGoesRedWhenTheProgramBeatsTheFinger() throws {
        let problems = swipeDuringGlideProblems(["-MiBancoDemoGlideWins"])
        XCTAssertFalse(problems.isEmpty, "Con el programa ganándole al dedo, la comprobación debería fallar y no falla")
        XCTAssertTrue(problems.contains { $0.contains("no acabó en la tarjeta en la que lo dejó el dedo") },
                      "Falla, pero no por la regla que vigila la regresión: \(problems.joined(separator: " | "))")
    }

    /// Un deslizamiento programado largo («Todo» → Trade Republic) pasa por Revolut e imagin sin que empiecen a contar
    /// su cifra desde 0 (se veía «0.000,00 €» al pasar): al llegar solo han contado la de salida y la de llegada.
    func testFarGlideDoesNotRevealPassingCards() throws {
        launchHome(["-MiBancoDemoCardElements"])
        let seen = any("card-seen")
        XCTAssertTrue(seen.waitForExistence(timeout: 8), "Falta la sonda de tarjetas ya contadas")
        XCTAssertEqual(seen.label, "all", "Al arrancar ya había contado otra tarjeta además de «Todo»")
        segment("Trade Rep.").tap()
        XCTAssertTrue(waitUntil(8) { self.frontCardNumber() == 4 }, "El segmento no llevó a Trade Republic: \(carousel().label)")
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(seen.label, "all,tr", "Las tarjetas por las que pasó el deslizamiento contaron su cifra: \(seen.label)")
        assertEverythingAgrees(on: 4, "Tras el deslizamiento largo")
        // Después, con el dedo, la tarjeta vecina sí cuenta la suya al verse.
        carousel().swipeRight()
        XCTAssertTrue(waitUntil(8) { self.frontCardNumber() == 3 }, "El dedo no volvió a imagin: \(carousel().label)")
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(seen.label, "all,ima,tr", "La tarjeta a la que llega el dedo no contó su cifra: \(seen.label)")
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
    /// voltea (abre el abanico de tarjetas, que se cierra con «Cerrar»); después, un toque corto sí la voltea y otro la
    /// devuelve.
    func testLongPressLiftsWithoutFlipping() throws {
        launchHome(["-MiBancoDemoCardElements", "-MiBancoDemoHomeProbes"])
        let lifts = any("card-lift-count")
        XCTAssertTrue(lifts.waitForExistence(timeout: 8), "Falta el contador de levantadas")
        XCTAssertEqual(lifts.label, "0")
        let backButton = app.buttons["Editar saldos"]
        XCTAssertFalse(backButton.exists, "El reverso ya estaba a la vista")
        let middle = carousel().coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))

        // 0,85 s: se levanta a los 0,42 s (más el retardo del toque dentro del carrusel) y el dedo sube poco después;
        // si llegara a los 0,92 s con el dedo encima, el abanico se abriría igual: lo que importa es que no la voltea.
        middle.press(forDuration: 0.85)
        XCTAssertTrue(waitUntil(6) { self.homeProbe()["abanico"] == "1" }, "Soltar la tarjeta levantada no abrió el abanico: \(homeProbe())")
        Thread.sleep(forTimeInterval: 1.5)
        let closeFan = app.buttons["wallet-fan-close"]
        XCTAssertTrue(closeFan.waitForExistence(timeout: 5), "Falta «Cerrar» en el abanico")
        closeFan.tap()
        XCTAssertTrue(waitUntil(6) { self.homeProbe()["abanico"] == "0" }, "«Cerrar» no cerró el abanico: \(homeProbe())")
        // Con el abanico abierto, Inicio (y sus sondas) queda fuera de la accesibilidad: se leen ahora.
        XCTAssertTrue(waitUntil(5) { lifts.exists && lifts.label == "1" }, "La pulsación larga no levantó la tarjeta")
        XCTAssertFalse(backButton.exists, "Soltar la tarjeta levantada (o cerrar el abanico) la volteó")
        XCTAssertEqual(frontCardNumber(), 1, "Levantar la tarjeta movió el carrusel")

        middle.tap()
        XCTAssertTrue(backButton.waitForExistence(timeout: 8), "Un toque corto no volteó la tarjeta")
        XCTAssertEqual(lifts.label, "1", "Un toque corto contó como levantar")
        XCTAssertEqual(homeProbe()["abanicos"], "1", "Un toque corto abrió el abanico")
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

    // MARK: A4 — llega un movimiento

    /// Espera a la llegada de demo (`-MiBancoDemoArrival`, ~4 s tras arrancar) mirando si la insignia de la tarjeta
    /// llega a verse; devuelve su etiqueta («Pago» / «Ingreso») o nil si nunca se vio.
    private func watchArrivalBadge(_ timeout: TimeInterval = 14) -> String? {
        let badge = any("arrival-feedback")
        var seen: String?
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if badge.exists { seen = badge.label }
            if seen != nil, homeProbe()["insignias"] == "1" { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return seen
    }

    /// Con Reducir movimiento la llegada se sigue viendo: el ✓ con el importe aparece sobre la cifra (sin viaje), la
    /// fila nueva está la primera, la cifra grande cambia, y después la insignia se va y todo responde.
    func testReduceMotionStillShowsArrival() throws {
        launchHome(["-MiBancoDemoArrival", "-MiBancoReduceMotion", "-MiBancoDemoCardElements", "-MiBancoDemoHomeProbes"])
        let hero = any("card-hero-all")
        XCTAssertTrue(waitUntil(6) { hero.exists && hero.label.hasSuffix(" euros") }, "La cifra grande no aparece")
        XCTAssertEqual(watchArrivalBadge(), "Pago", "La llegada no enseñó su ✓ sobre la cifra: \(homeProbe())")
        XCTAssertEqual(homeProbe()["insignias"], "1")
        let first = app.buttons.matching(identifier: "movementRow").firstMatch
        XCTAssertTrue(waitUntil(5) { first.label.contains("Carrefour") }, "La fila del pago no está la primera: \(first.label)")
        XCTAssertTrue(hero.label.hasSuffix(" euros"), "La cifra grande dejó de verse con la llegada: \(hero.label)")
        // La insignia se va sola y no deja un importe suelto.
        XCTAssertTrue(waitUntil(8) { !self.any("arrival-feedback").exists }, "La insignia de la llegada no se fue")
        first.tap()
        let close = app.buttons["Cerrar"]
        XCTAssertTrue(close.waitForExistence(timeout: 8), "Tras la llegada, la fila nueva no abre su detalle")
        close.tap()
    }

    /// Dinero que entra (`-MiBancoDemoArrivalIncome`): el ✓ es el de un ingreso y la fila nueva es la del ingreso.
    func testIncomeArrivalShowsItsCheck() throws {
        launchHome(["-MiBancoDemoArrival", "-MiBancoDemoArrivalIncome", "-MiBancoDemoCardElements", "-MiBancoDemoHomeProbes"])
        XCTAssertEqual(watchArrivalBadge(), "Ingreso", "El ingreso no enseñó su ✓ sobre la cifra: \(homeProbe())")
        let first = app.buttons.matching(identifier: "movementRow").firstMatch
        XCTAssertTrue(waitUntil(5) { first.label.contains("Carlos") && first.label.contains("ingreso de") },
                      "La fila del ingreso no está la primera: \(first.label)")
        XCTAssertTrue(waitUntil(8) { !self.any("arrival-feedback").exists }, "La insignia del ingreso no se fue")
    }

    // MARK: A5 — listas

    private func firstRow() -> XCUIElement {
        app.buttons.matching(identifier: "movementRow").firstMatch
    }

    /// Toca una tarjeta del abanico en su franja visible (arriba): el resto de la tarjeta queda bajo la siguiente.
    private func tapFanCard(_ name: String) {
        app.buttons["wallet-card-\(name)"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
    }

    /// Deslizar una fila hacia la izquierda enseña «Nota» y «No es mío»; cada acción hace lo suyo; deslizar no mueve el
    /// carrusel ni rompe el toque normal de la fila ni el desplazamiento de la lista.
    func testSwipeRowShowsActions() throws {
        launchHome(["-MiBancoDemoCardElements"])
        let row = firstRow()
        XCTAssertTrue(row.waitForExistence(timeout: 8), "No hay filas")
        let flag = app.buttons["row-action-flag"]
        let note = app.buttons["row-action-note"]
        XCTAssertFalse(flag.exists, "Las acciones ya estaban a la vista")

        // Un deslizamiento rápido la abre.
        row.swipeLeft()
        XCTAssertTrue(flag.waitForExistence(timeout: 5), "Deslizar la fila no enseñó sus acciones")
        XCTAssertTrue(note.exists, "Falta la acción «Nota»")
        XCTAssertEqual(flag.label, "No es mío")
        XCTAssertGreaterThanOrEqual(flag.frame.width, 44, "La acción no llega a 44 pt: \(flag.frame)")
        XCTAssertEqual(frontCardNumber(), 1, "Deslizar una fila movió el carrusel")
        flag.tap()
        XCTAssertTrue(waitUntil(5) { self.firstRow().label.contains("Marcado como no es mío") },
                      "«No es mío» no marcó el movimiento: \(firstRow().label)")
        XCTAssertTrue(waitUntil(5) { !flag.exists }, "La fila no se cerró tras la acción")

        // Un arrastre lento que pasa de 70 pt también la abre; ahora la acción deshace la marca.
        let from = row.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        let to = row.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5))
        from.press(forDuration: 0.1, thenDragTo: to, withVelocity: 180, thenHoldForDuration: 0.3)
        XCTAssertTrue(flag.waitForExistence(timeout: 5), "Un arrastre lento no abrió la fila")
        XCTAssertEqual(flag.label, "Sí es mío")
        flag.tap()
        XCTAssertTrue(waitUntil(5) { !self.firstRow().label.contains("Marcado como no es mío") },
                      "«Sí es mío» no quitó la marca: \(firstRow().label)")

        // Abierta, un toque en la fila la cierra sin abrir el detalle.
        row.swipeLeft()
        XCTAssertTrue(note.waitForExistence(timeout: 5), "La fila no se abrió por tercera vez")
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        XCTAssertTrue(waitUntil(5) { !note.exists }, "Tocar la fila abierta no la cerró")
        XCTAssertFalse(app.buttons["Cerrar"].exists, "Tocar la fila abierta abrió el detalle")

        // «Nota» abre el detalle (donde se escribe la nota).
        row.swipeLeft()
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()
        let close = app.buttons["Cerrar"]
        XCTAssertTrue(close.waitForExistence(timeout: 8), "«Nota» no abrió el detalle")
        close.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: close)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 8), .completed, "El detalle no se cerró")

        // Cerrada, el toque de siempre abre el detalle, y la lista sigue bajando con el dedo sobre las filas.
        XCTAssertTrue(waitUntil(5) { !note.exists }, "La fila siguió abierta")
        row.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 8), "El toque normal de la fila dejó de abrir el detalle")
        close.tap()
        XCTAssertTrue(waitUntil(8) { !close.exists }, "El detalle no se cerró la segunda vez")
        let top = row.frame.minY
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -220)), withVelocity: 400, thenHoldForDuration: 0.3)
        XCTAssertLessThan(firstRow().frame.minY, top - 100, "Arrastrar hacia arriba sobre una fila ya no baja la lista")
    }

    /// Como en Mail: con una fila abierta, en cuanto el dedo arrastra la lista (desde OTRA fila), la fila se cierra y
    /// sus acciones dejan de existir.
    func testScrollingTheListClosesTheOpenRow() throws {
        launchHome(["-MiBancoDemoCardElements"])
        let row = firstRow()
        XCTAssertTrue(row.waitForExistence(timeout: 8), "No hay filas")
        let other = app.buttons.matching(identifier: "movementRow").element(boundBy: 1)
        XCTAssertTrue(other.waitForExistence(timeout: 5), "Falta una segunda fila")
        let flag = app.buttons["row-action-flag"]
        row.swipeLeft()
        XCTAssertTrue(flag.waitForExistence(timeout: 5), "Deslizar la fila no enseñó sus acciones")

        let top = row.frame.minY
        let start = other.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -220)), withVelocity: 400, thenHoldForDuration: 0.3)
        XCTAssertLessThan(firstRow().frame.minY, top - 100, "La lista no bajó con el arrastre")
        // La fila sigue en pantalla (así su acción no ha desaparecido solo por salir de la vista).
        XCTAssertTrue(firstRow().exists && app.windows.firstMatch.frame.intersects(firstRow().frame), "La fila salió de la pantalla")
        XCTAssertTrue(waitUntil(5) { !flag.exists }, "La fila abierta siguió abierta al arrastrar la lista")
    }

    /// Tirar de la lista hacia abajo y soltar actualiza y dice «Al día»; un tirón corto no hace nada; después todo
    /// sigue respondiendo.
    /// Con dos bancos conectados y al día (`-MiBancoDemoBanks`; la demo responde «ya estaba reciente» y pasa por
    /// `RefreshVerdict`, como la app de verdad).
    func testPullRefreshShowsAlDia() throws {
        launchHome(["-MiBancoDemoHomeProbes", "-MiBancoDemoBanks"])
        let title = app.staticTexts["Tu dinero"]
        let grab = title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        XCTAssertEqual(homeProbe()["tirones"], "0")
        // Un tirón corto (por debajo del umbral) no actualiza.
        grab.press(forDuration: 0.1, thenDragTo: grab.withOffset(CGVector(dx: 0, dy: 50)), withVelocity: 300, thenHoldForDuration: 0.2)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(homeProbe()["tirones"], "0", "Un tirón corto lanzó una actualización")

        grab.press(forDuration: 0.1, thenDragTo: grab.withOffset(CGVector(dx: 0, dy: 420)), withVelocity: 500, thenHoldForDuration: 0.3)
        // «Al día» está a la vista poco más de un segundo: se mira mientras se espera a la sonda, que cuenta cada vez
        // que el indicador lo enseña (`alDia`).
        var sawText = false
        XCTAssertTrue(waitUntil(12) {
            if self.app.staticTexts["Al día"].exists { sawText = true }
            return self.homeProbe()["alDia"] == "1"
        }, "Tirar de la lista no acabó en «Al día»: \(homeProbe())")
        XCTAssertEqual(homeProbe()["tirones"], "1", "Tirar de la lista no lanzó exactamente una actualización: \(homeProbe())")
        if !sawText { sawText = app.staticTexts["Al día"].exists }
        XCTAssertTrue(waitUntil(8) { !self.app.staticTexts["Al día"].exists }, "«Al día» no se fue (visto: \(sawText))")
        // Todo vuelve a su sitio y responde.
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(title.frame), "El título quedó fuera de su sitio")
        app.buttons["Ocultar importes"].tap()
        XCTAssertTrue(app.buttons["Mostrar importes"].waitForExistence(timeout: 5), "Inicio no responde tras actualizar")
    }

    /// «Al día» es una afirmación sobre el dinero: si un banco conectado tiene el consentimiento caducado, tirar de la
    /// lista actualiza lo que se pueda pero NO dice «Al día» (ni háptica de éxito): el indicador solo se recoge.
    func testPullRefreshWithExpiredConsentDoesNotSayAlDia() throws {
        launchHome(["-MiBancoDemoHomeProbes", "-MiBancoDemoBanks", "-MiBancoDemoRefresh", "consentExpired"])
        let title = app.staticTexts["Tu dinero"]
        let grab = title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        XCTAssertTrue(waitUntil(5) { self.homeProbe()["tirones"] == "0" }, "Falta la sonda de Inicio: \(homeProbe())")
        grab.press(forDuration: 0.1, thenDragTo: grab.withOffset(CGVector(dx: 0, dy: 420)), withVelocity: 500, thenHoldForDuration: 0.3)
        XCTAssertTrue(waitUntil(5) { self.homeProbe()["tirones"] == "1" }, "Tirar de la lista no lanzó la actualización: \(homeProbe())")
        // La actualización de la demo dura una pasada de la luz (~1,2 s) y se recoge: se mira 6 s.
        var sawText = false
        let limit = Date().addingTimeInterval(6)
        while Date() < limit {
            if app.staticTexts["Al día"].exists { sawText = true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertFalse(sawText, "Dijo «Al día» con un consentimiento caducado")
        XCTAssertEqual(homeProbe()["alDia"], "0", "El indicador contó un «Al día»: \(homeProbe())")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(title.frame), "El título quedó fuera de su sitio")
    }

    // MARK: A6 — abanico de tarjetas

    /// Mantener pulsada la tarjeta abre el abanico; «Cerrar» lo cierra; tocar «Todo» lo cierra y deja «Todo» delante;
    /// tocar la tarjeta de un banco apunta su vuelo y abre la pantalla de ese banco.
    func testWalletFanOpensAndPicks() throws {
        launchHome(["-MiBancoDemoCardElements", "-MiBancoDemoHomeProbes"])
        XCTAssertTrue(carousel().waitForExistence(timeout: 5), "Falta el carrusel")
        let middle = carousel().coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        // 1,6 s: a los 0,42 s se levanta y a los 0,92 s, con el dedo aún encima, se abre el abanico.
        middle.press(forDuration: 1.6)
        XCTAssertTrue(waitUntil(5) { self.homeProbe()["abanico"] == "1" }, "Mantener pulsada la tarjeta no abrió el abanico: \(homeProbe())")
        XCTAssertTrue(app.staticTexts["Tus tarjetas"].waitForExistence(timeout: 5), "Falta el título del abanico")
        for name in ["all", "rev", "ima", "tr"] {
            let card = app.buttons["wallet-card-\(name)"]
            XCTAssertTrue(card.waitForExistence(timeout: 5), "Falta la tarjeta \(name) en el abanico")
            XCTAssertTrue(card.label.hasSuffix(" euros"), "La tarjeta \(name) no dice su saldo: \(card.label)")
            XCTAssertGreaterThanOrEqual(card.frame.height, 44)
        }
        // El dedo que abrió el abanico, al subir, no ha volteado la tarjeta ni ha elegido nada.
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(homeProbe()["elegida"], "-", "Abrir el abanico eligió una tarjeta sola")
        // Las tarjetas están una bajo otra, sin salirse de la pantalla.
        let window = app.windows.firstMatch.frame
        let tops = ["all", "rev", "ima", "tr"].map { app.buttons["wallet-card-\($0)"].frame.minY }
        XCTAssertEqual(tops, tops.sorted(), "Las tarjetas del abanico no van una bajo otra: \(tops)")
        XCTAssertGreaterThan(tops[1] - tops[0], 30, "Las tarjetas del abanico no se han abierto: \(tops)")
        XCTAssertLessThan(tops[3], window.maxY - 60, "La última tarjeta se sale de la pantalla: \(tops)")

        app.buttons["wallet-fan-close"].tap()
        XCTAssertTrue(waitUntil(6) { self.homeProbe()["abanico"] == "0" }, "«Cerrar» no cerró el abanico")
        XCTAssertFalse(app.buttons["Editar saldos"].exists, "Abrir y cerrar el abanico volteó la tarjeta")

        // «Todo» no tiene pantalla de banco: cierra el abanico y sigue delante.
        middle.press(forDuration: 1.6)
        XCTAssertTrue(waitUntil(5) { self.homeProbe()["abanico"] == "1" }, "El abanico no se abrió la segunda vez")
        Thread.sleep(forTimeInterval: 1.5)
        tapFanCard("all")
        XCTAssertTrue(waitUntil(6) { self.homeProbe()["abanico"] == "0" }, "Tocar «Todo» no cerró el abanico")
        XCTAssertEqual(homeProbe()["vuelos"], "0", "«Todo» no vuela a ninguna pantalla")
        XCTAssertEqual(frontCardNumber(), 1)

        // La tarjeta de un banco: se apunta su vuelo y se abre su pantalla.
        middle.press(forDuration: 1.6)
        XCTAssertTrue(waitUntil(5) { self.homeProbe()["abanico"] == "1" }, "El abanico no se abrió la tercera vez")
        Thread.sleep(forTimeInterval: 1.5)
        tapFanCard("rev")
        XCTAssertTrue(app.navigationBars["Revolut"].waitForExistence(timeout: 10) || app.staticTexts["Revolut"].exists,
                      "Tocar la tarjeta de Revolut no abrió su pantalla")
        XCTAssertFalse(app.staticTexts["Tu dinero"].exists, "Sigue en Inicio tras tocar la tarjeta de Revolut")
        // La sonda de Inicio se lee volviendo a su pestaña: la tarjeta elegida, su vuelo apuntado y el abanico quitado.
        backToHomeTab()
        XCTAssertTrue(waitUntil(6) { self.homeProbe()["elegida"] == "rev" }, "Tocar la tarjeta de Revolut no la eligió: \(homeProbe())")
        XCTAssertEqual(homeProbe()["vuelos"], "1", "No se apuntó el vuelo de la tarjeta: \(homeProbe())")
        XCTAssertEqual(homeProbe()["abanico"], "0", "El abanico se quedó abierto bajo la pantalla del banco")
        XCTAssertFalse(app.staticTexts["Tus tarjetas"].exists, "El abanico sigue a la vista al volver a Inicio")
    }

    // MARK: A7 — tarjeta de inversiones

    /// La tarjeta de inversiones enseña la ficha del cambio de hoy; con el ojo cerrado la ficha no lleva cifras.
    func testInvestmentsCardShowsChangeChip() throws {
        launchHome(["-MiBancoDemoCard", "inv", "-MiBancoDemoCardElements", "-MiBancoDemoDrawnText"])
        let chip = any("card-investments-change")
        XCTAssertTrue(chip.waitForExistence(timeout: 8), "Falta la ficha del cambio en la tarjeta de inversiones")
        XCTAssertTrue(chip.label.contains("€"), "La ficha no dice el cambio: \(chip.label)")
        Thread.sleep(forTimeInterval: 1.5)
        let card = app.buttons["card-front-investments"]
        XCTAssertTrue(card.frame.insetBy(dx: -1, dy: -1).contains(chip.frame), "La ficha \(chip.frame) se sale de la tarjeta \(card.frame)")
        app.buttons["Ocultar importes"].tap()
        XCTAssertTrue(waitUntil(5) { chip.label == "importe oculto" }, "La ficha sigue diciendo el cambio con el ojo cerrado: \(chip.label)")
        let found = amountLabels()
        XCTAssertTrue(found.isEmpty, "La tarjeta y la lista de inversiones enseñan importes con el ojo cerrado: \(found)")
        XCTAssertEqual(drawnAudit()["conCifras"], "0", "Se dibujó una cifra con el ojo cerrado: \(drawnAudit())")
    }

    // MARK: A8 — «Mover dinero»

    private let nbsp = "\u{00A0}"

    /// Abre «Mover dinero» desde «Todo» y elige Revolut como destino: queda en el paso del importe.
    private func openMoveAmountStep() {
        let move = app.buttons["Mover dinero"]
        XCTAssertTrue(move.waitForExistence(timeout: 8), "Falta «Mover dinero»")
        move.tap()
        XCTAssertTrue(app.navigationBars["Mover dinero"].waitForExistence(timeout: 8), "No se abrió «Mover dinero»")
        let target = any("move-target-rev")
        XCTAssertTrue(target.waitForExistence(timeout: 8), "Falta Revolut como destino")
        target.tap()
        XCTAssertTrue(app.buttons["1"].waitForExistence(timeout: 8), "No se llegó al teclado")
    }

    /// El importe se teclea dígito a dígito y sigue las reglas de siempre: punto de millar, tope de 99.999 €, una sola
    /// coma y dos decimales; lo que no cabe se ignora. La cifra nunca se sale de la hoja.
    func testKeypadReflowsAndCaps() throws {
        launchHome()
        openMoveAmountStep()
        func shows(_ text: String) -> Bool { app.staticTexts[text].waitForExistence(timeout: 4) }
        XCTAssertTrue(shows("0\(nbsp)€"), "El importe vacío no es «0 €»")
        for key in ["1", "2", "3"] { app.buttons[key].tap() }
        XCTAssertTrue(shows("123\(nbsp)€"), "Tras 1-2-3 no dice «123 €»")
        app.buttons["4"].tap()
        XCTAssertTrue(shows("1.234\(nbsp)€"), "Con cuatro cifras falta el punto de millar")
        app.buttons["5"].tap()
        XCTAssertTrue(shows("12.345\(nbsp)€"), "Con cinco cifras el punto no se movió")
        // Tope: 99.999 €. Una sexta cifra se ignora.
        app.buttons["6"].tap()
        XCTAssertTrue(shows("12.345\(nbsp)€"), "La sexta cifra pasó del tope")
        XCTAssertFalse(app.staticTexts["123.456\(nbsp)€"].exists)
        app.buttons[","].tap()
        app.buttons["5"].tap()
        XCTAssertTrue(shows("12.345,5\(nbsp)€"), "La coma y el primer decimal no entraron")
        app.buttons[","].tap()
        app.buttons["0"].tap()
        app.buttons["7"].tap()
        XCTAssertTrue(shows("12.345,50\(nbsp)€"), "La segunda coma o el tercer decimal no se ignoraron")
        // El importe entero cabe en la hoja.
        let display = app.staticTexts["12.345,50\(nbsp)€"]
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(display.frame.minX, 0, "El importe se sale por la izquierda: \(display.frame)")
        XCTAssertLessThanOrEqual(display.frame.maxX, window.width, "El importe se sale por la derecha: \(display.frame)")
        for _ in 0..<3 { app.buttons["keypad-backspace"].tap() }
        XCTAssertTrue(shows("12.345\(nbsp)€"), "Borrar no quitó los decimales y la coma")
        for _ in 0..<2 { app.buttons["keypad-backspace"].tap() }
        XCTAssertTrue(shows("123\(nbsp)€"), "Al borrar, el punto de millar no se fue")
        for _ in 0..<3 { app.buttons["keypad-backspace"].tap() }
        XCTAssertTrue(shows("0\(nbsp)€"), "Borrado todo, no vuelve a «0 €»")
    }

    /// Arrastra «Desliza para preparar» hasta el final.
    private func slideToPrepare(until target: XCUIElement) -> Bool {
        let slider = any("move-slide")
        guard slider.waitForExistence(timeout: 8) else { return false }
        for _ in 0..<2 {
            let frame = slider.frame
            guard frame.width > 60 else { continue }
            let origin = slider.coordinate(withNormalizedOffset: .zero)
            let from = origin.withOffset(CGVector(dx: 28, dy: frame.height / 2))
            let to = origin.withOffset(CGVector(dx: frame.width - 6, dy: frame.height / 2))
            from.press(forDuration: 0.3, thenDragTo: to, withVelocity: 300, thenHoldForDuration: 0.2)
            if target.waitForExistence(timeout: 8) { return true }
        }
        return target.waitForExistence(timeout: 4)
    }

    /// El paso «listo» (el momento de éxito): los textos de siempre —se ha copiado un dato, nada dice que se haya
    /// enviado dinero—, el botón de abrir el banco responde y «Copiar IBAN» pasa a «Copiado» y vuelve.
    func testMoveMoneyReadyStepKeepsItsTextsAndCopiesAgain() throws {
        launchHome()
        openMoveAmountStep()
        for key in ["2", "0"] { app.buttons[key].tap() }
        let copied = app.staticTexts["IBAN de Revolut copiado"]
        XCTAssertTrue(slideToPrepare(until: copied), "No apareció «IBAN de Revolut copiado»")
        XCTAssertTrue(app.staticTexts["Se borra del portapapeles en 3 minutos."].waitForExistence(timeout: 5))
        XCTAssertTrue(any("move-money-explainer").exists, "Falta la línea que dice que el dinero lo envías tú")
        let ready = app.scrollViews["move-ready-scroll"]
        XCTAssertTrue(ready.waitForExistence(timeout: 5), "Falta el paso «listo»")
        for word in ["Enviado", "enviado", "Enviada", "enviada"] {
            let said = ready.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", word)).count
            XCTAssertEqual(said, 0, "El paso «listo» dice «\(word)»")
        }
        let again = ready.buttons["Copiar IBAN"]
        XCTAssertTrue(again.waitForExistence(timeout: 6), "Falta «Copiar IBAN»")
        XCTAssertGreaterThanOrEqual(again.frame.height, 44)
        again.tap()
        XCTAssertTrue(ready.buttons["Copiado"].waitForExistence(timeout: 6), "«Copiar IBAN» no pasó a «Copiado»")
        XCTAssertTrue(again.waitForExistence(timeout: 8), "«Copiado» no volvió a «Copiar IBAN»")
    }

    /// Regla D9: preparar no es enviar. El paso «listo» monta el ✓ neutro de «preparado» y NUNCA el ✓ del éxito
    /// (`SuccessMark`); ese solo sale cuando la app ha VISTO salir el dinero («He visto salir…»).
    func testReadyStepShowsPreparedMarkNotSuccessMark() throws {
        launchHome(["-MiBancoDemoHomeProbes"])
        XCTAssertEqual(homeProbe()["exitos"], "0", "Ya había un ✓ de éxito en Inicio: \(homeProbe())")
        openMoveAmountStep()
        for key in ["2", "0"] { app.buttons[key].tap() }
        let copied = app.staticTexts["IBAN de Revolut copiado"]
        XCTAssertTrue(slideToPrepare(until: copied), "No apareció «IBAN de Revolut copiado»")
        // La entrada entera ya ha pasado.
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(homeProbe()["preparados"], "1", "El paso «listo» no montó el ✓ de preparado: \(homeProbe())")
        XCTAssertEqual(homeProbe()["exitos"], "0", "El paso «listo» montó el ✓ del éxito (lee «enviado»): \(homeProbe())")

        // El camino de un traspaso detectado sigue usando el ✓ del éxito.
        launchHome(["-MiBancoDemoHomeProbes", "-MiBancoDemoPending", "done"])
        let seen = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'He visto salir'")).firstMatch
        XCTAssertTrue(seen.waitForExistence(timeout: 8), "Falta «He visto salir»")
        XCTAssertTrue(waitUntil(5) { (Int(self.homeProbe()["exitos"] ?? "") ?? 0) >= 1 },
                      "«He visto salir» no montó el ✓ del éxito: \(homeProbe())")
        XCTAssertEqual(homeProbe()["preparados"], "0", "Inicio montó un ✓ de preparado: \(homeProbe())")
    }

    // MARK: El ojo en la búsqueda, el abanico y «Mover dinero»

    /// Con el ojo cerrado no hay ni un importe en los resultados de la búsqueda, en el abanico de tarjetas ni en
    /// «Mover dinero» (destino, importe tecleado, «Desde» y el paso «listo»): ni en etiquetas ni en lo dibujado.
    func testPrivateModeHidesAmountsInSearchFanAndMoveMoney() throws {
        launchHome(["-MiBancoDemoPrivate", "-MiBancoDemoCardElements", "-MiBancoDemoHomeProbes", "-MiBancoDemoDrawnText"])
        func assertNoAmounts(_ place: String, deep: Bool = false) {
            let found = deep ? amountLabelsAndValues() : amountLabels()
            XCTAssertTrue(found.isEmpty, "\(place): hay importes con el ojo cerrado: \(found)")
            XCTAssertEqual(drawnAudit()["conCifras"], "0", "\(place): se dibujó una cifra con el ojo cerrado: \(drawnAudit())")
        }

        // Búsqueda.
        app.buttons["Buscar movimientos"].tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "La lupa no abrió la búsqueda")
        field.typeText("Mercadona")
        XCTAssertTrue(firstRow().waitForExistence(timeout: 8), "La búsqueda no encontró filas")
        Thread.sleep(forTimeInterval: 0.6)
        assertNoAmounts("Búsqueda", deep: true)
        app.buttons["Cancelar"].tap()
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 5), "No volvió Inicio al cancelar la búsqueda")

        // Abanico.
        XCTAssertTrue(carousel().waitForExistence(timeout: 5), "Falta el carrusel")
        Thread.sleep(forTimeInterval: 1)
        carousel().coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).press(forDuration: 1.6)
        XCTAssertTrue(waitUntil(5) { self.homeProbe()["abanico"] == "1" }, "No se abrió el abanico: \(homeProbe())")
        let fanCard = app.buttons["wallet-card-rev"]
        XCTAssertTrue(fanCard.waitForExistence(timeout: 5))
        XCTAssertTrue(fanCard.label.hasSuffix("importe oculto"), "La tarjeta del abanico dice su saldo: \(fanCard.label)")
        Thread.sleep(forTimeInterval: 1.5)
        assertNoAmounts("Abanico")
        app.buttons["wallet-fan-close"].tap()
        XCTAssertTrue(waitUntil(6) { self.homeProbe()["abanico"] == "0" }, "El abanico no se cerró")

        // «Mover dinero».
        openMoveAmountStep()
        for key in ["1", "2", "5"] { app.buttons[key].tap() }
        let display = any("move-amount-display")
        XCTAssertTrue(display.waitForExistence(timeout: 5), "Falta el importe tecleado")
        XCTAssertEqual(display.label, "importe oculto", "El importe tecleado se lee con el ojo cerrado")
        // Lo dibujado tampoco dice cuántas cifras lleva: con 3 y con 4 cifras (punto de millar) es la misma máscara.
        XCTAssertEqual(display.value as? String, "•••€", "La máscara del importe tecleado deja ver su tamaño")
        app.buttons["0"].tap()
        XCTAssertTrue(waitUntil(3) { (display.value as? String) == "•••€" },
                      "Con cuatro cifras la máscara cambió: \(String(describing: display.value))")
        app.buttons["keypad-backspace"].tap()
        assertNoAmounts("Mover dinero, importe")
        let copied = app.staticTexts["IBAN de Revolut copiado"]
        XCTAssertTrue(slideToPrepare(until: copied), "No apareció «IBAN de Revolut copiado»")
        Thread.sleep(forTimeInterval: 1.5)
        assertNoAmounts("Mover dinero, listo", deep: true)
        let audit = drawnAudit()
        XCTAssertGreaterThanOrEqual(Int(audit["ocultos"] ?? "") ?? 0, 12, "Apenas se dibujaron importes en texto con el ojo cerrado: \(audit)")
    }

    // MARK: Menores del lote 1

    /// La inclinación del teléfono solo se lee con la tarjeta en pantalla: al subir la lista hasta taparla, los
    /// sensores se paran, y al volver arriba, siguen.
    func testTiltStopsWhenTheCardIsScrolledAway() throws {
        launchHome(["-MiBancoDemoHomeProbes"])
        XCTAssertTrue(waitUntil(6) { self.homeProbe()["inclinacion"] == "1" }, "Con Inicio a la vista la inclinación no se lee: \(homeProbe())")
        app.swipeUp()
        XCTAssertTrue(waitUntil(6) { self.homeProbe()["inclinacion"] == "0" },
                      "Con la tarjeta fuera de la pantalla la inclinación se sigue leyendo: \(homeProbe())")
        // De vuelta arriba del todo (arrastres cortos desde el centro, sin tirar de la lista más allá del tope).
        let title = app.staticTexts["Tu dinero"]
        let centre = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        for _ in 0..<8 {
            if title.exists && title.frame.minY >= 90 { break }
            centre.press(forDuration: 0.1, thenDragTo: centre.withOffset(CGVector(dx: 0, dy: 300)), withVelocity: 900, thenHoldForDuration: 0.2)
        }
        XCTAssertTrue(title.exists, "No se volvió arriba de la lista")
        XCTAssertTrue(waitUntil(6) { self.homeProbe()["inclinacion"] == "1" }, "Al volver arriba la inclinación no vuelve: \(homeProbe())")
    }

    /// Con Reducir movimiento, cambiar de tarjeta no superpone dos listas ni dos cifras: mientras dura el cambio el
    /// resumen de 7 días existe una sola vez, y al acabar dice lo de la tarjeta nueva.
    func testReduceMotionListSwapNeverShowsTwoSummaries() throws {
        launchHome(["-MiBancoReduceMotion", "-MiBancoDemoCardElements", "-MiBancoDemoHomeProbes"])
        let summaries = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Gastado en 7 días:"))
        XCTAssertTrue(summaries.firstMatch.waitForExistence(timeout: 8), "Falta el resumen de 7 días")
        let before = summaries.firstMatch.label
        segment("Revolut").tap()
        var most = 0
        let end = Date().addingTimeInterval(1.5)
        repeat { most = max(most, summaries.count) } while Date() < end
        XCTAssertLessThanOrEqual(most, 1, "Durante el cambio hubo \(most) resúmenes de 7 días a la vez")
        XCTAssertTrue(waitUntil(5) { summaries.firstMatch.label != before }, "El resumen no cambió con la tarjeta: \(before)")
        XCTAssertEqual(homeProbe()["listas"], "1", "La lista no hizo su cambio (salir, cambiar, entrar): \(homeProbe())")
        // Con Reducir movimiento la lista vieja sí se funde del todo (las cifras se funden por su cuenta).
        XCTAssertEqual(homeProbe()["fondoLista"], "0", "Con Reducir movimiento la lista vieja no se fundió: \(homeProbe())")
    }

    // MARK: Retoques de diseño

    /// Cambiar de tarjeta es un fundido cruzado: la lista vieja se atenúa (al 30 %) y la nueva sale desde ahí. En el
    /// instante del cambio la lista nunca está al 0 % (antes, ~100 ms de pantalla en negro bajo el selector).
    func testCardChangeNeverBlanksTheList() throws {
        launchHome(["-MiBancoDemoCardElements", "-MiBancoDemoHomeProbes"])
        let summaries = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Gastado en 7 días:"))
        XCTAssertTrue(summaries.firstMatch.waitForExistence(timeout: 8), "Falta el resumen de 7 días")
        let before = summaries.firstMatch.label
        segment("Revolut").tap()
        XCTAssertTrue(waitUntil(5) { self.homeProbe()["listas"] == "1" }, "La lista no hizo su cambio: \(homeProbe())")
        XCTAssertEqual(homeProbe()["fondoLista"], "30", "La lista vieja se apagó del todo antes del cambio: \(homeProbe())")
        XCTAssertTrue(waitUntil(5) { summaries.firstMatch.label != before }, "El resumen no cambió con la tarjeta: \(before)")
        // Sigue respondiendo: la fila abre su detalle.
        let row = firstRow()
        XCTAssertTrue(row.waitForExistence(timeout: 5), "No hay filas tras el cambio")
        row.tap()
        let close = app.buttons["Cerrar"]
        XCTAssertTrue(close.waitForExistence(timeout: 8), "Tras el cambio de tarjeta, la fila no abre su detalle")
        close.tap()
    }

    /// Prueba de la prueba de arriba: con la regresión exacta (`-MiBancoDemoListBlanks`: la lista nueva parte de
    /// invisible, la pantalla se queda en negro bajo el selector) la sonda tiene que dar 0, que es lo que la prueba
    /// anterior rechaza. Así se sabe que esa prueba puede fallar por el defecto que vigila.
    func testListBlankGuardGoesRedWhenTheListBlanks() throws {
        launchHome(["-MiBancoDemoCardElements", "-MiBancoDemoHomeProbes", "-MiBancoDemoListBlanks"])
        let summaries = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Gastado en 7 días:"))
        XCTAssertTrue(summaries.firstMatch.waitForExistence(timeout: 8), "Falta el resumen de 7 días")
        segment("Revolut").tap()
        XCTAssertTrue(waitUntil(5) { self.homeProbe()["listas"] == "1" }, "La lista no hizo su cambio: \(homeProbe())")
        XCTAssertEqual(homeProbe()["fondoLista"], "0", "Con la lista nueva invisible la sonda no lo vio: \(homeProbe())")
    }

    /// Una llegada anunciada cuyo movimiento no se publica nunca (como un aviso que sustituye a otro sin cambiar el
    /// número de movimientos) caduca: ni insignia ni fila marcada como nueva (fondo y ✓ fijos horas después).
    func testStaleArrivalNeverLeavesAFreshRow() throws {
        launchHome(["-MiBancoDemoCardMoment", "staleArrival", "-MiBancoDemoCardElements", "-MiBancoDemoHomeProbes"])
        let todo = segment("Todo")
        XCTAssertTrue(todo.waitForExistence(timeout: 8), "Falta el segmento «Todo»")
        XCTAssertEqual(homeProbe()["nueva"], "0", "Ya había una fila marcada como nueva: \(homeProbe())")
        todo.tap()
        XCTAssertTrue(waitUntil(3) { self.homeProbe()["anunciadas"] == "1" }, "La llegada no se anunció: \(homeProbe())")
        // Pasado el plazo (2 s) sin que el movimiento aparezca, la fila ya no está marcada.
        XCTAssertTrue(waitUntil(4) { self.homeProbe()["nueva"] == "0" }, "La llegada caducada dejó la fila marcada como nueva: \(homeProbe())")
        XCTAssertEqual(homeProbe()["insignias"], "0", "Una llegada sin movimiento enseñó su ✓: \(homeProbe())")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(homeProbe()["nueva"], "0", "La fila volvió a marcarse: \(homeProbe())")
    }

    /// Con el texto más grande, la cabecera del abanico («Tus tarjetas» y la ayuda) no queda debajo de la primera
    /// tarjeta: su alto sale de lo que mide (antes, 92 pt fijos).
    func testWalletFanHeaderFitsAtLargestText() throws {
        // Con este tamaño de texto la tarjeta no siempre queda bajo el dedo de la prueba: el abanico se abre por el mismo
        // camino (`openFan`) con el momento de demo (tocar el segmento ya elegido).
        launchHome(["-MiBancoDemoCardElements", "-MiBancoDemoHomeProbes", "-MiBancoDemoCardMoment", "fan",
                    "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let todo = segment("Todo")
        XCTAssertTrue(todo.waitForExistence(timeout: 8), "Falta el segmento «Todo»")
        todo.tap()
        XCTAssertTrue(waitUntil(5) { self.homeProbe()["abanico"] == "1" }, "No se abrió el abanico: \(homeProbe())")
        let help = app.staticTexts["Toca una para abrirla."]
        let first = app.buttons["wallet-card-all"]
        XCTAssertTrue(help.waitForExistence(timeout: 5) && first.waitForExistence(timeout: 5), "Falta la cabecera o la primera tarjeta")
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertLessThanOrEqual(help.frame.maxY, first.frame.minY + 1,
                                 "La primera tarjeta \(first.frame) tapa la ayuda del abanico \(help.frame)")
        app.buttons["wallet-fan-close"].tap()
        XCTAssertTrue(waitUntil(6) { self.homeProbe()["abanico"] == "0" }, "El abanico no se cerró")
    }
}
