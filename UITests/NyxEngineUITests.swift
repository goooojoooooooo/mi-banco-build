import XCTest

/// Pruebas de interfaz de Nyx Fase 2 — N8 (motor de Nyx en los tres momentos, avisos locales y sonda de salud).
final class NyxEngineUITests: XCTestCase {
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
        app = XCUIApplication()
        app.launchArguments = ["-MiBancoDemo"] + extra + ["-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for name in ["Permitir", "Allow"] {
            let b = springboard.alerts.buttons[name]
            if b.waitForExistence(timeout: 2) { b.tap(); break }
        }
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func value(_ el: XCUIElement) -> String {
        (el.value as? String) ?? ""
    }

    private func waitUntil(_ timeout: TimeInterval = 12, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.15)
        }
        return condition()
    }

    private func nyxProbe() -> [String: String] {
        let el = element("nyx-engine-probe")
        guard el.exists else { return [:] }
        let raw = value(el)
        var out: [String: String] = [:]
        for pair in raw.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 { out[String(parts[0])] = String(parts[1]) }
        }
        return out
    }

    /// N8: con escenario `shortfall` tras el desbloqueo, Nyx apunta exactamente 1 observación nueva (`shortfall`)
    /// y nunca corre antes de quitar el bloqueo.
    func testAbrirConUnCobroQueNoCabeLoApuntaYEnciendeElPunto() throws {
        launch([
            "-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "2",
            "-MiBancoDemoNyx", "shortfall",
            "-MiBancoDemoPersistNyx", "-MiBancoDemoNyxReset",
        ])

        let probeEl = element("nyx-engine-probe")
        XCTAssertTrue(probeEl.waitForExistence(timeout: 15), "Falta la sonda del motor de Nyx")

        // Tras desbloquear, Nyx corre `.open` y apunta exactamente 1 cosa nueva (`shortfall`), encendiendo el punto.
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 20), "No se desbloqueó Inicio")
        XCTAssertTrue(waitUntil(12) { self.nyxProbe()["nuevas"] == "1" && (Int(self.nyxProbe()["corridas"] ?? "0") ?? 0) >= 1 },
                      "Nyx no apuntó exactamente 1 cosa nueva tras desbloquear: \(nyxProbe())")
        XCTAssertEqual(nyxProbe()["situaciones"], "shortfall", "La situación apuntada debe ser shortfall: \(nyxProbe())")
        let nyxButton = app.buttons["nyx-button"]
        XCTAssertTrue(nyxButton.waitForExistence(timeout: 8), "Falta nyx-button tras desbloquear")
        XCTAssertEqual(value(nyxButton), "1 cosa nueva", "El valor de nyx-button debe indicar 1 cosa nueva: \(value(nyxButton))")
    }

    /// N8: relanzar en el mismo escenario conservando la memoria no duplica la observación (`nuevas` sigue siendo 1).
    func testElMismoMomentoDosVecesNoDuplica() throws {
        launch([
            "-MiBancoDemoNyx", "shortfall",
            "-MiBancoDemoPersistNyx", "-MiBancoDemoNyxReset",
        ])
        let probeEl = element("nyx-engine-probe")
        XCTAssertTrue(probeEl.waitForExistence(timeout: 15), "Falta la sonda del motor de Nyx en el primer arranque")
        XCTAssertTrue(waitUntil(12) { self.nyxProbe()["nuevas"] == "1" },
                      "El primer arranque no apuntó 1 cosa nueva: \(nyxProbe())")

        app.terminate()

        launch([
            "-MiBancoDemoNyx", "shortfall",
            "-MiBancoDemoPersistNyx",
        ])
        XCTAssertTrue(probeEl.waitForExistence(timeout: 15), "Falta la sonda del motor de Nyx en el segundo arranque")
        XCTAssertTrue(waitUntil(12) { (Int(self.nyxProbe()["corridas"] ?? "0") ?? 0) >= 1 },
                      "El motor de Nyx no corrió en el segundo arranque: \(nyxProbe())")
        XCTAssertEqual(nyxProbe()["nuevas"], "1", "El segundo arranque duplicó la observación: \(nyxProbe())")
        XCTAssertEqual(nyxProbe()["total"], "1", "El total de entradas en memoria debe seguir en 1: \(nyxProbe())")
        let nyxButton = app.buttons["nyx-button"]
        XCTAssertTrue(nyxButton.waitForExistence(timeout: 8), "Falta nyx-button en el segundo arranque")
        XCTAssertEqual(value(nyxButton), "1 cosa nueva", "El valor de nyx-button cambió tras relanzar: \(value(nyxButton))")
    }

    /// N8 (privacidad ojo cerrado): un aviso local de Nyx compuesto con el ojo cerrado no lleva ningún dígito ni «€».
    func testAvisoDeNyxConOjoCerradoNoLlevaCifras() throws {
        launch([
            "-MiBancoDemoNyx", "shortfall-bg",
            "-MiBancoDemoPrivate",
        ])
        let probeEl = element("nyx-engine-probe")
        XCTAssertTrue(probeEl.waitForExistence(timeout: 15), "Falta la sonda del motor de Nyx")
        XCTAssertTrue(waitUntil(12) {
            let p = self.nyxProbe()
            return (Int(p["corridas"] ?? "0") ?? 0) >= 1 && (p["aviso"] ?? "-") != "-"
        }, "No se compuso ningún aviso de Nyx en segundo plano: \(nyxProbe())")

        let notifText = nyxProbe()["aviso"] ?? ""
        XCTAssertFalse(notifText.isEmpty || notifText == "-", "El texto del aviso de Nyx está vacío")
        XCTAssertFalse(notifText.contains(where: \.isNumber), "Con el ojo cerrado el aviso de Nyx contiene dígitos: \(notifText)")
        XCTAssertFalse(notifText.contains("€"), "Con el ojo cerrado el aviso de Nyx contiene €: \(notifText)")
        XCTAssertFalse(notifText.contains("%"), "Con el ojo cerrado el aviso de Nyx contiene %: \(notifText)")
    }

    /// N8 (m-6 permiso real): sin permiso del sistema, Nyx baja el aviso a `.list`, no gasta tope ni registra «Te avisé».
    func testSinPermisoDeAvisosNoGastaTopeNiGrabaTeAvise() throws {
        launch([
            "-MiBancoDemoNyx", "shortfall-bg",
            "-MiBancoDemoNyxNoNotifications",
        ])
        let probeEl = element("nyx-engine-probe")
        XCTAssertTrue(probeEl.waitForExistence(timeout: 15), "Falta la sonda del motor de Nyx")
        XCTAssertTrue(waitUntil(12) { (Int(self.nyxProbe()["corridas"] ?? "0") ?? 0) >= 1 },
                      "El motor de Nyx no corrió sin permiso de avisos: \(nyxProbe())")

        let p = nyxProbe()
        XCTAssertEqual(p["aviso"], "-", "Sin permiso del sistema no debe publicarse ningún aviso: \(p)")
        XCTAssertEqual(p["interrupciones"], "0", "Sin permiso del sistema no debe gastarse el tope diario: \(p)")
        XCTAssertTrue((p["entregas"] ?? "").contains("list"), "Las observaciones deben bajar a la lista: \(p)")
        XCTAssertFalse((p["entregas"] ?? "").contains("notification"), "Ninguna observación debe quedar como notification: \(p)")
    }
}
