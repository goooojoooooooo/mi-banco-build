import XCTest

/// Ráfagas visuales de Seguridad Fase 2 (`motion-video -f tour_class=MotionTourSecurityTests`):
/// - Bloqueo sin código (`SEC-08`): normal, con ojo cerrado y con Reducir movimiento.
/// - Campos migrados a `MaskedAmountTextField` (`SEC-05`): `PositionDetailSheet` y `AccountsView` con el ojo cerrado.
final class MotionTourSecurityTests: MotionTourCase {

    private func scrollTo(_ el: XCUIElement, in container: XCUIElement? = nil, swipes: Int = 8) {
        if el.waitForExistence(timeout: 2), el.isHittable { return }
        let target: XCUIElement = container ?? app!
        for _ in 0..<swipes {
            if el.exists && el.isHittable { return }
            target.swipeUp()
        }
        for _ in 0..<swipes {
            if el.exists && el.isHittable { return }
            target.swipeDown()
        }
    }

    private func captureNoPasscodeDisable(_ name: String, extra: [String]) {
        launch(["-MiBancoDemoNoPasscode"] + extra, scale: 4)
        let disableButton = app.buttons["lock-disable-button"]
        XCTAssertTrue(disableButton.waitForExistence(timeout: 20), "Falta la pantalla de bloqueo sin código")
        // Dejar terminar las piezas del bloqueo en frío para que los primeros fotogramas muestren la pantalla en reposo.
        Thread.sleep(forTimeInterval: 3.0)
        // Dos fotogramas de control antes de tocar y el resto durante la salida y aparición de Inicio.
        burst(name + "-antes", frames: 2, every: 0.3)
        disableButton.tap()
        burst(name, frames: 12, every: 0.25)
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 12), "No apareció Inicio tras desactivar")
    }

    func testLockNoPasscodeDisable() throws {
        captureNoPasscodeDisable("security-lock-nopasscode", extra: [])
    }

    func testLockNoPasscodeDisableEyeClosed() throws {
        captureNoPasscodeDisable("security-lock-nopasscode-ojo", extra: ["-MiBancoDemoPrivate"])
    }

    func testLockNoPasscodeDisableReduceMotion() throws {
        captureNoPasscodeDisable("security-lock-nopasscode-reducir", extra: ["-MiBancoReduceMotion"])
    }

    /// SEC-05: hoja de posición con el ojo cerrado al abrir «Poner precio a mano» y enfocar el campo (máscara → vacío).
    func testPositionPriceEyeClosed() throws {
        launch(["-MiBancoDemoPosition", "-MiBancoDemoPrivate"], scale: 4)
        let scroll = app.scrollViews["position-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 20), "No se abrió la hoja de posición")
        let manualButton = app.buttons["Poner precio a mano"]
        scrollTo(manualButton, in: scroll)
        XCTAssertTrue(manualButton.waitForExistence(timeout: 8), "Falta Poner precio a mano")
        manualButton.tap()
        let field = app.textFields["manualPriceField"]
        scrollTo(field, in: scroll)
        XCTAssertTrue(field.waitForExistence(timeout: 8), "Falta manualPriceField")
        burst("security-position-price-ojo-reposo", frames: 2, every: 0.3)
        field.tap()
        burst("security-position-price-ojo", frames: 6, every: 0.25)
    }

    /// SEC-05: colchón mínimo de Cuentas y contactos con el ojo cerrado (máscara → vacío al tocar).
    func testAccountsFloorEyeClosed() throws {
        launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoAccounts", "-MiBancoDemoFloor", "-MiBancoDemoPrivate"],
               scale: 4)
        XCTAssertTrue(app.navigationBars["Cuentas y contactos"].waitForExistence(timeout: 20),
                      "No se abrió Cuentas y contactos")
        let floor = app.textFields["accounts-floor-field-rev"]
        scrollTo(floor)
        XCTAssertTrue(floor.waitForExistence(timeout: 8), "Falta el colchón mínimo de Revolut")
        burst("security-accounts-floor-ojo-reposo", frames: 2, every: 0.3)
        floor.tap()
        burst("security-accounts-floor-ojo", frames: 6, every: 0.25)
    }
}
