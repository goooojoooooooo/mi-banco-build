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

    /// Abre el detalle de la primera fila de Inicio y espera a que la hoja esté arriba.
    private func openFirstRowDetail() {
        let row = app.buttons.matching(identifier: "movementRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "No hay filas de movimientos")
        XCTAssertTrue(waitUntil(10) { row.isHittable }, "La primera fila no se puede tocar")
        row.tap()
        XCTAssertTrue(app.buttons["Cerrar"].waitForExistence(timeout: 8), "No se abrió la hoja de detalle")
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
