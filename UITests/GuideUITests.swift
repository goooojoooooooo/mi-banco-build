import XCTest

/// Toques reales sobre la guía de avisos: abrirla desde Ajustes, avanzar, retroceder, ayuda y «Abrir Atajos».
final class GuideUITests: XCTestCase {
    /// Pasos de la guía de Revolut (una sola acción por pantalla).
    static let revolutSteps = 22
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
        app.launchArguments = ["-MiBancoDemo", "-MiBancoDemoScreen", "ajustes", "-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()
    }

    /// El contador lleva identificador, así que se lee su etiqueta («Parte 1 de 4 · Paso 3 de 22»), no se busca por texto.
    private func waitForStep(_ n: Int, _ message: String, total: Int = GuideUITests.revolutSteps,
                             partEnds: [Int] = [8, 11, 16]) {
        let counter = app.descendants(matching: .any).matching(identifier: "guide-step-counter").firstMatch
        if !counter.waitForExistence(timeout: 10) {
            // Si falla, el árbol de accesibilidad (en una línea) queda en el registro para ver qué había en pantalla.
            let tree = app.debugDescription.replacingOccurrences(of: "\n", with: " | ")
            XCTFail("\(message). Árbol: \(tree.prefix(6000))")
            return
        }
        // Partes de la guía de Revolut: pasos 1–8, 9–11, 12–16 y 17–22 (Apple Pay: 1–7, 8–10, 11–15 y 16–20).
        let part = (partEnds.firstIndex { n <= $0 } ?? partEnds.count) + 1
        let expected = "Parte \(part) de 4 · Paso \(n) de \(total)"
        let reached = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: counter)
        XCTAssertEqual(XCTWaiter().wait(for: [reached], timeout: 6), .completed, "\(message) (se esperaba «\(expected)»)")
    }

    private func openRevolutGuide() {
        let link = app.buttons["settings-alerts-guide"]
        XCTAssertTrue(link.waitForExistence(timeout: 15), "Ajustes no muestra «Avisos al instante»")
        link.tap()
        let revolut = app.buttons["guide-track-revolut"]
        XCTAssertTrue(revolut.waitForExistence(timeout: 5), "La lista de guías no aparece")
        revolut.tap()
        waitForStep(1, "No abrió el paso 1")
    }

    func testStepsAndHelp() throws {
        openRevolutGuide()
        let next = app.buttons["guide-next"]
        XCTAssertTrue(next.exists)
        next.tap()
        waitForStep(2, "Siguiente no avanzó al paso 2")
        next.tap()
        waitForStep(3, "Siguiente no avanzó al paso 3")

        let back = app.buttons["guide-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        waitForStep(2, "Atrás no volvió al paso 2")
        next.tap()
        waitForStep(3, "Siguiente no avanzó otra vez al paso 3")

        XCTAssertFalse(app.staticTexts["guide-help-text"].exists)
        let help = app.buttons["guide-help"]
        XCTAssertTrue(help.waitForExistence(timeout: 5))
        help.tap()
        XCTAssertTrue(app.staticTexts["guide-help-text"].waitForExistence(timeout: 5), "La ayuda no se abrió")
        XCTAssertTrue(app.buttons["guide-open-shortcuts"].exists, "Falta el botón «Abrir Atajos»")
    }

    func testListHasOneApplePayGuidePerBank() throws {
        let link = app.buttons["settings-alerts-guide"]
        XCTAssertTrue(link.waitForExistence(timeout: 15), "Ajustes no muestra «Avisos al instante»")
        link.tap()
        for id in ["guide-track-walletImagin", "guide-track-walletRevolut", "guide-track-walletTradeRepublic"] {
            XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 5), "Falta la guía de Apple Pay: \(id)")
        }
    }

    private let base = ["-MiBancoDemo", "-MiBancoDemoScreen", "ajustes", "-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]

    private func openList() {
        let link = app.buttons["settings-alerts-guide"]
        XCTAssertTrue(link.waitForExistence(timeout: 15), "Ajustes no muestra «Avisos al instante»")
        link.tap()
    }

    private func waitForApplePayStep(_ n: Int, _ message: String) {
        waitForStep(n, message, total: 20, partEnds: [7, 10, 15])
    }

    /// iOS puede cerrar la app mientras él está en Atajos: al volver, la guía sigue en el mismo paso. Se prueba con una
    /// guía que en los datos de demo no ha recibido ningún aviso (la fila de la lista muestra entonces dónde se quedó).
    func testGuideResumesAfterRelaunch() throws {
        app.terminate()
        let persist = base + ["-MiBancoDemoPersistGuide"]
        app.launchArguments = persist + ["-MiBancoDemoGuideReset"]
        app.launch()
        openList()
        let track = app.buttons["guide-track-walletRevolut"]
        XCTAssertTrue(track.waitForExistence(timeout: 5), "La lista de guías no aparece")
        track.tap()
        waitForApplePayStep(1, "No abrió el paso 1")
        let next = app.buttons["guide-next"]
        for step in 2...4 {
            next.tap()
            waitForApplePayStep(step, "No llegó al paso \(step)")
        }
        XCTAssertFalse(app.buttons["guide-restart"].exists, "«Empezar desde el principio» solo se ofrece al retomar")

        app.terminate()
        app.launchArguments = persist
        app.launch()
        openList()
        let row = app.buttons["guide-track-walletRevolut"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "La lista de guías no aparece")
        XCTAssertTrue(row.label.contains("Vas por el paso 4 de 20"), "La lista no dice dónde se quedó: \(row.label)")
        row.tap()
        waitForApplePayStep(4, "No retomó en el paso 4 tras reiniciar")
        let restart = app.buttons["guide-restart"]
        XCTAssertTrue(restart.waitForExistence(timeout: 5), "Falta «Empezar desde el principio»")
        restart.tap()
        waitForApplePayStep(1, "«Empezar desde el principio» no volvió al paso 1")

        // Y tras otro cierre la guía abre en el paso 1, sin retomar nada.
        app.terminate()
        app.launchArguments = persist
        app.launch()
        openList()
        let again = app.buttons["guide-track-walletRevolut"]
        XCTAssertTrue(again.waitForExistence(timeout: 5), "La lista de guías no aparece")
        XCTAssertFalse(again.label.contains("Vas por el paso"), "No debería quedar nada que retomar: \(again.label)")
        again.tap()
        waitForApplePayStep(1, "Tras empezar de nuevo debía abrir el paso 1")
        XCTAssertFalse(app.buttons["guide-restart"].exists, "No debería ofrecer empezar de nuevo en el paso 1")
    }

    /// Retomando una guía en un paso con mucho texto, lo que él necesita se ve sin deslizar: la ayuda se puede tocar y la
    /// instrucción entera queda por encima de «Abrir Atajos».
    func testResumedStepFitsWithoutScrolling() throws {
        for step in [19, 10] {
            app.terminate()
            app.launchArguments = base + ["-MiBancoDemoGuideSeed", "rev", String(step)]
            app.launch()
            waitForStep(step, "No retomó en el paso \(step)")
            let help = app.buttons["guide-help"]
            XCTAssertTrue(help.waitForExistence(timeout: 5), "Falta «¿No te sale esto?» en el paso \(step)")
            XCTAssertTrue(help.isHittable, "«¿No te sale esto?» no se ve sin deslizar en el paso \(step)")
            let instruction = app.staticTexts["guide-instruction"]
            XCTAssertTrue(instruction.exists, "Falta la instrucción en el paso \(step)")
            let open = app.buttons["guide-open-shortcuts"]
            XCTAssertTrue(open.exists)
            XCTAssertLessThanOrEqual(instruction.frame.maxY, open.frame.minY,
                                     "La instrucción del paso \(step) queda bajo «Abrir Atajos»")
            XCTAssertLessThanOrEqual(help.frame.maxY, open.frame.minY, "La ayuda del paso \(step) queda bajo «Abrir Atajos»")
            let restart = app.buttons["guide-restart"]
            XCTAssertTrue(restart.exists, "Falta «Empezar desde el principio» al retomar el paso \(step)")
            XCTAssertLessThanOrEqual(restart.frame.maxY, open.frame.minY,
                                     "«Empezar desde el principio» del paso \(step) queda bajo «Abrir Atajos»")
        }
    }

    /// «Empezar desde el principio» no se ofrece en el primer paso, tampoco si se vuelve atrás hasta él.
    func testRestartIsNotOfferedOnStepOne() throws {
        app.terminate()
        app.launchArguments = base + ["-MiBancoDemoGuideSeed", "rev", "4"]
        app.launch()
        waitForStep(4, "No retomó en el paso 4")
        XCTAssertTrue(app.buttons["guide-restart"].waitForExistence(timeout: 5))
        let back = app.buttons["guide-back"]
        for step in [3, 2, 1] {
            back.tap()
            waitForStep(step, "Atrás no llegó al paso \(step)")
        }
        XCTAssertFalse(app.buttons["guide-restart"].exists, "«Empezar desde el principio» sigue en el paso 1")
    }

    /// Espera (sin deslizar nada) a que se cumpla algo que lee posiciones: el contenido puede estar aún deslizándose.
    private func eventually(_ timeout: TimeInterval = 4, _ condition: @escaping () -> Bool) -> Bool {
        let met = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter().wait(for: [met], timeout: timeout) == .completed
    }

    /// Abre un paso por el camino de retomar (con un paso guardado), con más argumentos si hacen falta.
    private func launchResumed(_ track: String, _ step: Int, extra: [String] = []) {
        app.terminate()
        app.launchArguments = base + extra + ["-MiBancoDemoGuideSeed", track, String(step)]
        app.launch()
    }

    /// Arriba de lo visible del paso: el final de la cabecera (la línea de la parte, 8 pt, los puntos de 6 pt y 12 pt).
    private func visibleTop() -> CGFloat {
        app.staticTexts["guide-step-part"].frame.maxY + 8 + 6 + 12
    }

    /// Abre «¿No te sale esto?» sin deslizar nada y comprueba que se ve (G28): si es más baja que lo visible, entera por
    /// encima del margen de los botones (`open.minY - 12`, sin recortar ni los 12 pt de relleno); si es más alta, su
    /// principio dentro de lo visible y, tras deslizar una vez, su final.
    private func assertOpeningHelpShowsIt(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let help = app.buttons["guide-help"]
        XCTAssertTrue(help.waitForExistence(timeout: 5), "Falta «¿No te sale esto?» (\(name))", file: file, line: line)
        help.tap()
        let text = app.staticTexts["guide-help-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5), "La ayuda no se abrió (\(name))", file: file, line: line)
        let open = app.buttons["guide-open-shortcuts"]
        let top = visibleTop()
        // H: lo visible entre la cabecera y los botones fijos (que llevan 12 pt de margen encima de «Abrir Atajos»).
        let visible = open.frame.minY - 12 - top
        let drawing = app.descendants(matching: .any).matching(identifier: "guide-drawing").firstMatch
        if text.frame.height <= visible {
            XCTAssertTrue(eventually(4) { text.frame.maxY <= open.frame.minY - 12 && text.frame.minY >= top - 1 },
                          "La ayuda abierta no se ve entera sin deslizar (\(name)): ayuda \(text.frame), botón \(open.frame), arriba \(top)",
                          file: file, line: line)
        } else {
            XCTAssertTrue(eventually(4) { text.frame.minY >= top - 1 && text.frame.minY + 34 <= open.frame.minY },
                          "El principio de la ayuda no se ve sin deslizar (\(name)): ayuda \(text.frame), botón \(open.frame), arriba \(top)",
                          file: file, line: line)
            app.swipeUp()
            XCTAssertTrue(eventually(4) { text.frame.maxY <= open.frame.minY - 12 },
                          "El final de la ayuda no se alcanza deslizando (\(name)): ayuda \(text.frame), botón \(open.frame)",
                          file: file, line: line)
        }
        let drawingInfo = drawing.exists ? String(format: "%.1f pt", drawing.frame.height) : "oculto"
        let measure = String(format: "G28 (%@): ayuda alto %.1f, maxY %.1f vs open.minY %.1f (tope %.1f), dibujo %@",
                             name, text.frame.height, text.frame.maxY, open.frame.minY, open.frame.minY - 12, drawingInfo)
        XCTContext.runActivity(named: measure) { _ in }
    }

    /// Abrir «¿No te sale esto?» siempre la enseña (G28), retomando el paso 19 de Revolut.
    func testOpeningHelpShowsIt() throws {
        launchResumed("rev", 19)
        waitForStep(19, "No retomó rev en el paso 19")
        assertOpeningHelpShowsIt("rev 19 retomado")
    }

    /// La ayuda más larga (Apple Pay de imagin, paso 6, retomado): se ve entera al abrirla (el dibujo cede el sitio).
    func testOpeningLongestHelpShowsIt() throws {
        launchResumed("wallet", 6)
        waitForApplePayStep(6, "No retomó wallet en el paso 6")
        assertOpeningHelpShowsIt("wallet 6 retomado")
    }

    /// Un paso nuevo (sin retomar) que cabe justo: al abrir la ayuda, el dibujo cede el sitio y la ayuda entera queda
    /// por encima de «Abrir Atajos» sin deslizar.
    func testOpeningHelpOnFreshStepShowsIt() throws {
        app.terminate()
        app.launchArguments = base + ["-MiBancoDemoAlertsGuide", "rev", "19"]
        app.launch()
        waitForStep(19, "No abrió rev en el paso 19")
        XCTAssertFalse(app.buttons["guide-restart"].exists, "Este paso no debía abrirse retomando")
        assertOpeningHelpShowsIt("rev 19 nuevo")
    }

    /// Cerrar la ayuda devuelve el paso exactamente a su sitio (G28 / I2): primero se afirma que al abrirla la ayuda se
    /// vio de verdad (y con dibujo arriba el dibujo se ocultó o encogió), y después que al cerrarla tanto el título como
    /// el dibujo vuelven a su sitio (±1 pt) y la instrucción empieza dentro de lo visible.
    func testClosingHelpPutsTheStepBack() throws {
        for size in ["", "UICTContentSizeCategoryAccessibilityM"] {
            launchResumed("wallet", 6, extra: size.isEmpty ? [] : ["-UIPreferredContentSizeCategoryName", size])
            waitForApplePayStep(6, "No retomó wallet en el paso 6 (\(size))")
            let title = app.staticTexts["guide-title"]
            XCTAssertTrue(title.waitForExistence(timeout: 5), "Falta el título (\(size))")
            let drawing = app.descendants(matching: .any).matching(identifier: "guide-drawing").firstMatch
            XCTAssertTrue(drawing.exists, "Falta el dibujo antes de abrir la ayuda (\(size))")
            let beforeTitle = title.frame.minY
            let beforeDrawing = drawing.frame.height
            let help = app.buttons["guide-help"]
            let open = app.buttons["guide-open-shortcuts"]
            let top = visibleTop()

            help.tap()
            let text = app.staticTexts["guide-help-text"]
            XCTAssertTrue(text.waitForExistence(timeout: 5), "La ayuda no se abrió (\(size))")
            if size.isEmpty {
                XCTAssertTrue(eventually(4) { text.frame.maxY <= open.frame.minY - 12 && text.frame.minY >= top - 1 },
                              "La ayuda no se vio entera al abrirla (\(size)): ayuda \(text.frame), botón \(open.frame), arriba \(top)")
                XCTAssertTrue(eventually(4) { !drawing.exists || drawing.frame.height < beforeDrawing - 1 },
                              "El dibujo no cedió sitio al abrir la ayuda (\(size)): antes \(beforeDrawing), ahora \(drawing.frame.height)")
            } else {
                XCTAssertTrue(eventually(4) { text.frame.minY >= top - 1 && text.frame.minY + 34 <= open.frame.minY },
                              "El principio de la ayuda no se vio al abrirla (\(size)): ayuda \(text.frame), botón \(open.frame)")
            }

            help.tap()
            XCTAssertTrue(eventually(4) { !text.exists }, "La ayuda no se cerró (\(size))")
            let instruction = app.staticTexts["guide-instruction"]
            XCTAssertTrue(eventually(4) { abs(title.frame.minY - beforeTitle) <= 1 },
                          "Al cerrar la ayuda el título no vuelve a su sitio (\(size)): antes \(beforeTitle), ahora \(title.frame)")
            XCTAssertTrue(eventually(4) { drawing.exists && abs(drawing.frame.height - beforeDrawing) <= 1 },
                          "Al cerrar la ayuda el dibujo no vuelve a su alto (\(size)): antes \(beforeDrawing), ahora existe=\(drawing.exists) alto=\(drawing.frame.height)")
            XCTAssertTrue(instruction.frame.minY >= top - 1 && instruction.frame.minY < open.frame.minY,
                          "Al cerrar la ayuda la instrucción no empieza en lo visible (\(size)): \(instruction.frame), arriba \(top)")
        }
    }

    /// Con el texto arriba (letra de accesibilidad), VoiceOver lee en el orden de la pantalla (G27): lo imprescindible,
    /// «Empezar desde el principio» y el dibujo al final.
    @MainActor
    func testTextFirstReadsInScreenOrder() throws {
        launchResumed("rev", 19, extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"])
        waitForStep(19, "No retomó rev en el paso 19")
        let instruction = app.staticTexts["guide-instruction"]
        let drawing = app.descendants(matching: .any).matching(identifier: "guide-drawing").firstMatch
        XCTAssertTrue(instruction.waitForExistence(timeout: 5) && drawing.exists, "Falta la instrucción o el dibujo")
        XCTAssertLessThan(instruction.frame.minY, drawing.frame.minY, "Con letra de accesibilidad el texto debía ir arriba")
        // Orden del árbol de accesibilidad (el que sigue VoiceOver), en profundidad.
        var order: [String] = []
        func walk(_ node: XCUIElementSnapshot) {
            if !node.identifier.isEmpty { order.append(node.identifier) }
            node.children.forEach(walk)
        }
        walk(try app.snapshot())
        let ids = ["guide-instruction", "guide-help", "guide-restart", "guide-drawing"]
        let positions = ids.map { order.firstIndex(of: $0) }
        XCTAssertFalse(positions.contains(nil), "Faltan piezas en el árbol: \(order)")
        let found = positions.compactMap { $0 }
        XCTAssertEqual(found, found.sorted(), "VoiceOver no lee en el orden de la pantalla: \(order)")
    }

    /// Con letra más grande (sin ser de accesibilidad), retomando el paso 19: la instrucción entera y «¿No te sale
    /// esto?» siguen por encima de «Abrir Atajos» sin deslizar.
    func testResumedStepFitsAtLargerText() throws {
        for size in ["UICTContentSizeCategoryXL", "UICTContentSizeCategoryXXXL"] {
            launchResumed("rev", 19, extra: ["-UIPreferredContentSizeCategoryName", size])
            waitForStep(19, "No retomó en el paso 19 (\(size))")
            let help = app.buttons["guide-help"]
            XCTAssertTrue(help.waitForExistence(timeout: 5), "Falta «¿No te sale esto?» (\(size))")
            XCTAssertTrue(help.isHittable, "«¿No te sale esto?» no se ve sin deslizar (\(size))")
            let instruction = app.staticTexts["guide-instruction"]
            XCTAssertTrue(instruction.exists, "Falta la instrucción (\(size))")
            let open = app.buttons["guide-open-shortcuts"]
            XCTAssertTrue(open.exists)
            XCTAssertLessThanOrEqual(instruction.frame.maxY, open.frame.minY, "La instrucción queda bajo «Abrir Atajos» (\(size))")
            XCTAssertLessThanOrEqual(help.frame.maxY, open.frame.minY, "La ayuda queda bajo «Abrir Atajos» (\(size))")
        }
    }

    func testLastStepIsDone() throws {
        openRevolutGuide()
        let next = app.buttons["guide-next"]
        for step in 2...Self.revolutSteps {
            next.tap()
            waitForStep(step, "No llegó al paso \(step)")
        }
        XCTAssertEqual(next.label, "Hecho")
        next.tap()
        XCTAssertTrue(app.buttons["guide-track-revolut"].waitForExistence(timeout: 5), "«Hecho» no volvió a la lista")
    }
}
