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
        let chart = element("gasto.grafico")
        XCTAssertTrue(chart.waitForExistence(timeout: 5), "Gasto no tiene el gráfico del mes")
        XCTAssertTrue(chart.label.hasPrefix("Gráfico del gasto de "), "El gráfico no dice qué es: \(chart.label)")
        XCTAssertTrue(value(chart).contains(" euros frente a "), "El gráfico no dice sus importes: \(value(chart))")
        // Lo que dice el gráfico es el total del mes.
        let spent = total.label.components(separatedBy: ": ").last ?? ""
        XCTAssertTrue(value(chart).hasPrefix(spent), "El gráfico («\(value(chart))») y el total («\(spent)») no coinciden")
        // Mes anterior: otro gráfico (otro mes en su etiqueta) y otro total.
        let before = chart.label
        let previous = app.buttons["gasto.mesAnterior"]
        XCTAssertTrue(previous.isHittable)
        previous.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "label != %@", before), chart, timeout: 8),
                      "El gráfico no cambió con el mes: \(chart.label)")
        let pastSpent = element("gasto.total").label.components(separatedBy: ": ").last ?? ""
        XCTAssertTrue(waitFor(NSPredicate(format: "value BEGINSWITH %@", pastSpent), chart, timeout: 8),
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
        openGasto(["-MiBancoDemoPrivate"])
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
        // Ni un dígito pegado a una coma decimal en ninguna etiqueta (un importe sin su «€»).
        let decimals = app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES %@", ".*[0-9],[0-9]{2}.*"))
        XCTAssertEqual(decimals.allElementsBoundByIndex.map { $0.label }, [], "Próximos cobros enseña cifras con el ojo cerrado")
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
}
