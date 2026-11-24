import XCTest

/// Toques reales sobre lo que la fase de animaciones cambia en las pantallas (Ajustes › Animaciones, Gasto y su gráfico,
/// presupuestos, suscripciones, Avisos). Siempre con la demo (`-MiBancoDemo…`): datos inventados, sin red. Cada toque se
/// comprueba con su efecto (valores, etiquetas, estados), no solo con que el elemento exista.
final class MotionScreensTests: XCTestCase {
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

    private func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-MiBancoDemo"] + extra + ["-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for name in ["Permitir", "Allow"] {
            let b = springboard.alerts.buttons[name]
            if b.waitForExistence(timeout: 2) { b.tap(); break }
        }
    }

    /// Cualquier elemento con ese identificador (filas combinadas, grupos, etc.).
    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func waitFor(_ predicate: NSPredicate, _ object: Any, timeout: TimeInterval) -> Bool {
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: object)
        return XCTWaiter().wait(for: [exp], timeout: timeout) == .completed
    }

    /// Arrastra la pantalla hacia arriba un tercio, despacio y sin inercia (un `swipeUp` puede pasarse de largo), hasta que
    /// el elemento se pueda tocar.
    private func scrollDown(to el: XCUIElement, drags: Int = 16) {
        var left = drags
        while left > 0 && !(el.exists && el.isHittable) {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.68))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.36))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: 500, thenHoldForDuration: 0.2)
            left -= 1
        }
    }

    /// Cambia de pestaña tocando la barra; si el toque sintético no entra a la primera, pulsación corta y otro toque.
    private func selectTab(_ name: String, until target: XCUIElement) -> Bool {
        let tab = app.tabBars.buttons[name]
        tab.tap()
        if target.waitForExistence(timeout: 8) { return true }
        tab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).press(forDuration: 0.25)
        if target.waitForExistence(timeout: 8) { return true }
        tab.tap()
        return target.waitForExistence(timeout: 10)
    }

    private func goBack() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    private func value(_ el: XCUIElement) -> String { (el.value as? String) ?? "" }

    /// Los elementos que enseñan un importe con cifras («12,34 €» o «303 €», con el espacio duro de la app o uno normal).
    private func visibleAmounts() -> [String] {
        let predicate = NSPredicate(format: "label MATCHES %@", ".*[0-9][\u{00A0} ]€.*")
        return app.descendants(matching: .any).matching(predicate).allElementsBoundByIndex.map { $0.label }
    }

    // MARK: - Ajustes › Animaciones (B0)

    private func openMotionLevel(_ extra: [String] = []) -> XCUIElement {
        launch(["-MiBancoDemoScreen", "ajustes"] + extra)
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 20), "No se ve Ajustes")
        let picker = element("settings-motion-level")
        scrollDown(to: app.buttons["Equilibrado"])
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Ajustes no tiene la fila «Animaciones»")
        return picker
    }

    /// La app se estrena en «Expresivo» (lo que aprobó el dueño) y el kit lo usa de verdad.
    func testMotionLevelStartsExpressive() throws {
        let picker = openMotionLevel()
        XCTAssertTrue(app.buttons["Expresivo"].isSelected, "«Expresivo» no sale elegido al estrenar la app")
        XCTAssertFalse(app.buttons["Sutil"].isSelected)
        XCTAssertFalse(app.buttons["Equilibrado"].isSelected)
        XCTAssertEqual(value(picker), "Expresivo", "El kit no está en «Expresivo»")
        XCTAssertTrue(app.staticTexts["Animaciones"].exists, "Falta la cabecera «Animaciones»")
        XCTAssertTrue(app.staticTexts["Con Reducir movimiento activado en el iPhone, la app usa fundidos tranquilos."].exists,
                      "Falta el pie de «Animaciones»")
    }

    /// Cada nivel se elige con un toque, queda marcado él solo y llega al kit (lo que de verdad mueve la app).
    func testMotionLevelPicker() throws {
        let picker = openMotionLevel()
        for (title, others) in [("Sutil", ["Equilibrado", "Expresivo"]), ("Equilibrado", ["Sutil", "Expresivo"]),
                                ("Expresivo", ["Sutil", "Equilibrado"]), ("Sutil", ["Equilibrado", "Expresivo"])] {
            let button = app.buttons[title]
            XCTAssertTrue(button.isHittable, "«\(title)» no se puede tocar")
            button.tap()
            XCTAssertTrue(waitFor(NSPredicate(format: "selected == true"), button, timeout: 5), "«\(title)» no queda elegido")
            for other in others {
                XCTAssertFalse(app.buttons[other].isSelected, "«\(other)» sigue elegido tras tocar «\(title)»")
            }
            XCTAssertTrue(waitFor(NSPredicate(format: "value == %@", title), picker, timeout: 5),
                          "El kit no pasó a «\(title)»: \(value(picker))")
        }
        // Sigue elegido al salir de Ajustes y volver.
        // Al desplazar Ajustes la barra de pestañas se recoge: se vuelve arriba para tenerla entera.
        app.swipeDown()
        app.swipeDown()
        XCTAssertTrue(selectTab("Inicio", until: app.staticTexts["Tu dinero"]), "No se ve Inicio")
        XCTAssertTrue(selectTab("Ajustes", until: app.navigationBars["Ajustes"]), "No volvió a Ajustes")
        scrollDown(to: app.buttons["Sutil"])
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "La fila «Animaciones» no está al volver")
        XCTAssertTrue(app.buttons["Sutil"].isSelected, "El nivel elegido se perdió al cambiar de pestaña")
        XCTAssertEqual(value(picker), "Sutil")
    }

    /// El nivel forzado al arrancar (`-MiBancoMotionLevel`) es el que enseña la fila.
    func testMotionLevelRowShowsTheLevelInUse() throws {
        let picker = openMotionLevel(["-MiBancoMotionLevel", "balanced"])
        XCTAssertTrue(app.buttons["Equilibrado"].isSelected, "La fila no enseña el nivel en uso")
        XCTAssertEqual(value(picker), "Equilibrado")
    }

    // MARK: - Gasto: total, previsión y gráfico (B2, B3)

    private func openGasto(_ extra: [String] = []) {
        launch(["-MiBancoDemoScreen", "gasto"] + extra)
        XCTAssertTrue(element("gasto.total").waitForExistence(timeout: 20), "No se ve Gasto")
    }

    /// El total, la previsión y el gráfico dicen sus importes; el gráfico está en el mes en curso y en un mes pasado.
    func testSpendingShowsTotalForecastAndChart() throws {
        openGasto()
        let total = element("gasto.total")
        XCTAssertTrue(total.label.hasPrefix("Gastado en "), "El total no dice de qué mes es: \(total.label)")
        XCTAssertTrue(total.label.hasSuffix(" euros"), "El total no dice su importe: \(total.label)")
        // La previsión dice su frase entera, con su cifra en euros («…en unos 371 €»), aunque en pantalla esté contando.
        let forecast = element("gasto.prevision")
        XCTAssertTrue(forecast.waitForExistence(timeout: 5), "Gasto no enseña la previsión del mes en curso")
        XCTAssertNotNil(forecast.label.range(of: "[0-9][\u{00A0} ]€", options: .regularExpression),
                        "La previsión no dice su importe: \(forecast.label)")
        XCTAssertGreaterThan(forecast.label.count, 12, "La previsión no dice su frase: \(forecast.label)")
        let chart = element("gasto.grafico")
        XCTAssertTrue(chart.waitForExistence(timeout: 5), "Gasto no tiene el gráfico del mes")
        XCTAssertTrue(chart.label.hasPrefix("Gráfico del gasto de "), "El gráfico no dice qué es: \(chart.label)")
        // Lo de este mes va hasta hoy; lo del mes anterior es el mes ENTERO y el gráfico lo dice con su nombre («octubre
        // entero»): no compara en voz alta medio mes con uno completo sin avisar.
        let previousName = chart.label.components(separatedBy: " frente a ").last ?? ""
        XCTAssertFalse(previousName.isEmpty, "El gráfico no dice con qué mes compara: \(chart.label)")
        XCTAssertNotNil(value(chart).range(of: "^[0-9.]+,[0-9]{2} euros; \(previousName) entero: [0-9.]+,[0-9]{2} euros$",
                                           options: .regularExpression),
                        "El gráfico no dice «\(previousName) entero»: \(value(chart))")
        XCTAssertFalse(value(chart).contains(" frente a "), "El gráfico sigue comparando sin decir que el mes anterior va entero")
        // Lo que dice el gráfico es el total del mes.
        let spent = total.label.components(separatedBy: ": ").last ?? ""
        XCTAssertTrue(value(chart).hasPrefix(spent + ";"), "El gráfico («\(value(chart))») y el total («\(spent)») no coinciden")
        // Mes anterior: otro gráfico (otro mes en su etiqueta) y otro total.
        let before = chart.label
        let previous = app.buttons["gasto.mesAnterior"]
        XCTAssertTrue(previous.isHittable)
        previous.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "label != %@", before), chart, timeout: 8),
                      "El gráfico no cambió con el mes: \(chart.label)")
        let pastSpent = element("gasto.total").label.components(separatedBy: ": ").last ?? ""
        XCTAssertTrue(waitFor(NSPredicate(format: "value BEGINSWITH %@", pastSpent + ";"), chart, timeout: 8),
                      "El gráfico del mes pasado («\(value(chart))») no sigue a su total («\(pastSpent)»)")
        // Las filas siguen abriendo su categoría (la barra nueva no se come el toque).
        app.buttons["gasto.mesSiguiente"].tap()
        let row = element("gasto.fila.comerFuera")
        scrollDown(to: row)
        XCTAssertTrue(row.isHittable, "La fila de «Comer fuera» no se puede tocar")
        row.tap()
        XCTAssertTrue(element("categoria.total").waitForExistence(timeout: 8), "La fila no abre su categoría")
    }

    /// Con el ojo cerrado, Gasto, Presupuestos y Suscripciones no enseñan ni dicen ningún importe.
    func testPrivateModeHidesAmountsInSpendingScreens() throws {
        // Las tres pantallas se miran aunque una falle: así un fallo dice todo lo que se ve, no solo lo primero.
        continueAfterFailure = true
        openGasto(["-MiBancoDemoPrivate"])
        XCTAssertTrue(element("gasto.total").label.hasSuffix("importe oculto"), "El total se lee con el ojo cerrado")
        let chart = element("gasto.grafico")
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        XCTAssertEqual(value(chart), "importe oculto", "El gráfico dice importes con el ojo cerrado")
        let forecast = element("gasto.prevision")
        if forecast.exists {
            XCTAssertFalse(forecast.label.contains("€"), "La previsión se lee con el ojo cerrado: \(forecast.label)")
        }
        XCTAssertEqual(visibleAmounts(), [], "Gasto enseña importes con el ojo cerrado")

        let subscriptions = element("gasto.suscripciones")
        scrollDown(to: subscriptions)
        subscriptions.tap()
        let totals = element("suscripciones.total")
        XCTAssertTrue(totals.waitForExistence(timeout: 8), "No se ve Suscripciones")
        XCTAssertEqual(totals.label, "importe oculto al mes, importe oculto al año")
        XCTAssertEqual(visibleAmounts(), [], "Suscripciones enseña importes con el ojo cerrado")
        goBack()

        let budgets = element("gasto.presupuestos")
        scrollDown(to: budgets)
        XCTAssertTrue(budgets.waitForExistence(timeout: 8))
        budgets.tap()
        let bar = element("presupuestos.mes.barra")
        XCTAssertTrue(bar.waitForExistence(timeout: 8), "No se ve la barra del presupuesto del mes")
        XCTAssertTrue(bar.label.contains("importe oculto de importe oculto"), "La barra se lee con el ojo cerrado: \(bar.label)")
        XCTAssertFalse(bar.label.contains("por ciento"), "El porcentaje se lee con el ojo cerrado")
        XCTAssertEqual(visibleAmounts(), [], "Presupuestos enseña importes con el ojo cerrado")
    }

    // MARK: - Presupuestos: el aviso del 90 % (B2)

    /// «412,30 euros» -> 41230.
    private func spentCents(in label: String) -> Int? {
        guard let match = label.range(of: #": [0-9.]+,[0-9]{2} euros de "#, options: .regularExpression) else { return nil }
        let digits = label[match].filter { $0.isNumber }
        return Int(digits)
    }

    /// Escribe un límite nuevo en el campo (borra lo que hubiera) y lo guarda con Intro.
    private func setLimit(_ field: XCUIElement, cents: Int) {
        // El texto va pegado a la derecha: se toca junto al borde derecho para dejar el cursor al final.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        let text = "\(cents / 100)," + String(format: "%02d", cents % 100)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 14) + text + "\n")
    }

    /// Cruzar el 90 % mientras se mira avisa UNA vez (ámbar + vibración); seguir por encima no repite; bajar y volver a
    /// cruzar avisa otra vez; y una barra que ya nace pasada sale en ámbar sin avisar.
    func testBudgetWarnsOnce() throws {
        launch(["-MiBancoDemoScreen", "gasto", "-MiBancoDemoBudgets", "-MiBancoDemoBudgetWarnings"])
        let field = app.textFields["presupuestos.mes"]
        XCTAssertTrue(field.waitForExistence(timeout: 20), "No se ve Presupuestos")
        let bar = element("presupuestos.mes.barra")
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "El presupuesto del mes no tiene barra")
        let spent = try XCTUnwrap(spentCents(in: bar.label), "No se lee lo gastado en «\(bar.label)»")
        XCTAssertGreaterThan(spent, 1_000, "La demo no trae gasto este mes")
        let amber = NSPredicate(format: "value ENDSWITH %@", "ámbar")
        let white = NSPredicate(format: "value ENDSWITH %@", "blanca")

        // Punto de partida: al 50 %, blanca. Bajar (o no cruzar) nunca avisa.
        setLimit(field, cents: spent * 2)
        XCTAssertTrue(waitFor(NSPredicate(format: "label CONTAINS %@", ", 50 por ciento"), bar, timeout: 10),
                      "El límite nuevo no llegó a la barra: \(bar.label)")
        XCTAssertTrue(waitFor(white, bar, timeout: 5), "Al 50 % la barra no va en blanco: \(value(bar))")
        XCTAssertEqual(value(bar), "avisos 0, blanca")

        // Cruza el 90 % (al 95 %): un aviso, ámbar.
        setLimit(field, cents: spent * 100 / 95)
        XCTAssertTrue(waitFor(NSPredicate(format: "value == %@", "avisos 1, ámbar"), bar, timeout: 10),
                      "Cruzar el 90 % no avisó una vez: \(value(bar)) · \(bar.label)")

        // Se sale a Gasto: su barra del presupuesto del mes estaba debajo, sin verse, mientras se cruzaba el 90 %. Lleva el
        // dato nuevo y va en ámbar, pero NO ha avisado (ni pulso ni vibración desde una barra que no se ve).
        let root = element("gasto.presupuestoMes")
        let link = element("gasto.presupuestos")
        goBack()
        XCTAssertTrue(link.waitForExistence(timeout: 8), "No volvió a Gasto")
        XCTAssertTrue(root.waitForExistence(timeout: 8), "Gasto no tiene la barra del presupuesto del mes")
        XCTAssertTrue(waitFor(NSPredicate(format: "label CONTAINS %@", ", 95 por ciento"), root, timeout: 10),
                      "La barra de Gasto no lleva el límite nuevo: \(root.label)")
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(value(root), "avisos 0, ámbar", "La barra de Gasto avisó sin estar a la vista")

        // Se vuelve a Presupuestos: la barra nace ya pasada del 90 %. Ámbar desde el principio y ningún aviso.
        scrollDown(to: link)
        link.tap()
        XCTAssertTrue(bar.waitForExistence(timeout: 8), "No se ve la barra al volver")
        XCTAssertTrue(waitFor(amber, bar, timeout: 5), "La barra que nace pasada no va en ámbar: \(value(bar))")
        Thread.sleep(forTimeInterval: 2.5)
        XCTAssertEqual(value(bar), "avisos 0, ámbar", "Una barra que nace pasada del 90 % avisó")

        // Sigue por encima (al 97 %): no avisa.
        setLimit(field, cents: spent * 100 / 97)
        XCTAssertTrue(waitFor(NSPredicate(format: "label CONTAINS %@", ", 97 por ciento"), bar, timeout: 10),
                      "El límite nuevo no llegó a la barra: \(bar.label)")
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(value(bar), "avisos 0, ámbar", "Seguir por encima del 90 % avisó")

        // Baja (al 50 %): blanca, sin aviso. Y vuelve a cruzar (al 93 %): un aviso, el de esta barra.
        setLimit(field, cents: spent * 2)
        XCTAssertTrue(waitFor(white, bar, timeout: 10), "Al bajar del 90 % la barra sigue en ámbar: \(value(bar))")
        XCTAssertEqual(value(bar), "avisos 0, blanca")
        setLimit(field, cents: spent * 100 / 93)
        XCTAssertTrue(waitFor(NSPredicate(format: "value == %@", "avisos 1, ámbar"), bar, timeout: 10),
                      "Volver a cruzar el 90 % no avisó: \(value(bar)) · \(bar.label)")

        // Y la de Gasto, que tampoco se veía en estos dos cruces, sigue sin haber avisado.
        goBack()
        XCTAssertTrue(root.waitForExistence(timeout: 8), "No volvió a Gasto")
        XCTAssertTrue(waitFor(NSPredicate(format: "label CONTAINS %@", ", 93 por ciento"), root, timeout: 10),
                      "La barra de Gasto no lleva el último límite: \(root.label)")
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(value(root), "avisos 0, ámbar", "La barra de Gasto avisó sin estar a la vista")
    }

    // MARK: - Próximos cobros con el ojo cerrado (S5)

    /// Con el ojo cerrado, Próximos cobros no enseña ningún importe con cifras y VoiceOver dice «importe oculto».
    func testPrivateModeHidesAmountsInUpcomingCalendar() throws {
        openGasto(["-MiBancoDemoPrivate", "-MiBancoDemoDrawnAmounts"])
        let link = element("gasto.proximos")
        scrollDown(to: link)
        XCTAssertTrue(link.isHittable, "No se puede abrir Próximos cobros")
        link.tap()
        XCTAssertTrue(app.navigationBars["Próximos cobros"].waitForExistence(timeout: 8), "No se abrió Próximos cobros")
        let calendar = app.scrollViews["upcoming-calendar-scroll"]
        XCTAssertTrue(calendar.waitForExistence(timeout: 5), "Falta el contenedor de Próximos cobros")
        // La demo trae un cobro (Netflix) y los saldos previstos de los tres bancos.
        let hiddenAmounts = calendar.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "importe oculto"))
        XCTAssertTrue(hiddenAmounts.firstMatch.waitForExistence(timeout: 8), "VoiceOver no dice «importe oculto» en Próximos cobros")
        XCTAssertEqual(visibleAmounts(), [], "Próximos cobros enseña importes con el ojo cerrado")
        // Ni un dígito pegado a una coma decimal en ninguna etiqueta (un importe sin su «€»), aunque la etiqueta tenga
        // varias líneas.
        let decimals = app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES %@", "(?s).*[0-9],[0-9]{2}.*"))
        XCTAssertEqual(decimals.allElementsBoundByIndex.map { $0.label }, [], "Próximos cobros enseña cifras con el ojo cerrado")
        // Lo que se DIBUJA (las filas ignoran a sus hijos, así que la etiqueta no lo cuenta): cada importe dice en su
        // valor el texto que pinta. Con el ojo cerrado tiene que ser la máscara: ni un dígito. Con un desenfoque encima
        // de la cifra, aquí saldría «dibujado: −13,99 €».
        let drawn = calendar.descendants(matching: .any).matching(NSPredicate(format: "value BEGINSWITH %@", "dibujado: "))
        let texts = drawn.allElementsBoundByIndex.map { self.value($0) }
        XCTAssertGreaterThanOrEqual(texts.count, 4, "La demo trae un cobro y tres saldos previstos: \(texts)")
        for text in texts {
            XCTAssertNil(text.range(of: "[0-9]", options: .regularExpression), "Con el ojo cerrado se dibuja una cifra: \(text)")
            XCTAssertTrue(text.contains("•"), "Con el ojo cerrado no se dibuja la máscara: \(text)")
        }
    }

    /// Caso de control: con el ojo abierto, esas mismas filas dibujan sus cifras (la comprobación de arriba puede fallar).
    func testUpcomingCalendarDrawsAmountsWithTheEyeOpen() throws {
        openGasto(["-MiBancoDemoDrawnAmounts"])
        let link = element("gasto.proximos")
        scrollDown(to: link)
        link.tap()
        let calendar = app.scrollViews["upcoming-calendar-scroll"]
        XCTAssertTrue(calendar.waitForExistence(timeout: 8), "No se abrió Próximos cobros")
        let drawn = calendar.descendants(matching: .any).matching(NSPredicate(format: "value BEGINSWITH %@", "dibujado: "))
        XCTAssertTrue(drawn.firstMatch.waitForExistence(timeout: 8), "Las filas no dicen lo que dibujan")
        let texts = drawn.allElementsBoundByIndex.map { self.value($0) }
        XCTAssertGreaterThanOrEqual(texts.count, 4, "La demo trae un cobro y tres saldos previstos: \(texts)")
        for text in texts {
            XCTAssertNotNil(text.range(of: "[0-9],[0-9]{2}", options: .regularExpression), "Con el ojo abierto falta la cifra: \(text)")
        }
    }

    // MARK: - Reducir movimiento apaga las entradas de Gasto; una barra no avisa tras salir de su pestaña

    /// Con Reducir movimiento forzado (`-MiBancoReduceMotion`), Gasto no juega ninguna entrada, ni al entrar en la pestaña
    /// ni al cambiar de mes; sin la bandera, sí.
    func testReduceMotionSwitchesOffSpendingEntrances() throws {
        launch(["-MiBancoReduceMotion", "-MiBancoDemoEntranceCount"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 20), "No se ve Inicio")
        XCTAssertTrue(selectTab("Gasto", until: element("gasto.total")), "No se abre Gasto")
        let count = element("gasto.entradas")
        XCTAssertTrue(count.waitForExistence(timeout: 5), "Gasto no dice cuántas entradas ha jugado")
        XCTAssertEqual(value(count), "0", "Con Reducir movimiento Gasto jugó su entrada de pestaña")
        app.buttons["gasto.mesAnterior"].tap()
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(value(count), "0", "Con Reducir movimiento Gasto jugó la entrada del cambio de mes")

        // Control: sin la bandera, entrar en la pestaña y cambiar de mes son dos entradas.
        app.terminate()
        launch(["-MiBancoDemoEntranceCount"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 20), "No se ve Inicio")
        XCTAssertTrue(selectTab("Gasto", until: element("gasto.total")), "No se abre Gasto")
        XCTAssertTrue(count.waitForExistence(timeout: 5), "Gasto no dice cuántas entradas ha jugado")
        XCTAssertTrue(waitFor(NSPredicate(format: "value == %@", "1"), count, timeout: 5),
                      "Sin Reducir movimiento Gasto no jugó su entrada de pestaña: \(value(count))")
        app.buttons["gasto.mesAnterior"].tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "value == %@", "2"), count, timeout: 5),
                      "Sin Reducir movimiento el cambio de mes no jugó su entrada: \(value(count))")
    }

    /// El aviso del 90 % espera 0,3 s (del kit) a que la barra llegue al límite. Si en esa espera se sale de la pestaña,
    /// la barra ya no se ve y no avisa. A cámara lenta ×20 la espera dura unos 7 s: da tiempo a salir.
    func testBudgetDoesNotWarnAfterLeavingTheTab() throws {
        launch(["-MiBancoDemoScreen", "gasto", "-MiBancoDemoBudgets", "-MiBancoDemoBudgetWarnings", "-MiBancoMotionScale", "20"])
        let field = app.textFields["presupuestos.mes"]
        XCTAssertTrue(field.waitForExistence(timeout: 20), "No se ve Presupuestos")
        let bar = element("presupuestos.mes.barra")
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "El presupuesto del mes no tiene barra")
        let spent = try XCTUnwrap(spentCents(in: bar.label), "No se lee lo gastado en «\(bar.label)»")
        // Punto de partida: al 50 %, en blanco.
        setLimit(field, cents: spent * 2)
        XCTAssertTrue(waitFor(NSPredicate(format: "value == %@", "avisos 0, blanca"), bar, timeout: 15),
                      "Al 50 % la barra no va en blanco: \(value(bar))")
        // Cruza el 90 % y, sin esperar, se va a Inicio: la barra deja de verse antes de que llegue el aviso.
        setLimit(field, cents: spent * 100 / 95)
        app.tabBars.buttons["Inicio"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).press(forDuration: 0.25)
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 5), "No dio tiempo a salir a Inicio antes del aviso")
        Thread.sleep(forTimeInterval: 10)
        XCTAssertTrue(selectTab("Gasto", until: bar), "No volvió a Presupuestos")
        XCTAssertTrue(waitFor(NSPredicate(format: "label CONTAINS %@", ", 95 por ciento"), bar, timeout: 10),
                      "La barra no lleva el límite nuevo: \(bar.label)")
        XCTAssertEqual(value(bar), "avisos 0, ámbar", "La barra avisó después de salir de su pestaña")
    }

    // MARK: - Suscripciones (B1, B2)

    /// Las dos cifras de la cabecera siguen diciendo lo suyo y la fila que se cobra hoy lo dice.
    func testSubscriptionsHeaderAndTodayRow() throws {
        openGasto(["-MiBancoDemoChargeToday"])
        let link = element("gasto.suscripciones")
        scrollDown(to: link)
        link.tap()
        let totals = element("suscripciones.total")
        XCTAssertTrue(totals.waitForExistence(timeout: 8), "No se ve Suscripciones")
        XCTAssertNotNil(totals.label.range(of: #"^[0-9.]+,[0-9]{2} euros al mes, [0-9.]+,[0-9]{2} euros al año$"#,
                                           options: .regularExpression), "La cabecera no dice sus dos importes: \(totals.label)")
        let rows = app.descendants(matching: .any).matching(identifier: "suscripciones.fila")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), "No hay filas de suscripción")
        let labels = rows.allElementsBoundByIndex.map { $0.label }
        XCTAssertEqual(labels.filter { $0.contains("Próximo cobro: hoy") }.count, 1,
                       "Con `-MiBancoDemoChargeToday` debe haber una (y solo una) suscripción que se cobre hoy: \(labels)")
        // La fila sigue tomando su pulsación larga (la etiqueta «HOY» no la tapa).
        rows.element(boundBy: 0).press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Esto no es una suscripción"].waitForExistence(timeout: 5), "No salió el menú de ocultar")
    }

    /// Con la letra en XXXL (el tamaño más grande que no es de accesibilidad) e importes de cuatro y cinco cifras, la
    /// cabecera de Suscripciones salta de línea: no se sale del ancho de la pantalla ni se recorta. Deja una captura.
    func testSubscriptionsHeaderWrapsAtXXXL() throws {
        openGasto(["-MiBancoDemoBigSubscriptions", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"])
        let link = element("gasto.suscripciones")
        scrollDown(to: link)
        link.tap()
        let totals = element("suscripciones.total")
        XCTAssertTrue(totals.waitForExistence(timeout: 8), "No se ve Suscripciones")
        XCTAssertNotNil(totals.label.range(of: #"^[0-9]{2}\.[0-9]{3},[0-9]{2} euros al mes, [0-9]{3}\.[0-9]{3},[0-9]{2} euros al año$"#,
                                           options: .regularExpression), "La demo no trae los importes largos: \(totals.label)")
        Thread.sleep(forTimeInterval: 2)
        let screen = app.frame
        let frame = totals.frame
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "suscripciones-cabecera-xxxl"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertGreaterThanOrEqual(frame.minX, screen.minX + 19, "La cabecera se sale por la izquierda: \(frame)")
        XCTAssertLessThanOrEqual(frame.maxX, screen.maxX - 19, "La cabecera se sale por la derecha: \(frame) en \(screen)")
        // Dos líneas: una sola línea de este tamaño de letra mide unos 30 pt.
        XCTAssertGreaterThanOrEqual(frame.height, 44, "La cabecera no ha saltado de línea: \(frame)")
    }

    // MARK: - Avisos: el importe del aviso (B1)

    /// El aviso sigue leyéndose entero (con su importe) y, con el ojo cerrado, sin ningún importe; tocarlo abre su movimiento.
    func testAlertSentenceReadsWholeAndOpensMovement() throws {
        launch(["-MiBancoDemoScreen", "avisos"])
        XCTAssertTrue(app.navigationBars["Avisos"].waitForExistence(timeout: 20), "No se ve Avisos")
        let withAmount = NSPredicate(format: "label MATCHES %@", ".*[0-9],[0-9]{2}[\u{00A0} ]€.*")
        let row = app.buttons.matching(withAmount).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "Ningún aviso de la demo dice un importe")
        XCTAssertTrue(row.isHittable, "El aviso no se puede tocar")
        row.tap()
        let close = app.buttons["Cerrar"]
        XCTAssertTrue(close.waitForExistence(timeout: 8), "Tocar el aviso no abrió su movimiento")
        close.tap()

        app.terminate()
        launch(["-MiBancoDemoScreen", "avisos", "-MiBancoDemoPrivate"])
        XCTAssertTrue(app.navigationBars["Avisos"].waitForExistence(timeout: 20), "No se ve Avisos")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "importe oculto")).firstMatch
            .waitForExistence(timeout: 8), "Con el ojo cerrado ningún aviso dice «importe oculto»")
        XCTAssertEqual(visibleAmounts(), [], "Avisos enseña importes con el ojo cerrado")
    }

    // MARK: - Avisos y Ajustes: interruptores, umbrales y saldos (B4)

    private let hittable = NSPredicate(format: "hittable == true")

    /// El interruptor de una regla (los de Titanio, que se estiran) sigue encendiendo y apagando, y su umbral aparece y
    /// se va con él.
    func testToggleStillToggles() throws {
        launch(["-MiBancoDemoScreen", "avisos", "-MiBancoDemoRules"])
        XCTAssertTrue(app.navigationBars["Avisos"].waitForExistence(timeout: 20), "No se ve Avisos")
        let toggle = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Saldo bajo")).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "Falta el interruptor de «Saldo bajo»")
        scrollDown(to: toggle)
        XCTAssertTrue(toggle.isHittable, "El interruptor de «Saldo bajo» no se puede tocar")
        let field = app.textFields["Avisar por debajo de"]
        XCTAssertEqual(value(toggle), "1", "La demo trae «Saldo bajo» encendido")
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Con la regla encendida falta su umbral")

        toggle.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "value == %@", "0"), toggle, timeout: 5), "El interruptor no se apagó")
        XCTAssertTrue(waitFor(NSPredicate(format: "exists == false"), field, timeout: 5), "El umbral sigue con la regla apagada")

        toggle.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "value == %@", "1"), toggle, timeout: 5), "El interruptor no se encendió")
        XCTAssertTrue(field.waitForExistence(timeout: 5), "El umbral no volvió al encender la regla")
        XCTAssertTrue(waitFor(hittable, field, timeout: 5), "El umbral no se puede tocar")
        XCTAssertTrue(value(field).contains("€"), "El umbral no enseña su importe: \(value(field))")
    }

    /// Con el ojo cerrado, los umbrales de Avisos y los saldos de Ajustes (el del banco conectado y los que se editan)
    /// no enseñan ni dicen ninguna cifra.
    func testPrivateModeHidesThresholdsAndBalances() throws {
        continueAfterFailure = true
        launch(["-MiBancoDemoScreen", "avisos", "-MiBancoDemoRules", "-MiBancoDemoPrivate"])
        XCTAssertTrue(app.navigationBars["Avisos"].waitForExistence(timeout: 20), "No se ve Avisos")
        let threshold = app.textFields["Avisar por debajo de"]
        scrollDown(to: threshold)
        XCTAssertTrue(threshold.waitForExistence(timeout: 8), "Falta el umbral de «Saldo bajo»")
        XCTAssertEqual(value(threshold), "importe oculto", "El umbral se lee con el ojo cerrado")
        let large = app.textFields["Pago grande desde"]
        scrollDown(to: large)
        XCTAssertEqual(value(large), "importe oculto", "El umbral de pago grande se lee con el ojo cerrado")
        XCTAssertEqual(visibleAmounts(), [], "Avisos enseña importes con el ojo cerrado")

        app.terminate()
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoBanks", "-MiBancoDemoPrivate"])
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 20), "No se ve Ajustes")
        // Trade Republic no está conectado en la demo: su saldo es un campo que se edita.
        let editable = app.textFields["Saldo de Trade Republic"]
        scrollDown(to: editable)
        XCTAssertTrue(editable.waitForExistence(timeout: 8), "Falta el saldo de Trade Republic")
        XCTAssertEqual(value(editable), "importe oculto", "El saldo que se edita se lee con el ojo cerrado")
        let connected = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Saldo de Revolut: ")).firstMatch
        XCTAssertTrue(connected.waitForExistence(timeout: 5), "Falta el saldo de Revolut (conectado)")
        XCTAssertEqual(connected.label, "Saldo de Revolut: importe oculto")
        XCTAssertEqual(visibleAmounts(), [], "Ajustes enseña importes con el ojo cerrado")
    }

    /// Guardar un saldo a mano sigue enseñando su ✓ («Guardado») junto al campo, y el campo se queda con el importe nuevo.
    func testSavingABalanceShowsTheCheck() throws {
        launch(["-MiBancoDemoScreen", "ajustes"])
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 20), "No se ve Ajustes")
        let field = app.textFields["Saldo de Revolut"]
        scrollDown(to: field)
        XCTAssertTrue(field.waitForExistence(timeout: 8), "Falta el saldo de Revolut")
        let saved = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Guardado")).firstMatch
        XCTAssertFalse(saved.exists, "El ✓ de guardado ya estaba antes de guardar")
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 14) + "512,34\n")
        XCTAssertTrue(saved.waitForExistence(timeout: 5), "Guardar el saldo no enseñó el ✓")
        XCTAssertTrue(waitFor(NSPredicate(format: "value CONTAINS %@", "512,34"), field, timeout: 5),
                      "El campo no se quedó con el saldo nuevo: \(value(field))")
        XCTAssertTrue(waitFor(NSPredicate(format: "exists == false"), saved, timeout: 8), "El ✓ de guardado no se fue")
    }

    // MARK: - La pantalla de un banco: hoja sobre cabecera oscura (B5)

    /// Abre la pantalla de un banco TOCANDO su fila en Ajustes › Bancos (la demo trae Revolut e imagin conectados).
    private func openBank(_ id: String, _ extra: [String] = []) {
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoBanks"] + extra)
        let row = app.buttons["settings-bank-\(id)"]
        XCTAssertTrue(row.waitForExistence(timeout: 20), "Falta la fila del banco en Ajustes")
        XCTAssertTrue(waitFor(hittable, row, timeout: 5), "La fila del banco no se puede tocar")
        row.tap()
    }

    /// Arrastra la pantalla en vertical, despacio y sin inercia (fracciones del alto de la pantalla).
    private func drag(from: CGFloat, to: CGFloat) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: 500, thenHoldForDuration: 0.3)
    }

    /// Abierta desde Ajustes, la cabecera (banco, saldo, estado, acciones) está desde el principio; la hoja enseña los
    /// últimos movimientos de ESE banco; al subir la hoja, el título pequeño «Banco · saldo» se acopla en la barra y el
    /// saldo grande deja de verse; al bajarla, vuelve. Y todo lo de antes sigue en la pantalla.
    func testBankHeaderDocksTitle() throws {
        openBank("rev")
        let balance = element("bank-header-balance")
        XCTAssertTrue(balance.waitForExistence(timeout: 10), "La cabecera del banco no enseña su saldo")
        XCTAssertTrue(waitFor(hittable, balance, timeout: 5), "El saldo grande no está a la vista")
        XCTAssertTrue(balance.label.hasPrefix("Saldo de Revolut: "), "El saldo no dice de quién es: \(balance.label)")
        XCTAssertTrue(balance.label.hasSuffix(" euros"), "El saldo no dice su importe: \(balance.label)")
        let spoken = balance.label.replacingOccurrences(of: "Saldo de Revolut: ", with: "")
        let mini = element("bank-mini-title")
        XCTAssertFalse(mini.exists, "El título pequeño ya está en la barra con la hoja abajo: \(mini.exists ? mini.debugDescription : "")")
        XCTAssertTrue(app.staticTexts["Actualizado hace 5 min · exacto"].exists, "Falta el estado del banco en la cabecera")
        XCTAssertTrue(app.buttons["Actualizar ahora"].isHittable, "Falta «Actualizar ahora»")
        XCTAssertTrue(app.buttons["bank-import-statement"].isHittable, "Falta «Importar extracto»")

        // La hoja: «Movimientos» y los últimos de Revolut (como mucho ocho), ninguno de otro banco.
        XCTAssertTrue(element("bank-movements-title").waitForExistence(timeout: 5), "La hoja no tiene «Movimientos»")
        let rows = app.buttons.matching(identifier: "movementRow")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), "La hoja no enseña movimientos")
        let labels = rows.allElementsBoundByIndex.map { $0.label }
        XCTAssertLessThanOrEqual(labels.count, 8, "La hoja enseña más de ocho movimientos")
        XCTAssertEqual(labels.filter { $0.contains("imagin") || $0.contains("Trade Republic") }, [],
                       "La hoja de Revolut enseña movimientos de otro banco")

        // Sube la hoja: el título pequeño se acopla y el saldo grande ya no se ve.
        drag(from: 0.72, to: 0.18)
        XCTAssertTrue(mini.waitForExistence(timeout: 5), "Al subir la hoja no aparece el título pequeño")
        // Va en la barra de arriba: por encima de donde estaba el saldo grande y dentro de la pantalla.
        XCTAssertLessThan(mini.frame.maxY, 130, "El título pequeño no está en la barra: \(mini.frame)")
        XCTAssertGreaterThan(mini.frame.minY, 30, "El título pequeño queda bajo la barra de estado: \(mini.frame)")
        XCTAssertEqual(mini.label, "Revolut, \(spoken)", "El título pequeño no dice banco y saldo")
        XCTAssertFalse(balance.exists && balance.isHittable, "El saldo grande sigue a la vista bajo el título pequeño")

        // Baja la hoja: vuelve la cabecera y el título pequeño se va.
        drag(from: 0.30, to: 0.90)
        drag(from: 0.30, to: 0.90)
        XCTAssertTrue(waitFor(hittable, balance, timeout: 8), "Al bajar la hoja el saldo grande no vuelve")
        XCTAssertTrue(waitFor(NSPredicate(format: "exists == false"), mini, timeout: 5), "El título pequeño sigue con la hoja abajo")

        // Una fila abre su movimiento (la hoja única de la app) y se cierra.
        let first = rows.firstMatch
        XCTAssertTrue(waitFor(hittable, first, timeout: 5), "La primera fila no se puede tocar")
        first.tap()
        let close = app.buttons["Cerrar"]
        XCTAssertTrue(close.waitForExistence(timeout: 8), "Tocar un movimiento no abrió su detalle")
        close.tap()
        XCTAssertTrue(waitFor(hittable, balance, timeout: 8), "No volvió a la pantalla del banco")
        // Lo de siempre sigue en la pantalla.
        XCTAssertTrue(app.buttons["Desconectar"].exists, "Falta «Desconectar»")
        XCTAssertTrue(app.buttons["Olvidar clave y conexiones"].exists, "Falta «Olvidar clave y conexiones»")
        XCTAssertTrue(app.staticTexts["Primera actualización: últimos 12 meses (lo que dé el banco)"].exists, "Falta el historial")
    }

    /// Si una tarjeta viene volando desde Inicio, la cabecera la espera; pero si no llega (hoy nadie la hace aterrizar),
    /// la cabecera aparece igual: la pantalla nunca se queda sin cabecera. A cámara lenta ×8 el plazo dura unos 8 s.
    func testBankHeaderWaitsForAFlightButNeverStaysHidden() throws {
        openBank("rev", ["-MiBancoDemoFlightRequest", "-MiBancoMotionScale", "8"])
        XCTAssertTrue(element("bank-movements-title").waitForExistence(timeout: 10), "No se abrió la pantalla del banco")
        let balance = element("bank-header-balance")
        XCTAssertFalse(balance.exists, "Con una tarjeta en vuelo la cabecera no la esperó")
        XCTAssertFalse(app.buttons["bank-import-statement"].exists, "Con una tarjeta en vuelo las acciones ya estaban")
        XCTAssertTrue(balance.waitForExistence(timeout: 30), "La cabecera se quedó escondida: el vuelo no aterrizó y no venció el plazo")
        XCTAssertTrue(waitFor(hittable, app.buttons["bank-import-statement"], timeout: 10), "Las acciones no volvieron")
    }

    /// Con el ojo cerrado, la pantalla del banco no enseña ni dice ningún importe: ni en la cabecera, ni en la hoja, ni
    /// en el título pequeño.
    func testPrivateModeHidesAmountsInBankScreen() throws {
        continueAfterFailure = true
        openBank("rev", ["-MiBancoDemoPrivate"])
        let balance = element("bank-header-balance")
        XCTAssertTrue(balance.waitForExistence(timeout: 10), "La cabecera del banco no tiene saldo")
        XCTAssertEqual(balance.label, "Saldo de Revolut: importe oculto")
        XCTAssertTrue(app.buttons.matching(identifier: "movementRow").firstMatch.waitForExistence(timeout: 5),
                      "La hoja no enseña movimientos")
        XCTAssertEqual(visibleAmounts(), [], "La pantalla del banco enseña importes con el ojo cerrado")
        drag(from: 0.72, to: 0.18)
        let mini = element("bank-mini-title")
        XCTAssertTrue(mini.waitForExistence(timeout: 5), "Al subir la hoja no aparece el título pequeño")
        XCTAssertEqual(mini.label, "Revolut, importe oculto")
        XCTAssertEqual(visibleAmounts(), [], "Con la hoja arriba se ven importes con el ojo cerrado")
    }

    // MARK: - Conectar un banco: pasos con porcentaje y «conectado» (B6, B7)

    /// «Paso 2 de 3, 45 por ciento» -> (2, 45).
    private func stepAndPercent(_ label: String) -> (step: Int, percent: Int)? {
        let numbers = label.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
        guard label.hasPrefix("Paso "), numbers.count == 3 else { return nil }
        return (numbers[0], numbers[2])
    }

    /// El trámite entero con el banco de mentira de la demo: los tres pasos se recorren en orden, el porcentaje nunca
    /// baja, nunca alcanza el tope de un paso que sigue en marcha (34, 67, 99) y solo llega a 100 con el banco conectado;
    /// entonces sale «imagin, conectado» con su saldo, la lista se llena (esqueleto y luego filas) y «Listo» lo cierra.
    func testConnectStepsReachDone() throws {
        openBank("ima", ["-MiBancoDemoConnectScript", "-MiBancoDemoConnectStep", "4", "-MiBancoDemoConnectFill", "6"])
        let renew = app.buttons["Renovar conexión"]
        XCTAssertTrue(renew.waitForExistence(timeout: 10), "Falta «Renovar conexión»")
        XCTAssertFalse(element("bank-steps-percent").exists, "Los pasos ya estaban antes de empezar")
        renew.tap()

        let percent = element("bank-steps-percent")
        XCTAssertTrue(percent.waitForExistence(timeout: 5), "Renovar no enseñó los pasos con su porcentaje")
        XCTAssertTrue(app.staticTexts["Esperando a imagin…"].waitForExistence(timeout: 3), "Falta lo que se está haciendo")
        let title = element("bank-connected-title")
        let floors = [1: 0, 2: 34, 3: 67]
        let caps = [1: 34, 2: 67, 3: 99]
        var seen: Set<Int> = []
        var last = (step: 0, percent: -1)
        let deadline = Date().addingTimeInterval(40)
        while !title.exists, Date() < deadline {
            guard percent.exists, let now = stepAndPercent(percent.label) else { continue }
            guard now.percent < 100 else { break }
            XCTAssertGreaterThanOrEqual(now.percent, floors[now.step] ?? 0, "El porcentaje va por debajo de su paso: \(now)")
            XCTAssertLessThan(now.percent, caps[now.step] ?? 0, "El porcentaje alcanzó el tope de un paso sin terminar: \(now)")
            XCTAssertGreaterThanOrEqual(now.step, last.step, "Los pasos fueron hacia atrás: \(last) -> \(now)")
            XCTAssertGreaterThanOrEqual(now.percent, last.percent, "El porcentaje bajó: \(last) -> \(now)")
            seen.insert(now.step)
            last = now
        }
        XCTAssertTrue(title.waitForExistence(timeout: 10), "El trámite no llegó a «conectado»")
        XCTAssertEqual(seen, [1, 2, 3], "No se vieron los tres pasos en marcha: \(seen.sorted())")
        XCTAssertEqual(title.label, "imagin, conectado")
        let balance = element("bank-connected-balance")
        XCTAssertTrue(balance.waitForExistence(timeout: 5), "«Conectado» no enseña el saldo")
        XCTAssertTrue(balance.label.hasPrefix("Saldo: "), "El saldo no dice lo que es: \(balance.label)")
        XCTAssertTrue(balance.label.hasSuffix(" euros"), "El saldo no dice su importe: \(balance.label)")
        XCTAssertFalse(percent.exists, "Los pasos siguen a la vista con el banco ya conectado")

        // La lista se llena por primera vez: esqueleto (sin datos) y, después, las filas.
        let skeleton = element("skeleton-rows")
        XCTAssertTrue(skeleton.waitForExistence(timeout: 3), "Tras conectar no se ve el esqueleto de la lista")
        XCTAssertFalse(app.buttons.matching(identifier: "movementRow").firstMatch.exists, "Hay filas debajo del esqueleto")
        XCTAssertTrue(waitFor(NSPredicate(format: "exists == false"), skeleton, timeout: 15), "El esqueleto no se fue")
        XCTAssertTrue(app.buttons.matching(identifier: "movementRow").firstMatch.waitForExistence(timeout: 5),
                      "Tras el esqueleto no llegaron las filas")

        let done = app.buttons["bank-connected-done"]
        XCTAssertTrue(waitFor(hittable, done, timeout: 8), "«Listo» no se puede tocar")
        done.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "exists == false"), title, timeout: 5), "«Listo» no cerró «conectado»")
        XCTAssertTrue(element("bank-header-balance").waitForExistence(timeout: 5), "No volvió la cabecera de siempre")
        XCTAssertTrue(waitFor(hittable, app.buttons["bank-import-statement"], timeout: 5), "No volvieron las acciones")
    }

    /// «Ver movimientos» cierra «conectado» y sube la hoja (el título pequeño queda acoplado).
    func testConnectedShowMovementsDocksTheSheet() throws {
        openBank("ima", ["-MiBancoDemoConnectScript", "-MiBancoDemoConnectStep", "0.4", "-MiBancoDemoConnectFill", "0.5"])
        let renew = app.buttons["Renovar conexión"]
        XCTAssertTrue(renew.waitForExistence(timeout: 10), "Falta «Renovar conexión»")
        renew.tap()
        let show = app.buttons["bank-connected-show"]
        XCTAssertTrue(show.waitForExistence(timeout: 15), "El trámite no llegó a «conectado»")
        XCTAssertTrue(waitFor(hittable, show, timeout: 8), "«Ver movimientos» no se puede tocar")
        show.tap()
        XCTAssertTrue(element("bank-mini-title").waitForExistence(timeout: 8), "«Ver movimientos» no subió la hoja")
        XCTAssertFalse(element("bank-connected-title").exists, "«Conectado» sigue abierto")
    }

    /// Con el ojo cerrado, «conectado» no enseña ni dice el saldo.
    func testPrivateModeHidesTheConnectedBalance() throws {
        openBank("ima", ["-MiBancoDemoConnectScript", "-MiBancoDemoConnectStep", "0.4", "-MiBancoDemoPrivate"])
        let renew = app.buttons["Renovar conexión"]
        XCTAssertTrue(renew.waitForExistence(timeout: 10), "Falta «Renovar conexión»")
        renew.tap()
        let balance = element("bank-connected-balance")
        XCTAssertTrue(balance.waitForExistence(timeout: 15), "El trámite no llegó a «conectado»")
        XCTAssertEqual(balance.label, "Saldo: importe oculto")
        Thread.sleep(forTimeInterval: 2.5)
        XCTAssertEqual(visibleAmounts(), [], "«Conectado» enseña importes con el ojo cerrado")
    }

    // MARK: - Bienvenida (B8)

    /// La bienvenida llega con todas sus piezas (título, texto, saldos y «Seguir», que se puede tocar) y, con el ojo
    /// cerrado, un saldo ya escrito y sin editar es la máscara: ni se enseña ni se dice.
    func testWelcomeArrivesAndMasksATypedBalance() throws {
        launch(["-MiBancoDemoOnboarding", "1", "-MiBancoDemoPrivate"])
        XCTAssertTrue(app.staticTexts["Tus saldos"].waitForExistence(timeout: 20), "La bienvenida no enseña «Tus saldos»")
        let next = app.buttons["onboarding-next-1"]
        XCTAssertTrue(next.waitForExistence(timeout: 8), "La bienvenida no tiene «Seguir»")
        XCTAssertTrue(waitFor(hittable, next, timeout: 8), "«Seguir» no se puede tocar")
        let field = app.textFields["Saldo de Revolut"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Falta el saldo de Revolut")
        field.tap()
        field.typeText("340,20")
        XCTAssertTrue(waitFor(NSPredicate(format: "value == %@", "340,20"), field, timeout: 5),
                      "Mientras se escribe, el campo no enseña lo escrito: \(value(field))")
        // Se pasa a otro campo: el de Revolut deja de editarse y, con el ojo cerrado, se tapa.
        let other = app.textFields["Saldo de imagin"]
        XCTAssertTrue(other.waitForExistence(timeout: 5), "Falta el saldo de imagin")
        other.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "value == %@", "importe oculto"), field, timeout: 5),
                      "Con el ojo cerrado, el saldo escrito se sigue leyendo: \(value(field))")
        XCTAssertEqual(visibleAmounts(), [], "La bienvenida enseña importes con el ojo cerrado")
    }

    // MARK: - Importar un extracto: pasos y vista previa (B6)

    /// Primero los pasos (Leer, Revisar) y DESPUÉS la vista previa; el porcentaje se queda en 67 mientras se espera al
    /// dueño, sube al tocar «Importar» y la pantalla vuelve a la del banco.
    func testImportStepsThenPreview() throws {
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoImport", "-MiBancoDemoImportSlow"])
        let percent = element("import-steps-percent")
        XCTAssertTrue(percent.waitForExistence(timeout: 20), "La importación no enseña sus pasos")
        let summary = app.staticTexts["import-summary"]
        let confirm = app.buttons["import-confirm"]
        // Mientras se lee y se revisa (2 s por paso en esta prueba) no hay vista previa ni botón.
        var early: Set<Int> = []
        let reading = Date().addingTimeInterval(3)
        while Date() < reading, !summary.exists {
            guard let now = stepAndPercent(percent.label) else { continue }
            XCTAssertLessThan(now.percent, 67, "El porcentaje pasó de 67 antes de la vista previa: \(now)")
            XCTAssertLessThan(now.step, 3, "El tercer paso empezó antes de la vista previa")
            early.insert(now.step)
        }
        XCTAssertTrue(early.contains(1), "No se vio el paso «Leer» en marcha: \(early.sorted()) · etiqueta: \(percent.label)")
        XCTAssertFalse(summary.exists, "La vista previa salió antes de terminar los pasos")
        XCTAssertFalse(confirm.exists, "«Importar» salió antes de terminar los pasos")

        XCTAssertTrue(summary.waitForExistence(timeout: 10), "Tras los pasos no llegó la vista previa")
        XCTAssertEqual(summary.label, "3 movimientos nuevos, 3 filas ignoradas")
        XCTAssertEqual(percent.label, "Paso 3 de 3, 67 por ciento", "Esperando al dueño el porcentaje no está en 67")
        Thread.sleep(forTimeInterval: 2.5)
        XCTAssertEqual(percent.label, "Paso 3 de 3, 67 por ciento", "El porcentaje subió solo, sin tocar «Importar»")

        XCTAssertTrue(waitFor(hittable, confirm, timeout: 5), "«Importar» no se puede tocar")
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()
        let bank = app.buttons["bank-import-statement"]
        var afterTap: [Int] = []
        let leaving = Date().addingTimeInterval(12)
        while Date() < leaving, !bank.exists {
            guard percent.exists, let now = stepAndPercent(percent.label) else { continue }
            XCTAssertGreaterThanOrEqual(now.percent, 67, "El porcentaje bajó de 67 al importar: \(now)")
            XCTAssertGreaterThanOrEqual(now.percent, afterTap.last ?? 0, "El porcentaje bajó al importar")
            afterTap.append(now.percent)
        }
        XCTAssertTrue(bank.waitForExistence(timeout: 8), "Tras importar no volvió a la pantalla del banco")
        XCTAssertTrue(afterTap.contains { $0 > 67 }, "Al importar el porcentaje no se movió de 67: \(afterTap)")
    }
}
