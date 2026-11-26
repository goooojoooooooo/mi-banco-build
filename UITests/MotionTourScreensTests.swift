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

    /// Abre la app y espera a que la capa del arranque se haya quitado: mientras está, un toque la salta en vez de llegar a
    /// la pantalla, y lo que se anime debajo no se ve. A cámara lenta el arranque dura varios segundos.
    override func launch(_ extra: [String] = [], scale: Double = 4) {
        super.launch(extra, scale: scale)
        waitForLaunchToEnd()
    }

    private func waitForLaunchToEnd() {
        let layer = element("launch-layer")
        _ = layer.waitForExistence(timeout: 3)
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: layer)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 120), .completed, "El arranque no terminó")
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

    // MARK: - Avisos: los avisos entran desde la derecha; el umbral de una regla aparece

    /// Entrar en la pestaña Avisos: cada aviso llega desde 40 pt a la derecha, uno tras otro, y su importe rueda.
    func testAlertsEnter() throws {
        alertsEnter("alerts-enter", extra: [])
    }

    func testAlertsEnterEye() throws {
        alertsEnter("alerts-enter-eye", extra: ["-MiBancoDemoPrivate"])
    }

    /// A cámara lenta ×10 (no ×4): el primer fotograma llega más de un segundo después del toque y a ×4 la entrada ya
    /// estaba casi acabada.
    private func alertsEnter(_ name: String, extra: [String]) {
        launch(extra, scale: 10)
        rehearse(tab: "Avisos", until: app.navigationBars["Avisos"])
        press(tab: "Avisos")
        burst(name, frames: 18, every: 0.3)
        XCTAssertTrue(app.navigationBars["Avisos"].waitForExistence(timeout: 10), "La ráfaga no es de Avisos: la pestaña no se abrió")
    }

    /// Encender «Saldo bajo»: la fila de su umbral aparece con el muelle `row` (con el ojo cerrado, el umbral es la máscara).
    private func alertsRule(_ name: String, extra: [String]) {
        launch(["-MiBancoDemoScreen", "avisos", "-MiBancoDemoRules"] + extra)
        XCTAssertTrue(app.navigationBars["Avisos"].waitForExistence(timeout: 20), "No se ve Avisos")
        let toggle = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Saldo bajo")).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "Falta el interruptor de «Saldo bajo»")
        Thread.sleep(forTimeInterval: 3)
        scrollDown(to: toggle)
        XCTAssertTrue(toggle.isHittable, "El interruptor no se puede tocar")
        toggle.tap()
        Thread.sleep(forTimeInterval: 4)
        toggle.tap()
        burst(name, frames: 12, every: 0.2)
        XCTAssertTrue(app.textFields["Avisar por debajo de"].waitForExistence(timeout: 8), "La ráfaga no enseña el umbral")
    }

    func testAlertsRule() throws {
        alertsRule("alerts-rule", extra: [])
    }

    func testAlertsRuleEye() throws {
        alertsRule("alerts-rule-eye", extra: ["-MiBancoDemoPrivate"])
    }

    // MARK: - Ajustes: el ✓ de un saldo guardado; las filas de Bancos entran

    /// Guardar un saldo a mano: el ✓ se traza junto al campo y da un pequeño bote.
    /// A cámara lenta ×12: el ✓ aparece (fundido), da su bote y se queda; a ×4 todo eso pasaba antes del primer fotograma.
    private func settingsSave(_ name: String, extra: [String]) {
        launch(["-MiBancoDemoScreen", "ajustes"] + extra, scale: 12)
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 20), "No se ve Ajustes")
        let field = app.textFields["Saldo de Revolut"]
        scrollDown(to: field)
        XCTAssertTrue(field.isHittable, "El saldo de Revolut no se puede tocar")
        Thread.sleep(forTimeInterval: 1)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 14) + "512,34")
        Thread.sleep(forTimeInterval: 0.5)
        field.typeText("\n")
        burst(name, frames: 14, every: 0.3)
    }

    func testSettingsSave() throws {
        settingsSave("settings-save", extra: [])
    }

    /// Con el ojo cerrado: al soltar el campo, el saldo vuelve a ser la máscara; el ✓ salta igual.
    func testSettingsSaveEye() throws {
        settingsSave("settings-save-eye", extra: ["-MiBancoDemoPrivate"])
    }

    /// Entrar en Ajustes por primera vez: las filas de Bancos llegan una tras otra (a cámara lenta ×10). Se ensaya con
    /// otra pestaña (Gasto) para saber que la barra toma el toque; Ajustes no se ha abierto aún cuando empieza la ráfaga.
    func testBanksList() throws {
        launch(["-MiBancoDemoBanks"], scale: 10)
        rehearse(tab: "Gasto", until: element("gasto.total"))
        press(tab: "Ajustes")
        burst("banks-list", frames: 16, every: 0.3)
        XCTAssertTrue(app.buttons["settings-bank-rev"].waitForExistence(timeout: 10), "La ráfaga no es de Ajustes")
    }

    // MARK: - La pantalla de un banco: la hoja sube sobre la cabecera oscura

    /// Ajustes con los bancos de la demo conectados y la fila del banco lista para tocar.
    private func bankRow(_ id: String, _ extra: [String]) -> XCUIElement {
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoBanks"] + extra)
        let row = app.buttons["settings-bank-\(id)"]
        XCTAssertTrue(row.waitForExistence(timeout: 20), "Falta la fila del banco en Ajustes")
        Thread.sleep(forTimeInterval: 3)
        XCTAssertTrue(row.isHittable, "La fila del banco no se puede tocar")
        return row
    }

    /// Abrir el banco: la cabecera sube 12 pt, su saldo cuenta desde 0 y la hoja llega desde 260 pt más abajo.
    private func bankSheet(_ name: String, extra: [String], frames: Int = 16) {
        let row = bankRow("rev", extra)
        row.tap()
        burst(name, frames: frames, every: 0.25)
        XCTAssertTrue(element("bank-movements-title").waitForExistence(timeout: 10), "La ráfaga no es de la pantalla del banco")
    }

    func testBankSheet() throws {
        bankSheet("bank-sheet", extra: [])
    }

    func testBankSheetEye() throws {
        bankSheet("bank-sheet-eye", extra: ["-MiBancoDemoPrivate"])
    }

    /// En «Sutil»: recorridos más cortos y casi sin rebote.
    func testBankSheetSubtle() throws {
        bankSheet("bank-sheet-subtle", extra: ["-MiBancoMotionLevel", "subtle"])
    }

    /// Con Reducir movimiento: nada viaja; la cabecera y la hoja se funden.
    func testBankSheetReduce() throws {
        bankSheet("bank-sheet-reduce", extra: ["-MiBancoReduceMotion"], frames: 10)
    }

    /// Un fotograma de una hoja que no depende del tiempo sino de lo que se ha desplazado: el mismo formato de adjunto
    /// que `burst` («<nombre>-NN_tTTT»), para que el workflow lo ponga en su hoja de contacto.
    private func frame(_ name: String, _ index: Int, since start: Date) {
        let screenshot = app.screenshot()
        let tenths = Int((Date().timeIntervalSince(start) * 10).rounded())
        let attachment = XCTAttachment(screenshot: screenshot, quality: .original)
        attachment.name = "\(name)-" + String(format: "%02d", index) + "_t" + String(format: "%03d", tenths)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func drag(from: CGFloat, to: CGFloat) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to))
        // Despacio y soltando en parado: con más velocidad la lista sigue sola al soltar y se salta medio recorrido.
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: 70, thenHoldForDuration: 0.7)
    }

    /// La hoja sube sobre la cabecera (que se queda atrás, se encoge y se apaga), sus esquinas se cuadran al llegar arriba
    /// y el título pequeño «Banco · saldo» entra en la barra; después baja y la cabecera vuelve. Al soltar a medio camino
    /// la hoja se asienta sola (abajo o acoplada): los fotogramas se sacan seguidos justo después de soltar, así se ve el
    /// asentamiento a medio recorrido (a cámara lenta ×4).
    /// f1 en reposo · f2–f4 un arrastre corto que vuelve abajo · f5–f10 un arrastre largo que se acopla · f11–f16 baja.
    private func bankSheetDock(_ name: String, extra: [String]) {
        let row = bankRow("rev", extra)
        row.tap()
        XCTAssertTrue(element("bank-movements-title").waitForExistence(timeout: 10), "No se abrió la pantalla del banco")
        Thread.sleep(forTimeInterval: 7)
        let start = Date()
        var index = 1
        frame(name, index, since: start)
        let settle = { (count: Int) in
            for _ in 0..<count {
                index += 1
                self.frame(name, index, since: start)
                Thread.sleep(forTimeInterval: 0.12)
            }
        }
        // Un arrastre corto (unos 50 pt, menos de media cabecera): al soltar, vuelve abajo.
        drag(from: 0.62, to: 0.56)
        settle(3)
        // Uno largo (unos 200 pt, más de media cabecera): al soltar, termina de subir y se acopla.
        drag(from: 0.70, to: 0.46)
        settle(6)
        // Y baja: al soltar a medio camino, vuelve abajo y la cabecera vuelve.
        drag(from: 0.36, to: 0.62)
        settle(6)
        XCTAssertTrue(element("bank-header-balance").waitForExistence(timeout: 8), "Al bajar la hoja no volvió la cabecera")
    }

    func testBankSheetDock() throws {
        bankSheetDock("bank-sheet-dock", extra: [])
    }

    func testBankSheetDockEye() throws {
        bankSheetDock("bank-sheet-dock-eye", extra: ["-MiBancoDemoPrivate"])
    }

    /// Con Reducir movimiento la cabecera no viaja ni se encoge: solo se apaga bajo la hoja.
    func testBankSheetDockReduce() throws {
        bankSheetDock("bank-sheet-dock-reduce", extra: ["-MiBancoReduceMotion"])
    }

    // MARK: - Conectar un banco: pasos con porcentaje y «conectado»

    /// «Renovar conexión» con el banco de mentira de la demo: Verificar › Conectar › Importar con su porcentaje (que se
    /// frena antes de cada tope y solo llega a 100 al conectar) y, al final, «imagin, conectado»: el ✓ blanco salta con
    /// su destello, el título, el estado y el saldo llegan uno tras otro, el saldo cuenta desde 0 y los botones suben.
    private func bankConnected(_ name: String, extra: [String], frames: Int = 32) {
        let row = bankRow("ima", ["-MiBancoDemoConnectScript", "-MiBancoDemoConnectStep", "2.4", "-MiBancoDemoConnectFill", "6"] + extra)
        row.tap()
        let renew = app.buttons["Renovar conexión"]
        XCTAssertTrue(renew.waitForExistence(timeout: 10), "Falta «Renovar conexión»")
        Thread.sleep(forTimeInterval: 6)
        XCTAssertTrue(renew.isHittable, "«Renovar conexión» no se puede tocar")
        renew.tap()
        burst(name, frames: frames, every: 0.5)
        XCTAssertTrue(element("bank-connected-title").waitForExistence(timeout: 15), "La ráfaga no llegó a «conectado»")
    }

    func testBankConnected() throws {
        bankConnected("bank-connected", extra: [])
    }

    func testBankConnectedEye() throws {
        bankConnected("bank-connected-eye", extra: ["-MiBancoDemoPrivate"])
    }

    func testBankConnectedSubtle() throws {
        bankConnected("bank-connected-subtle", extra: ["-MiBancoMotionLevel", "subtle"])
    }

    /// Con Reducir movimiento: el porcentaje salta de tope en tope con un fundido, los nodos se funden y el ✓ sigue.
    func testBankConnectedReduce() throws {
        // «conectado» se cierra solo (como con «Listo») 8 s después de aparecer: la segunda ráfaga empieza ANTES de ese
        // cierre y lo graba entero (lote de cierre, ronda 1, m-2).
        bankConnected("bank-connected-reduce", extra: ["-MiBancoReduceMotion", "-MiBancoDemoConnectedDoneAfter", "8"], frames: 28)
        // Y «Listo» con Reducir movimiento: «conectado» se va y vuelve la cabecera de siempre en el acto, sin recorrido
        // de la hoja.
        burst("bank-connected-reduce-listo", frames: 20, every: 0.5)
        XCTAssertTrue(element("bank-header-balance").waitForExistence(timeout: 8), "«Listo» no volvió a la cabecera")
    }

    /// Cerrar el ojo con el interruptor de Ajustes, mirando los saldos (lote de cierre): ningún fotograma tras el toque
    /// enseña una cifra; los saldos son la máscara en el acto.
    func testSettingsEyeClose() throws {
        // El ojo se cierra solo, por el mismo camino que el interruptor, 9 s después de que el interruptor aparezca en
        // pantalla; la ráfaga empieza antes: los primeros fotogramas son el control (cifras a la vista) y después el
        // cierre, fotograma a fotograma (lote de cierre, ronda 1, m-2: antes empezaba después del toque).
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoBanks", "-MiBancoDemoCloseEyeAfter", "9"])
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 20), "No se ve Ajustes")
        let toggle = element("settings-private-mode")
        scrollDown(to: toggle)
        XCTAssertTrue(toggle.waitForExistence(timeout: 8), "Falta el interruptor «Modo privado»")
        // El cierre llega 9 s después de que el interruptor aparezca: la ráfaga (8 s) empieza antes.
        burst("settings-eye-close", frames: 32, every: 0.25)
    }

    /// Editar un saldo con el ojo cerrado (decisión del dueño): Ajustes enfoca el saldo de Trade Republic solo, 9 s
    /// después de que aparezca el interruptor (como un toque) y la ráfaga empieza antes: el campo pasa de la máscara a vacío, nunca a la cifra guardada.
    func testSettingsEditEye() throws {
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoBanks", "-MiBancoDemoPrivate", "-MiBancoDemoFocusBalanceAfter", "9"])
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 20), "No se ve Ajustes")
        let toggle = element("settings-private-mode")
        scrollDown(to: toggle)
        XCTAssertTrue(app.textFields["Saldo de Trade Republic"].exists, "Falta el saldo de Trade Republic")
        // El foco llega 9 s después de que el interruptor aparezca: la ráfaga (8 s) empieza antes.
        burst("settings-edit-eye", frames: 32, every: 0.25)
    }

    /// La pantalla de una categoría con el ojo cerrado (lote de cierre, ronda 1, I-2): total y comparación con máscara.
    func testCategoryDetailEye() throws {
        launch(["-MiBancoDemoScreen", "gasto", "-MiBancoDemoCategory", "compras", "-MiBancoDemoPrivate"])
        XCTAssertTrue(element("categoria.total").waitForExistence(timeout: 20), "No se abrió la categoría")
        burst("category-detail-eye", frames: 12, every: 0.25)
    }

    /// La entrada de la pestaña Gasto (lote de cierre, ronda 1, m-5): se ensaya con Avisos y, ya en Inicio, se toca Gasto.
    func testSpendingTabEntrance() throws {
        launch([], scale: 10)
        rehearse(tab: "Avisos", until: app.navigationBars["Avisos"])
        press(tab: "Gasto")
        burst("spending-tab-entrance", frames: 16, every: 0.3)
        XCTAssertTrue(element("gasto.total").waitForExistence(timeout: 10), "La ráfaga no es de Gasto")
    }

    /// De cerca, el remate (ojo de diseño 14.1–14.3): el tercer paso en marcha, la conexión termina de verdad, la cifra
    /// corre a 100 mientras el tercer nodo se rellena con su ✓ y la línea pasa a «Todo listo»; una pausa; los pasos, el
    /// saldo y el estado se apagan del todo y solo entonces salta el ✓ de «imagin, conectado». Cada paso de la demo dura
    /// 1,6 s: el éxito llega a los 4,8 s del toque; la ráfaga empieza a los 3 s y saca un fotograma cada 0,25 s (×4).
    private func bankConnectFinish(_ name: String, extra: [String]) {
        let row = bankRow("ima", ["-MiBancoDemoConnectScript", "-MiBancoDemoConnectStep", "1.6", "-MiBancoDemoConnectFill", "6"] + extra)
        row.tap()
        let renew = app.buttons["Renovar conexión"]
        XCTAssertTrue(renew.waitForExistence(timeout: 10), "Falta «Renovar conexión»")
        Thread.sleep(forTimeInterval: 6)
        XCTAssertTrue(renew.isHittable, "«Renovar conexión» no se puede tocar")
        renew.tap()
        Thread.sleep(forTimeInterval: 3)
        burst(name, frames: 32, every: 0.25)
        XCTAssertTrue(element("bank-connected-title").waitForExistence(timeout: 15), "La ráfaga no llegó a «conectado»")
    }

    func testBankConnectFinish() throws {
        bankConnectFinish("bank-connect-finish", extra: [])
    }

    func testBankConnectFinishEye() throws {
        bankConnectFinish("bank-connect-finish-eye", extra: ["-MiBancoDemoPrivate"])
    }

    /// Con Reducir movimiento: 100 con un fundido (sin contar), el nodo se funde con su ✓, la misma pausa y el mismo orden.
    func testBankConnectFinishReduce() throws {
        bankConnectFinish("bank-connect-finish-reduce", extra: ["-MiBancoReduceMotion"])
    }

    /// Tras conectar, la lista se llena por primera vez: fichas grises con un brillo que las barre y, al llegar los
    /// movimientos, las filas entran una tras otra.
    func testSkeleton() throws {
        let row = bankRow("ima", ["-MiBancoDemoConnectScript", "-MiBancoDemoConnectStep", "0.5", "-MiBancoDemoConnectFill", "5"])
        row.tap()
        let renew = app.buttons["Renovar conexión"]
        XCTAssertTrue(renew.waitForExistence(timeout: 10), "Falta «Renovar conexión»")
        Thread.sleep(forTimeInterval: 6)
        renew.tap()
        XCTAssertTrue(element("skeleton-rows").waitForExistence(timeout: 10), "Tras conectar no se ve el esqueleto")
        burst("skeleton", frames: 24, every: 0.3)
        XCTAssertTrue(app.buttons.matching(identifier: "movementRow").firstMatch.waitForExistence(timeout: 10),
                      "Tras el esqueleto no llegaron las filas")
    }

    // MARK: - Importar un extracto: pasos, vista previa y «Importar»

    /// Leer › Revisar con su porcentaje y, después, la vista previa: sus piezas entran una tras otra y el recuento cuenta.
    private func importPreview(_ name: String, extra: [String]) {
        // La importación se abre tocando la fila del banco (con el arranque ya terminado): si se abriera sola al arrancar,
        // sus pasos pasarían debajo de la capa del arranque.
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoImportOnOpen"] + extra)
        let row = app.buttons["settings-bank-rev"]
        XCTAssertTrue(row.waitForExistence(timeout: 20), "Falta la fila de Revolut en Ajustes")
        Thread.sleep(forTimeInterval: 2)
        row.tap()
        burst(name, frames: 26, every: 0.3)
        XCTAssertTrue(app.staticTexts["import-summary"].waitForExistence(timeout: 10), "La ráfaga no llegó a la vista previa")
    }

    func testImportPreview() throws {
        importPreview("import-preview", extra: [])
    }

    func testImportPreviewEye() throws {
        importPreview("import-preview-eye", extra: ["-MiBancoDemoPrivate"])
    }

    // MARK: - Bienvenida y guía de avisos

    /// La primera vez: tres líneas de titanio cruzan la pantalla en diagonal, se ensanchan en bandas tenues y las piezas
    /// del primer paso llegan una tras otra; la marca va quieta.
    func testWelcome() throws {
        // Sin esperar al arranque: la bienvenida empieza cuando el arranque deja ver lo de debajo, y la ráfaga los coge
        // seguidos (primero las piezas del arranque, luego las bandas y las piezas de la bienvenida).
        super.launch(["-MiBancoDemoOnboarding", "1"])
        burst("welcome", frames: 32, every: 0.4)
        XCTAssertTrue(app.staticTexts["Tus saldos"].waitForExistence(timeout: 10), "La ráfaga no es de la bienvenida")
    }

    /// Con Reducir movimiento: sin barrido; las bandas y las piezas aparecen con un fundido.
    func testWelcomeReduce() throws {
        super.launch(["-MiBancoDemoOnboarding", "1", "-MiBancoReduceMotion"])
        burst("welcome-reduce", frames: 14, every: 0.3)
        XCTAssertTrue(app.staticTexts["Tus saldos"].waitForExistence(timeout: 10), "La ráfaga no es de la bienvenida")
    }

    /// Primer arranque aterrizando en la bienvenida (`.launchWelcomeMark()`) a cámara lenta ×8: marca montada, «ONYX»
    /// se apaga al despegar, la marca vuela hasta la ranura de 58 pt de la bienvenida y aterriza sin relevo doble ni
    /// hueco (una sola marca en cada fotograma).
    func testWelcomeLaunchLanding() throws {
        super.launch(["-MiBancoDemoOnboarding", "1", "-MiBancoDemoLaunchHold", "25"], scale: 8)
        let probe = element("launch-probe")
        var startsAt: Double?
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            let text = (probe.value as? String) ?? ""
            for pair in text.split(separator: ";") {
                let parts = pair.split(separator: "=", maxSplits: 1)
                if parts.count == 2, parts[0] == "empieza", let t = Double(parts[1]) {
                    startsAt = t
                }
            }
            if startsAt != nil { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        let start = try XCTUnwrap(startsAt, "La app no publicó cuándo empieza el arranque de la bienvenida")
        // A ×8 en Expresivo: brillo ~5,7 s, assembleAt ~7,0 s, despegue ~7,7 s, aterrizaje ~10,8 s.
        let wait = start + 5.5 - Date().timeIntervalSince1970
        XCTAssertGreaterThan(wait, 0, "La espera del arranque se quedó corta (\(wait) s)")
        if wait > 0 { Thread.sleep(forTimeInterval: wait) }
        burst("welcome-launch", frames: 32, every: 0.25)
        XCTAssertTrue(app.staticTexts["Tus saldos"].waitForExistence(timeout: 10), "La ráfaga no llegó a la bienvenida")
        XCTAssertFalse(app.staticTexts["ONYX"].exists, "Quedó el texto «ONYX» en la bienvenida")
    }

    /// La guía de avisos: «Siguiente» desliza la página 70 pt hacia el lado al que se avanza y, medio segundo después,
    /// un aro de «toca aquí» sale de lo que hay que tocar en el dibujo.
    func testAlertsGuide() throws {
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoAlertsGuide", "rev", "1"])
        let next = app.buttons["guide-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 20), "No se abrió la guía")
        Thread.sleep(forTimeInterval: 6)
        // Sin comprobar «se puede tocar»: junto a la barra de pestañas esa pregunta falla aunque el toque entre.
        next.tap()
        burst("alerts-guide", frames: 22, every: 0.3)
        let counter = app.descendants(matching: .any).matching(identifier: "guide-step-counter").firstMatch
        XCTAssertTrue(counter.label.contains("Paso 2 de"), "La ráfaga no avanzó al paso 2: \(counter.label)")
    }

    /// Tocar «Importar»: el tercer paso corre de 67 a 100, el botón se transforma (rueda y ✓) y se vuelve al banco.
    func testImportConfirm() throws {
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoImportOnOpen"])
        let row = app.buttons["settings-bank-rev"]
        XCTAssertTrue(row.waitForExistence(timeout: 20), "Falta la fila de Revolut en Ajustes")
        row.tap()
        let confirm = app.buttons["import-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 30), "Falta «Importar»")
        Thread.sleep(forTimeInterval: 5)
        XCTAssertTrue(confirm.isHittable, "«Importar» no se puede tocar")
        confirm.tap()
        burst("import-confirm", frames: 20, every: 0.2)
        XCTAssertTrue(app.buttons["bank-import-statement"].waitForExistence(timeout: 10), "Tras importar no volvió al banco")
    }
}
