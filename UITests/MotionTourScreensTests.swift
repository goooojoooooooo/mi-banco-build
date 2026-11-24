import XCTest

/// Ráfagas de movimiento del flujo «Pantallas» (Ajustes, Gasto, presupuestos, suscripciones, Avisos, próximos cobros).
/// Cada prueba llega al momento con toques de verdad, lo dispara y saca su hoja de contacto a cámara lenta (×4); las que
/// llevan importes se repiten con el ojo cerrado (`-MiBancoDemoPrivate`): en ningún fotograma puede verse una cifra.
/// Las aserciones son las justas para saber que la hoja enseña lo que dice (que la pantalla es la que es).
final class MotionTourScreensTests: MotionTourCase {

    // MARK: Ayudas

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Arrastra la pantalla hacia arriba un tercio, despacio y sin inercia, hasta que el elemento se pueda tocar.
    private func scrollDown(to el: XCUIElement, drags: Int = 16) {
        var left = drags
        while left > 0 && !(el.exists && el.isHittable) {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.68))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.36))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: 500, thenHoldForDuration: 0.2)
            left -= 1
        }
    }

    /// Espera a Inicio y a que el arranque termine de asentarse.
    private func waitForHome() {
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 20), "Inicio no aparece")
        Thread.sleep(forTimeInterval: 3)
    }

    /// Toca una pestaña como entra de verdad en la barra de cristal de iOS 26: una pulsación corta (un toque sintético
    /// seco muchas veces no entra).
    private func press(tab name: String) {
        app.tabBars.buttons[name].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).press(forDuration: 0.25)
    }

    /// Abre una pestaña y espera a verla; si no entra, lo intenta otra vez (pulsación corta y, si no, toque).
    private func open(tab name: String, until target: XCUIElement) {
        for _ in 0..<3 {
            press(tab: name)
            if target.waitForExistence(timeout: 6) { return }
            app.tabBars.buttons[name].tap()
            if target.waitForExistence(timeout: 6) { return }
        }
        XCTFail("La pestaña \(name) no se abre")
    }

    /// Entra en una pestaña, vuelve a Inicio y deja todo asentado: así se sabe que la barra toma el toque antes de la
    /// ráfaga. La ráfaga se saca en la SEGUNDA entrada, que repite la misma entrada por capas que la primera (lo que el
    /// dueño ve cada vez que cambia de pestaña).
    private func rehearse(tab name: String, until target: XCUIElement) {
        waitForHome()
        open(tab: name, until: target)
        Thread.sleep(forTimeInterval: 1.5)
        open(tab: "Inicio", until: app.staticTexts["Tu dinero"])
        Thread.sleep(forTimeInterval: 3)
    }

    /// Gasto abierto por argumento y ya asentado.
    private func launchGasto(_ extra: [String] = []) {
        launch(["-MiBancoDemoScreen", "gasto"] + extra)
        XCTAssertTrue(element("gasto.total").waitForExistence(timeout: 20), "No se ve Gasto")
        Thread.sleep(forTimeInterval: 3)
    }

    // MARK: - Ajustes › Animaciones

    /// De «Expresivo» a «Sutil»: el indicador del segmentado cruza dos casillas y se aplasta al correr.
    func testSettingsMotionLevel() throws {
        launch(["-MiBancoDemoScreen", "ajustes"])
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 20), "No se ve Ajustes")
        let subtle = app.buttons["Sutil"]
        scrollDown(to: subtle)
        XCTAssertTrue(subtle.isHittable, "«Sutil» no se puede tocar")
        XCTAssertTrue(app.buttons["Expresivo"].isSelected, "La app no se estrena en «Expresivo»")
        Thread.sleep(forTimeInterval: 1)
        subtle.tap()
        burst("settings-motion-level", frames: 12, every: 0.2)
        XCTAssertTrue(subtle.isSelected, "«Sutil» no quedó elegido")
    }

    // MARK: - Gasto: total que rueda, barras que se llenan, gráfico que se dibuja

    /// Entrar en la pestaña Gasto: el total rueda desde 0, la previsión cuenta, el gráfico se dibuja y las barras de las
    /// categorías se llenan una tras otra.
    private func spendingMonth(_ name: String, extra: [String], frames: Int, every: TimeInterval) {
        launch(extra)
        rehearse(tab: "Gasto", until: element("gasto.total"))
        press(tab: "Gasto")
        burst(name, frames: frames, every: every)
        XCTAssertTrue(element("gasto.total").waitForExistence(timeout: 10), "La ráfaga no es de Gasto: la pestaña no se abrió")
        XCTAssertTrue(element("gasto.grafico").exists, "Gasto no tiene gráfico")
    }

    func testSpendingMonth() throws {
        spendingMonth("spending-month", extra: [], frames: 30, every: 0.3)
    }

    /// Lo mismo con el ojo cerrado: puntos en vez de cifras en todos los fotogramas, y «•••» en la rejilla del gráfico.
    func testSpendingMonthEye() throws {
        spendingMonth("spending-month-eye", extra: ["-MiBancoDemoPrivate"], frames: 30, every: 0.3)
    }

    /// Con Reducir movimiento: sin rodar ni trazar; todo aparece ya en su sitio (fundidos).
    func testSpendingMonthReduce() throws {
        spendingMonth("spending-month-reduce", extra: ["-MiBancoReduceMotion"], frames: 12, every: 0.3)
    }

    /// Cambiar de mes: el total rueda del importe de un mes al del otro y el gráfico y las barras del mes nuevo se dibujan.
    func testSpendingMonthChange() throws {
        launchGasto()
        let previous = app.buttons["gasto.mesAnterior"]
        XCTAssertTrue(previous.isHittable, "No se puede ir al mes anterior")
        previous.tap()
        burst("spending-month-change", frames: 18, every: 0.3)
    }

    // MARK: - Presupuestos: cruzar el 90 %

    /// «412,30 euros» -> 41230 (de la etiqueta de la barra).
    private func spentCents(in label: String) -> Int? {
        guard let match = label.range(of: #": [0-9.]+,[0-9]{2} euros de "#, options: .regularExpression) else { return nil }
        return Int(label[match].filter { $0.isNumber })
    }

    /// Lo gastado este mes en la demo, leído de la barra del presupuesto del mes con el ojo abierto.
    private func demoSpentThisMonth() -> Int {
        launch(["-MiBancoDemoScreen", "gasto", "-MiBancoDemoBudgets"])
        let bar = element("presupuestos.mes.barra")
        XCTAssertTrue(bar.waitForExistence(timeout: 20), "No se ve Presupuestos")
        let spent = spentCents(in: bar.label) ?? 0
        XCTAssertGreaterThan(spent, 1_000, "No se lee lo gastado en «\(bar.label)»")
        app.terminate()
        return spent
    }

    private func typeLimit(_ field: XCUIElement, cents: Int, commit: Bool) {
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        let text = "\(cents / 100)," + String(format: "%02d", cents % 100)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 14) + text + (commit ? "\n" : ""))
    }

    /// Se baja el presupuesto del mes hasta dejarlo al 95 %: la barra salta hacia la derecha, pasa a ámbar y da un pulso.
    private func budgetLimit(_ name: String, extra: [String]) {
        let spent = demoSpentThisMonth()
        launch(["-MiBancoDemoScreen", "gasto", "-MiBancoDemoBudgets"] + extra)
        let field = app.textFields["presupuestos.mes"]
        XCTAssertTrue(field.waitForExistence(timeout: 20), "No se ve Presupuestos")
        Thread.sleep(forTimeInterval: 3)
        // Punto de partida: al 50 %, en blanco y ya asentada.
        typeLimit(field, cents: spent * 2, commit: true)
        Thread.sleep(forTimeInterval: 5)
        // El límite nuevo, escrito; la ráfaga empieza al pulsar Intro.
        typeLimit(field, cents: spent * 100 / 95, commit: false)
        Thread.sleep(forTimeInterval: 0.5)
        field.typeText("\n")
        burst(name, frames: 20, every: 0.25)
    }

    func testBudgetLimit() throws {
        budgetLimit("budget-limit", extra: [])
    }

    /// Con el ojo cerrado: la barra hace lo mismo y «77 de 90 €  85 %» sigue tapado en todos los fotogramas.
    func testBudgetLimitEye() throws {
        budgetLimit("budget-limit-eye", extra: ["-MiBancoDemoPrivate"])
    }

    // MARK: - Suscripciones: los totales ruedan y «HOY» salta

    private func subscriptions(_ name: String, extra: [String]) {
        launchGasto(["-MiBancoDemoChargeToday"] + extra)
        let link = element("gasto.suscripciones")
        scrollDown(to: link)
        XCTAssertTrue(link.isHittable, "No se puede abrir Suscripciones")
        link.tap()
        burst(name, frames: 16, every: 0.25)
        XCTAssertTrue(element("suscripciones.total").waitForExistence(timeout: 10), "La ráfaga no es de Suscripciones")
    }

    func testSubscriptions() throws {
        subscriptions("subscriptions", extra: [])
    }

    func testSubscriptionsEye() throws {
        subscriptions("subscriptions-eye", extra: ["-MiBancoDemoPrivate"])
    }

    // MARK: - Avisos: el importe de cada aviso rueda

    private func alerts(_ name: String, extra: [String]) {
        launch(extra)
        rehearse(tab: "Avisos", until: app.navigationBars["Avisos"])
        press(tab: "Avisos")
        burst(name, frames: 14, every: 0.3)
        XCTAssertTrue(app.navigationBars["Avisos"].waitForExistence(timeout: 10), "La ráfaga no es de Avisos: la pestaña no se abrió")
    }

    func testAlertsCounter() throws {
        alerts("alerts-counter", extra: [])
    }

    func testAlertsCounterEye() throws {
        alerts("alerts-counter-eye", extra: ["-MiBancoDemoPrivate"])
    }

    // MARK: - Próximos cobros: la entrada de siempre

    /// Los días entran uno tras otro: cada bloque sube y aparece (la entrada estándar, con los tiempos del kit).
    private func upcomingCalendar(_ name: String, extra: [String]) {
        launchGasto(extra)
        let link = element("gasto.proximos")
        scrollDown(to: link)
        XCTAssertTrue(link.isHittable, "No se puede abrir Próximos cobros")
        link.tap()
        burst(name, frames: 12, every: 0.25)
        XCTAssertTrue(element("upcoming-calendar-scroll").waitForExistence(timeout: 10), "La ráfaga no es de Próximos cobros")
    }

    func testUpcomingCalendar() throws {
        upcomingCalendar("upcoming-calendar", extra: [])
    }

    /// Con el ojo cerrado: el cobro y los saldos previstos son «•••,•• €» en todos los fotogramas de la entrada.
    func testUpcomingCalendarEye() throws {
        upcomingCalendar("upcoming-calendar-eye", extra: ["-MiBancoDemoPrivate"])
    }
}
