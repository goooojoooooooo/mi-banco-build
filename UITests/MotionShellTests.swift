import XCTest

/// Toques reales sobre el marco y las hojas de la fase de animaciones (línea «Marco y hojas»): el arranque «logo en
/// piezas», el bloqueo, y los importes que ruedan en el detalle y en el resumen. Siempre en modo demo.
final class MotionShellTests: XCTestCase {
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
        app = XCUIApplication()
    }

    private func launch(_ extra: [String] = []) {
        app.launchArguments = ["-MiBancoDemo"] + extra + ["-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func labelled(_ predicate: String, _ argument: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: predicate, argument)).firstMatch
    }

    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return condition()
    }

    private func moneyShaped(_ text: String) -> Bool {
        text.contains("€") || text.contains("euros") || text.range(of: #"\d,\d{2}"#, options: .regularExpression) != nil
    }

    /// Todas las etiquetas y valores con forma de importe que hay ahora en la app.
    private func moneyStrings() -> [String] {
        app.descendants(matching: .any).allElementsBoundByIndex.flatMap { el -> [String] in
            var found: [String] = []
            if moneyShaped(el.label) { found.append("label:\(el.label)") }
            if let value = el.value as? String, moneyShaped(value) { found.append("value:\(value)") }
            return found
        }
    }

    /// Lo que publica la app sobre su arranque (solo DEBUG): «arranques=1;estilo=piezas;saltos=0;libre=963;fin=1344;…».
    private func probe() -> [String: String] {
        let value = element("launch-probe").value as? String ?? ""
        var out: [String: String] = [:]
        for pair in value.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 { out[String(parts[0])] = String(parts[1]) }
        }
        return out
    }

    /// Espera a que la capa del arranque se haya quitado (mientras está, un toque la salta en vez de llegar a Inicio).
    private func waitForLaunchToEnd(_ timeout: TimeInterval = 20) {
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")
        XCTAssertTrue(waitUntil(timeout) { !self.element("launch-layer").exists }, "El arranque no terminó")
    }

    /// El carrusel es un único elemento de accesibilidad cuya etiqueta acaba en «N de 4».
    private func carousel() -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES %@", ".* [0-9] de 4$")).firstMatch
    }

    /// Un toque de verdad en Inicio: el ojo cambia de «Ocultar importes» a «Mostrar importes».
    private func assertHomeResponds(_ message: String) {
        let hide = app.buttons["Ocultar importes"]
        XCTAssertTrue(hide.waitForExistence(timeout: 8), "Falta el ojo: \(message)")
        hide.tap()
        XCTAssertTrue(app.buttons["Mostrar importes"].waitForExistence(timeout: 5), message)
    }

    /// Abre el detalle de la primera fila de Inicio y espera a que la hoja esté arriba.
    private func openFirstRowDetail() {
        waitForLaunchToEnd()
        let row = app.buttons.matching(identifier: "movementRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "No hay filas de movimientos")
        XCTAssertTrue(waitUntil(10) { row.isHittable }, "La primera fila no se puede tocar")
        row.tap()
        XCTAssertTrue(app.buttons["Cerrar"].waitForExistence(timeout: 8), "No se abrió la hoja de detalle")
    }

    // MARK: - C2 · Arranque «logo en piezas»

    /// (a) Sin bloqueo: un toque en cualquier parte salta el arranque y deja Inicio a mano. (b) Con bloqueo: las piezas
    /// se montan EN el bloqueo; mientras dure el bloqueo no existe ninguna capa del arranque ni se ve nada de Inicio, y un
    /// toque en la pantalla termina el dibujo de la marca pero no desbloquea. Al desbloquear, la marca vuela sin estorbar.
    func testLaunchSkippableAndNeverAboveLock() throws {
        // (a) A cámara lenta ×40 el arranque duraría casi un minuto y tardaría 38 s en dejar tocar Inicio.
        launch(["-MiBancoMotionScale", "40"])
        let layer = element("launch-layer")
        XCTAssertTrue(layer.waitForExistence(timeout: 15), "No aparece la capa del arranque")
        XCTAssertEqual(layer.value as? String, "piezas;tocable", "El arranque no es el de piezas o ya no recibe toques")
        XCTAssertEqual(probe()["saltos"], "0")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)).tap()
        // Tras el toque queda una décima de guion (unos 5 s a ×40): si no saltara, la capa seguiría medio minuto más.
        XCTAssertTrue(waitUntil(10) { !layer.exists }, "Un toque no saltó el arranque")
        let skipped = probe()
        XCTAssertEqual(skipped["saltos"], "1", "El toque no contó como salto: \(skipped)")
        XCTAssertEqual(skipped["arranques"], "1")
        assertHomeResponds("Tras saltar el arranque, Inicio no responde")
        app.terminate()

        // (b) Bloqueo de demo de 45 s, también a ×40 (las piezas tardarían 44 s en montarse).
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "45", "-MiBancoMotionScale", "40"])
        let unlock = app.buttons["Desbloquear"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 15), "Falta la pantalla de bloqueo")
        XCTAssertTrue(unlock.isHittable, "El botón de desbloquear no está disponible mientras la marca se monta")
        let mark = element("lock-mark")
        XCTAssertTrue(mark.waitForExistence(timeout: 5), "Falta la marca del bloqueo")
        XCTAssertEqual(mark.value as? String, "piezas", "En el arranque en frío el bloqueo debe montar las piezas")
        func assertNothingBesidesTheLock(_ moment: String) {
            XCTAssertFalse(element("launch-layer").exists, "\(moment): la capa del arranque existe con el bloqueo puesto")
            XCTAssertFalse(element("launch-exit").exists, "\(moment): la marca vuela con el bloqueo puesto")
            XCTAssertFalse(app.staticTexts["Tu dinero"].exists, "\(moment): Inicio está a la vista con el bloqueo puesto")
            XCTAssertFalse(app.buttons["Ocultar importes"].exists, "\(moment): el ojo de Inicio existe con el bloqueo puesto")
        }
        assertNothingBesidesTheLock("Al aparecer el bloqueo")
        // Un toque fuera del botón: la marca queda terminada y el bloqueo sigue ahí.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.14)).tap()
        XCTAssertTrue(waitUntil(5) { (mark.value as? String) == "completa" }, "Un toque no terminó la marca del bloqueo")
        var checks = 0
        while unlock.exists && checks < 10 {
            assertNothingBesidesTheLock("Tras el toque (mirada \(checks))")
            checks += 1
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertEqual(checks, 10, "El toque en la pantalla quitó el bloqueo")
        XCTAssertTrue(unlock.exists, "El toque en la pantalla quitó el bloqueo")
        XCTAssertEqual(probe()["arranques"], "0", "Con bloqueo no debe montarse la capa del arranque")

        // Al acabar el bloqueo de demo: Inicio vuelve, la marca vuela (a ×40 tarda 17 s) y mientras tanto Inicio responde.
        XCTAssertTrue(waitUntil(60) { !unlock.exists }, "El bloqueo de demo no se quitó")
        let exit = element("launch-exit")
        XCTAssertTrue(exit.waitForExistence(timeout: 5), "Tras desbloquear en frío la marca no vuela")
        XCTAssertEqual(exit.value as? String, "frio")
        XCTAssertFalse(element("launch-layer").exists, "Tras desbloquear se montó la capa del arranque")
        assertHomeResponds("Mientras la marca vuela, Inicio no responde")
        let after = probe()
        XCTAssertEqual(after["arranques"], "0", "Tras desbloquear se montó la capa del arranque: \(after)")
        XCTAssertEqual(after["salidas"], "1")
        XCTAssertEqual(after["bloqueoPiezas"], "1")
    }

    /// Volver de segundo plano no repite el arranque: ni sin bloqueo (no aparece ninguna capa) ni con él (el bloqueo sale
    /// con la marca quieta y, al quitarse, tampoco hay arranque).
    func testWarmResumeShowsNoLaunch() throws {
        launch()
        waitForLaunchToEnd()
        XCTAssertTrue(waitUntil(10) { self.probe()["fin"] != "-" }, "El arranque en frío no llegó a terminar")
        XCTAssertEqual(probe()["arranques"], "1")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1.5)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "La app no volvió a primer plano")
        for look in 0..<12 {
            XCTAssertFalse(element("launch-layer").exists, "Mirada \(look): el arranque se repitió al volver de segundo plano")
            XCTAssertFalse(element("launch-exit").exists, "Mirada \(look): la marca voló al volver de segundo plano")
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertEqual(probe()["arranques"], "1", "El arranque se repitió al volver de segundo plano")
        assertHomeResponds("Al volver de segundo plano, Inicio no responde")
        app.terminate()

        // Con bloqueo (demo, 4 s): arranque en frío con piezas; al volver de segundo plano, marca quieta.
        launch(["-MiBancoDemoLock"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 25), "Inicio no apareció tras el bloqueo")
        let cold = probe()
        XCTAssertEqual(cold["bloqueoPiezas"], "1", "El bloqueo del arranque en frío no montó las piezas: \(cold)")
        XCTAssertEqual(cold["bloqueoQuieto"], "0")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1.5)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "La app no volvió a primer plano")
        let unlock = app.buttons["Desbloquear"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 5), "No se mostró el bloqueo al volver de segundo plano")
        XCTAssertEqual(element("lock-mark").value as? String, "fija", "Al volver de segundo plano la marca del bloqueo debe estar quieta")
        XCTAssertFalse(element("launch-layer").exists, "El arranque se montó con el bloqueo puesto")
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no volvió tras el re-bloqueo")
        XCTAssertFalse(element("launch-layer").exists, "El arranque se repitió tras el re-bloqueo")
        let warm = probe()
        XCTAssertEqual(warm["arranques"], "0", "El arranque se repitió tras el re-bloqueo: \(warm)")
        XCTAssertEqual(warm["bloqueoPiezas"], "1", "Las piezas se repitieron en el re-bloqueo: \(warm)")
        XCTAssertEqual(warm["bloqueoQuieto"], "1")
    }

    /// A velocidad real y sin tocar nada: la capa del arranque deja tocar Inicio antes de 1,6 s (lo mide la propia app
    /// desde que empieza el arranque) y, cuando se quita, el carrusel está a mano y responde.
    func testLaunchNeverDelaysHome() throws {
        launch()
        let card = carousel()
        XCTAssertTrue(card.waitForExistence(timeout: 15), "No aparece el carrusel de tarjetas")
        XCTAssertTrue(waitUntil(10) { self.probe()["fin"] != "-" }, "El arranque no terminó solo")
        let result = probe()
        XCTAssertEqual(result["arranques"], "1")
        XCTAssertEqual(result["estilo"], "piezas", "El arranque por defecto (Expresivo) debe ser el de piezas: \(result)")
        XCTAssertEqual(result["saltos"], "0")
        let free = try XCTUnwrap(Int(result["libre"] ?? ""), "La app no apuntó cuándo dejó tocar Inicio: \(result)")
        let finished = try XCTUnwrap(Int(result["fin"] ?? ""), "La app no apuntó cuándo se quitó el arranque: \(result)")
        XCTAssertLessThanOrEqual(free, 1_600, "El arranque tardó \(free) ms en dejar tocar Inicio (máximo 1600)")
        XCTAssertGreaterThanOrEqual(free, 700, "El arranque dejó tocar Inicio a los \(free) ms: ¿se saltó solo?")
        // Guion: 1344 ms. El margen es para un simulador de CI cargado, no para el iPhone.
        XCTAssertLessThanOrEqual(finished, 2_000, "El arranque tardó \(finished) ms en quitarse (guion: 1344)")
        XCTAssertFalse(element("launch-layer").exists, "La capa del arranque sigue montada")
        XCTAssertTrue(card.isHittable, "El carrusel no se puede tocar tras el arranque")
        assertHomeResponds("Tras el arranque, Inicio no responde")
    }

    /// En Sutil y con Reducir movimiento el arranque es solo un fundido (sin piezas) y también deja Inicio a mano.
    func testSubtleAndReduceMotionLaunchOnlyFade() throws {
        for arguments in [["-MiBancoMotionLevel", "subtle"], ["-MiBancoReduceMotion"]] {
            launch(arguments)
            waitForLaunchToEnd()
            XCTAssertTrue(waitUntil(10) { self.probe()["fin"] != "-" }, "\(arguments): el arranque no terminó")
            let result = probe()
            XCTAssertEqual(result["estilo"], "fundido", "\(arguments): el arranque debe ser solo un fundido: \(result)")
            let finished = try XCTUnwrap(Int(result["fin"] ?? ""), "\(arguments): sin tiempo de fin: \(result)")
            XCTAssertLessThanOrEqual(finished, 1_200, "\(arguments): el fundido tardó \(finished) ms")
            assertHomeResponds("\(arguments): Inicio no responde tras el fundido")
            app.terminate()
        }
    }

    // MARK: - C1 · Importes que ruedan en las hojas

    /// El detalle de un movimiento: el importe grande y «Te quedaban» se leen como siempre (una etiqueta cada uno) aunque
    /// ahora rueden, y «Cerrar» sigue cerrando la hoja.
    func testDetailAmountsKeepTheirSpokenLabels() throws {
        launch()
        openFirstRowDetail()
        let amount = labelled("label BEGINSWITH %@", "Pago de ")
        XCTAssertTrue(amount.waitForExistence(timeout: 5), "Falta la etiqueta «Pago de …» del importe")
        XCTAssertTrue(amount.label.hasSuffix(" euros"), "El importe no se lee en euros: «\(amount.label)»")
        let left = labelled("label BEGINSWITH %@", "Te quedaban ")
        XCTAssertTrue(left.waitForExistence(timeout: 5), "Falta «Te quedaban»")
        XCTAssertTrue(left.label.hasSuffix(" euros"), "«Te quedaban» no se lee en euros: «\(left.label)»")
        app.buttons["Cerrar"].tap()
        XCTAssertTrue(waitUntil(8) { !self.app.buttons["Cerrar"].exists }, "La hoja no se cerró")
    }

    /// Con el ojo cerrado, abrir el detalle no añade a la app ni un solo importe, ni en etiquetas ni en valores: ni
    /// mientras la hoja entra (a cámara lenta: el importe rueda y «Te quedaban» se destapa) ni cuando ya está quieta.
    func testDetailAmountsObeyTheEye() throws {
        launch(["-MiBancoDemoPrivate", "-MiBancoMotionScale", "3"])
        let row = app.buttons.matching(identifier: "movementRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "No hay filas de movimientos")
        XCTAssertTrue(waitUntil(15) { row.isHittable }, "La primera fila no se puede tocar")
        let before = NSCountedSet(array: moneyStrings())
        row.tap()
        XCTAssertTrue(app.buttons["Cerrar"].waitForExistence(timeout: 8), "No se abrió la hoja de detalle")
        for pass in 0..<8 {
            let now = NSCountedSet(array: moneyStrings())
            let added = now.allObjects.filter { now.count(for: $0) > before.count(for: $0) }
            XCTAssertTrue(added.isEmpty, "Pasada \(pass): con el ojo cerrado el detalle trae importes: \(added)")
            Thread.sleep(forTimeInterval: 0.4)
        }
        XCTAssertTrue(labelled("label == %@", "Pago de importe oculto").exists
                      || labelled("label == %@", "Ingreso de importe oculto").exists,
                      "El importe del detalle no dice «importe oculto»")
        XCTAssertTrue(labelled("label == %@", "Te quedaban importe oculto").exists,
                      "«Te quedaban» no dice «importe oculto»")
    }

    /// La línea del total del resumen sigue siendo UNA etiqueta con la frase entera, aunque su importe ruede dentro.
    func testBriefingTotalIsOneSentence() throws {
        launch(["-MiBancoDemoBriefing", "busy"])
        XCTAssertTrue(app.buttons["Vale"].waitForExistence(timeout: 20), "La hoja del resumen no se abrió")
        let total = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "En total, ", "Sigues con ")).firstMatch
        XCTAssertTrue(total.waitForExistence(timeout: 8), "Falta la frase del total")
        XCTAssertTrue(total.label.contains("€"), "La frase del total no lleva su importe: «\(total.label)»")
        // Ninguna palabra suelta de la frase es un elemento aparte.
        for word in ["En ", "total, ", "Sigues ", "con "] {
            XCTAssertFalse(app.staticTexts[word].exists, "La frase del total se partió en palabras para VoiceOver: «\(word)»")
        }
        app.buttons["Vale"].tap()
        XCTAssertTrue(waitUntil(8) { !self.app.buttons["Vale"].exists }, "La hoja del resumen no se cerró")
    }
}
