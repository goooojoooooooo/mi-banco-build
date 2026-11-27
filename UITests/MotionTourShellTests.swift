import XCTest

/// Ráfagas de movimiento del flujo «Marco y hojas» (nadie más edita este fichero): el arranque «logo en piezas» fotograma
/// a fotograma (entero, saltado con un toque, en Sutil, con Reducir movimiento y con el ojo cerrado), las piezas sobre el
/// bloqueo, la salida al desbloquear y los importes que ruedan en las hojas.
///
/// El arranque empieza en cuanto se abre la app, antes de que una prueba pueda hacer su primera captura. Por eso las
/// ráfagas del arranque piden a la app que espere unos segundos en negro (`-MiBancoDemoLaunchHold`, solo DEBUG) y leen
/// de ella cuándo empieza (`launch-probe` → `empieza=`), para capturar desde justo antes del primer fotograma.
final class MotionTourShellTests: MotionTourCase {

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func probe() -> [String: String] {
        let value = element("launch-probe").value as? String ?? ""
        var out: [String: String] = [:]
        for pair in value.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 { out[String(parts[0])] = String(parts[1]) }
        }
        return out
    }

    private func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return condition()
    }

    /// Duerme hasta `lead` segundos antes (o `-lead` después) de que empiece el arranque que la app tiene en espera
    /// (o las piezas del bloqueo).
    private func sleepUntilLaunchStarts(lead: TimeInterval) throws {
        var startsAt: Double?
        XCTAssertTrue(waitUntil(20) {
            startsAt = Double(self.probe()["empieza"] ?? "")
            return startsAt != nil
        }, "La app no publicó cuándo empieza el arranque")
        let start = try XCTUnwrap(startsAt)
        let wait = start - lead - Date().timeIntervalSince1970
        XCTAssertGreaterThan(wait, 0, "La espera del arranque se quedó corta: ya había empezado (\(wait) s)")
        if wait > 0 { Thread.sleep(forTimeInterval: wait) }
    }

    private func waitForLaunchToEnd() {
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 20), "Inicio no aparece")
        XCTAssertTrue(waitUntil(30) { !self.element("launch-layer").exists }, "El arranque no terminó")
    }

    // MARK: - Arranque

    /// El arranque entero a ×4 (5,4 s): piezas y líneas, loseta y nombre, brillo, bandas, vuelo e Inicio montándose.
    func testLaunch() throws {
        launch(["-MiBancoDemoLaunchHold", "25"])
        try sleepUntilLaunchStarts(lead: 0.3)
        burst("launch", frames: 24, every: 0.25)
    }

    /// Lo mismo con el ojo cerrado: Inicio se monta debajo sin enseñar una cifra.
    func testLaunchWithTheEyeClosed() throws {
        launch(["-MiBancoDemoLaunchHold", "25", "-MiBancoDemoPrivate"])
        try sleepUntilLaunchStarts(lead: 0.3)
        burst("launch-ojo", frames: 24, every: 0.25)
    }

    /// Un toque a mitad de las piezas (a ×16, para que el salto dure lo bastante para verlo): tres fotogramas antes del
    /// toque y, después, la marca ya entera volando a su sitio.
    func testLaunchSkip() throws {
        launch(["-MiBancoDemoLaunchHold", "25"], scale: 16)
        try sleepUntilLaunchStarts(lead: -3.5)
        burst("launch-skip-antes", frames: 3, every: 0.3)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).tap()
        burst("launch-skip", frames: 12, every: 0.2)
    }

    /// Nivel Sutil: solo un fundido (0,28 s; a ×4, 1,1 s).
    func testLaunchSubtle() throws {
        launch(["-MiBancoDemoLaunchHold", "25", "-MiBancoMotionLevel", "subtle"])
        try sleepUntilLaunchStarts(lead: 0.3)
        burst("launch-sutil", frames: 10, every: 0.18)
    }

    /// Reducir movimiento: la marca aparece con un fundido e Inicio se funde (0,52 s; a ×4, 2,1 s).
    func testLaunchReduceMotion() throws {
        launch(["-MiBancoDemoLaunchHold", "25", "-MiBancoReduceMotion"])
        try sleepUntilLaunchStarts(lead: 0.3)
        burst("launch-reducir", frames: 12, every: 0.25)
    }

    // MARK: - Bloqueo

    /// Arranque en frío con bloqueo: las piezas se montan sobre la marca del bloqueo (a ×4, 4,4 s); el botón está desde
    /// el primer fotograma.
    func testLockAssembles() throws {
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "60", "-MiBancoDemoLaunchHold", "25"])
        try sleepUntilLaunchStarts(lead: 0.3)
        burst("lock", frames: 24, every: 0.22)
    }

    /// Al desbloquear en frío (a ×8, 3,4 s): el bloqueo se funde, las bandas cruzan, la marca vuela hacia la barra
    /// superior e Inicio se monta. Desbloquea el temporizador del bloqueo de demo (el botón pediría el código del iPhone).
    func testUnlockFlight() throws {
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "14"], scale: 8)
        // El bloqueo de demo se quita a los 14 s de montarse, o algo después (las piezas, a ×8, tardan 8,8 s): se
        // empieza a capturar justo antes y se cubren 6 s.
        try sleepUntilLaunchStarts(lead: -13.7)
        burst("unlock", frames: 30, every: 0.2)
    }

    /// Lote 3 (0): desbloquear en Sutil (a ×8: el fundido dura 2,4 s). Nada vuela: el bloqueo se funde con su marca
    /// grande e Inicio aparece debajo SIN la marca de su barra, que sale de una vez al acabar el fundido. Una marca
    /// por fotograma.
    func testUnlockSubtle() throws {
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "8", "-MiBancoMotionLevel", "subtle"], scale: 8)
        try sleepUntilLaunchStarts(lead: -7.7)
        burst("unlock-sutil", frames: 18, every: 0.2)
    }

    /// Lo mismo con Reducir movimiento (a ×8: el fundido dura 1,8 s).
    func testUnlockReduceMotion() throws {
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "8", "-MiBancoReduceMotion"], scale: 8)
        try sleepUntilLaunchStarts(lead: -7.7)
        burst("unlock-reducir", frames: 18, every: 0.2)
    }

    /// I-2, como pide la revisión: el bloqueo de demo se quita a los 0,4 s de empezar las piezas (a ×8 apenas han
    /// asomado). El bloqueo se funde (2,7 s a ×8) ya sin piezas ni líneas y la marca entera vuela: nunca dos marcas.
    func testUnlockEarly() throws {
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "0.4", "-MiBancoDemoLaunchHold", "25"], scale: 8)
        try sleepUntilLaunchStarts(lead: 0.3)
        burst("unlock-early", frames: 36, every: 0.2)
    }

    /// I-2 en su peor momento: el desbloqueo llega con las dos mitades en el aire entre las líneas (2,4 s a ×8 = 0,27 s
    /// del guion).
    func testUnlockMidFlight() throws {
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "2.4", "-MiBancoDemoLaunchHold", "25"], scale: 8)
        try sleepUntilLaunchStarts(lead: 0.3)
        burst("unlock-early-mitad", frames: 44, every: 0.2)
    }

    /// I-1: el éxito de Face ID llega con la escena aún inactiva (la bandera lo simula durante 2 s). El bloqueo deja
    /// paso a la tapa de golpe (nunca los dos a medias), Inicio se monta debajo y, al volver a activa, la tapa se quita
    /// de golpe y la marca vuela sobre un Inicio que no vuelve a empezar de cero.
    func testUnlockWhileInactive() throws {
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "12", "-MiBancoDemoUnlockInactive", "2"])
        try sleepUntilLaunchStarts(lead: -11.6)
        burst("unlock-inactive", frames: 30, every: 0.2)
    }

    /// N-1: lo mismo, pero la escena vuelve a activa a los 0,2 s reales del desbloqueo, mucho antes de lo que duraría el
    /// fundido del bloqueo (2,7 s a ×8; la bandera no va a cámara lenta). El bloqueo no se funde debajo de la tapa: al
    /// quitarse la tapa no queda nada suyo y solo hay una marca, la que vuela.
    func testUnlockInactiveForAnInstant() throws {
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "14", "-MiBancoDemoUnlockInactive", "0.2"], scale: 8)
        try sleepUntilLaunchStarts(lead: -13.7)
        burst("unlock-inactive-corto", frames: 30, every: 0.2)
    }

    /// Re-bloqueo (volver de segundo plano): la marca sale quieta y entera, sin piezas (`lock-rebloqueo`, con el bloqueo
    /// en reposo: si el bloqueo de demo cumple su tiempo con la app detrás, no se acepta y vuelve a durar 10 s desde la
    /// vuelta). Después, el desbloqueo templado a ×8 (`unlock-templado`): el bloqueo se funde y la marca vuela, sin
    /// bandas, hasta la ranura de la barra de Inicio.
    func testRelockIsStatic() throws {
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "10"], scale: 8)
        let unlock = app.buttons["Desbloquear"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 20), "Falta la pantalla de bloqueo")
        XCTAssertTrue(waitUntil(30) { !unlock.exists }, "El bloqueo de demo no se quitó")
        // El vuelo en frío (3,4 s a ×8) termina antes de salir.
        Thread.sleep(forTimeInterval: 6)
        XCUIDevice.shared.press(.home)
        if !waitUntil(4, { self.app.state == .runningBackground || self.app.state == .runningBackgroundSuspended }) {
            // Con el simulador cargado el gesto de Inicio a veces no saca la app: Ajustes la manda atrás seguro.
            let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
            settings.activate()
            _ = settings.wait(for: .runningForeground, timeout: 20)
        }
        Thread.sleep(forTimeInterval: 1.5)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "La app no volvió a primer plano")
        XCTAssertTrue(unlock.waitForExistence(timeout: 8), "No se mostró el bloqueo al volver de segundo plano")
        burst("lock-rebloqueo", frames: 6, every: 0.3)
        XCTAssertTrue(unlock.exists, "El bloqueo se quitó durante la ráfaga: no estaba en reposo")
        // El bloqueo de demo se quita solo: se captura desde que empieza a fundirse.
        XCTAssertTrue(waitUntil(25) { self.probe()["fundido"] == "1" }, "El re-bloqueo de demo no se quitó")
        burst("unlock-templado", frames: 24, every: 0.2)
    }

    // MARK: - Pestañas (T1)

    /// Cambiar de pestaña a ×16 (a ×4 la entrada ya había acabado cuando la prueba hacía la primera captura, run9): el
    /// contenido llega desde 70 pt en la dirección del cambio y se funde; luego de vuelta.
    private func tabChangeBursts(_ name: String, extra: [String] = []) {
        launch(extra, scale: 16)
        waitForLaunchToEnd()
        let gasto = app.tabBars.buttons["Gasto"]
        XCTAssertTrue(gasto.waitForExistence(timeout: 10), "Falta la pestaña Gasto")
        // Un toque normal en la barra de cristal a veces no cambia de pestaña en el simulador (Plan3TapTests lo sabe):
        // una pulsación corta en su centro sí.
        Thread.sleep(forTimeInterval: 1)
        gasto.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).press(forDuration: 0.12)
        burst(name, frames: 12, every: 0.4)
        XCTAssertTrue(gasto.isSelected, "No se cambió a Gasto: la ráfaga no enseña el cambio")
        app.tabBars.buttons["Inicio"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).press(forDuration: 0.12)
        burst(name + "-vuelta", frames: 12, every: 0.4)
    }

    /// Ronda 1 del lote 3: el FUNDIDO de la entrada de pestaña, grabado desde ANTES del cambio. La app cambia sola de
    /// Inicio a Gasto (`-MiBancoDemoTabSwitch`) y la ráfaga empieza 0,3 s antes; a ×16 el fundido dura ~3 s (a ×16, con
    /// Reducir movimiento, solo el fundido).
    private func tabFadeBursts(_ name: String, extra: [String] = []) throws {
        launch(["-MiBancoDemoTabSwitch", "40"] + extra, scale: 16)
        waitForLaunchToEnd()
        var at: Double?
        XCTAssertTrue(waitUntil(20) {
            at = Double(self.probe()["cambioPestana"] ?? "")
            return at != nil
        }, "La app no publicó cuándo cambia de pestaña")
        let wait = try XCTUnwrap(at) - 0.3 - Date().timeIntervalSince1970
        XCTAssertGreaterThan(wait, 0, "El cambio de pestaña ya había pasado (\(wait) s)")
        if wait > 0 { Thread.sleep(forTimeInterval: wait) }
        burst(name, frames: 16, every: 0.25)
    }

    func testTabFade() throws { try tabFadeBursts("tab-change-fundido") }

    func testTabFadeReduceMotion() throws { try tabFadeBursts("tab-change-fundido-reducir", extra: ["-MiBancoReduceMotion"]) }

    func testTabChange() throws { tabChangeBursts("tab-change") }

    func testTabChangeWithTheEyeClosed() throws { tabChangeBursts("tab-change-ojo", extra: ["-MiBancoDemoPrivate"]) }

    func testTabChangeReduceMotion() throws { tabChangeBursts("tab-change-reducir", extra: ["-MiBancoReduceMotion"]) }

    // MARK: - Aviso dentro de la app (C6)

    /// En Gasto llega un pago (la demo lo mete a los ~4 s reales): a ×4 el aviso cae, se despliega con «Te quedan»
    /// rodando y dos acciones, se recoge y se va (≈ 14,6 s).
    private func bannerBursts(_ name: String, extra: [String] = []) {
        launch(["-MiBancoDemoArrival", "-MiBancoDemoScreen", "gasto"] + extra)
        let banner = element("in-app-banner")
        XCTAssertTrue(banner.waitForExistence(timeout: 30), "No apareció el aviso dentro de la app")
        burst(name, frames: 30, every: 0.6)
    }

    func testInAppBanner() throws { bannerBursts("in-app-banner") }

    func testInAppBannerWithTheEyeClosed() throws { bannerBursts("in-app-banner-ojo", extra: ["-MiBancoDemoPrivate"]) }

    func testInAppBannerReduceMotion() throws { bannerBursts("in-app-banner-reducir", extra: ["-MiBancoReduceMotion"]) }

    // MARK: - Importes que ruedan en las hojas

    /// Fila → detalle a ×4: el importe grande entra y rueda; «Te quedaban» empieza oculto y rueda cuando el importe se posa.
    func testDetailAmounts() throws {
        launch()
        waitForLaunchToEnd()
        let row = app.buttons.matching(identifier: "movementRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "No hay filas de movimientos")
        row.tap()
        burst("detail-amount", frames: 24, every: 0.33)
        // «No es mío»: la raya sobre el importe.
        app.swipeUp()
        let flag = app.buttons["No es mío"]
        XCTAssertTrue(flag.waitForExistence(timeout: 5), "Falta la acción «No es mío»")
        flag.tap()
        app.swipeDown()
        burst("detail-flagged", frames: 3, every: 0.5)
    }

    /// C4 (D1): fila → detalle a ×4, desde el toque: el importe sale de la fila y vuela con un arco a su sitio; las
    /// líneas entran desde 0,15 s; «Te quedaban» rueda cuando el importe se posa; las barras del historial crecen 40 ms
    /// una detrás de otra. Luego se cierra (`detail-dismiss`).
    /// m-4 (lote final): la hoja se cierra SOLA a los 4,5 s de abrirse (`-MiBancoDemoAutoCloseDetail`): un toque en
    /// «Cerrar» espera a que la app quede quieta y la ráfaga del cierre empezaba con la hoja ya cerrada. La segunda
    /// ráfaga empieza antes del cierre y lo cubre entero.
    private func rowDetailBursts(_ name: String, extra: [String] = []) {
        launch(extra + ["-MiBancoDemoAutoCloseDetail", "9"])
        waitForLaunchToEnd()
        let row = app.buttons.matching(identifier: "movementRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "No hay filas de movimientos")
        XCTAssertTrue(waitUntil(15) { row.isHittable }, "La primera fila no se puede tocar")
        row.tap()
        burst(name, frames: 24, every: 0.12)
        XCTAssertTrue(app.buttons["Cerrar"].exists, "La hoja se cerró antes de grabar su cierre")
        // I-4 (ronda 1): la ráfaga del cierre empieza 0,3 s antes del cierre que la app publica (`cierreDetalle`).
        let closeAt = Double(probe()["cierreDetalle"] ?? "") ?? 0
        XCTAssertGreaterThan(closeAt, 0, "La app no publicó cuándo se cierra la hoja")
        let wait = closeAt - 0.3 - Date().timeIntervalSince1970
        XCTAssertGreaterThan(wait, 0, "La hoja ya se había cerrado al empezar la ráfaga del cierre")
        if wait > 0 { Thread.sleep(forTimeInterval: wait) }
        burst(name == "row-detail" ? "detail-dismiss" : name + "-cerrar", frames: 14, every: 0.15)
    }

    func testRowDetail() throws { rowDetailBursts("row-detail") }

    func testRowDetailWithTheEyeClosed() throws { rowDetailBursts("row-detail-ojo", extra: ["-MiBancoDemoPrivate"]) }

    func testRowDetailReduceMotion() throws { rowDetailBursts("row-detail-reducir", extra: ["-MiBancoReduceMotion"]) }

    /// C8 (C6): la tarjeta del abanico vuela hasta la cabecera de su banco, que se abre encima de Inicio (la pestaña no
    /// cambia). Luego «Inicio» lo cierra (`card-flight-vuelta`). A ×4.
    private func cardFlightBursts(_ name: String, extra: [String] = []) {
        launch(extra + ["-MiBancoDemoCardElements"])
        waitForLaunchToEnd()
        let anchor = NSPredicate(format: "label ENDSWITH %@", " de 4")
        let carousel = app.descendants(matching: .any).matching(anchor).firstMatch
        XCTAssertTrue(carousel.waitForExistence(timeout: 15), "Falta el carrusel")
        carousel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).press(forDuration: 1.6)
        XCTAssertTrue(app.staticTexts["Tus tarjetas"].waitForExistence(timeout: 15), "No se abrió el abanico")
        let card = app.buttons["wallet-card-rev"]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Falta la tarjeta de Revolut")
        XCTAssertTrue(waitUntil(15) { card.isHittable }, "La tarjeta de Revolut no se puede tocar")
        card.tap()
        burst(name, frames: 24, every: 0.15)
        let back = app.buttons["bank-over-home-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 10), "Falta «Inicio» en el banco")
        back.tap()
        burst(name + "-vuelta", frames: 8, every: 0.15)
    }

    func testCardFlight() throws { cardFlightBursts("card-flight") }

    func testCardFlightWithTheEyeClosed() throws { cardFlightBursts("card-flight-ojo", extra: ["-MiBancoDemoPrivate"]) }

    // Sin variante con Reducir movimiento: con Reducir no hay abanico (no se levanta la tarjeta, diseño de la línea A)
    // ni vuelo; el banco desde Ajustes con Reducir lo cubre `testReduceMotionWalk`.

    /// Ronda 1 (kit m-4): el ojo se cierra (solo, `-MiBancoDemoCloseEyeOverRoll`) mientras el total aún rueda tras el
    /// arranque. Se graba desde 1 s ANTES del cambio: el barajado y los puntos encima de la cifra, sin ningún fotograma
    /// con una casilla vacía ni con un dígito y su punto a la vez.
    func testEyeClosesOverARollingFigure() throws {
        // Ronda 2 (N-6): a cámara lenta (×4) y con el texto dibujado de cada importe (`-MiBancoDrawnText`).
        launch(["-MiBancoDemoCloseEyeOverRoll", "4.5", "-MiBancoDrawnText"], scale: 4)
        XCTAssertTrue(waitUntil(20) { (self.probe()["ojoCierraEn"] ?? "-") != "-" }, "La app no dijo cuándo cierra el ojo")
        let at = Double(probe()["ojoCierraEn"] ?? "") ?? 0
        let wait = at - 1 - Date().timeIntervalSince1970
        XCTAssertGreaterThan(wait, 0, "El ojo ya se había cerrado al empezar la ráfaga")
        if wait > 0 { Thread.sleep(forTimeInterval: wait) }
        burst("eye-close-rolling", frames: 14, every: 0.1)
        // Desde el cierre, ningún importe dibuja un dígito (ni al azar): se mira varias veces mientras la ráfaga sigue.
        XCTAssertGreaterThan(Date().timeIntervalSince1970, at, "La comprobación empieza antes del cierre")
        for look in 0..<8 {
            let digits = NSPredicate(format: "value MATCHES %@", ".*[0-9].*€.*")
            let drawn = app.descendants(matching: .any).matching(digits).allElementsBoundByIndex.map { $0.value as? String ?? "" }
            XCTAssertEqual(drawn, [], "Mirada \(look): con el ojo cerrado se dibujan dígitos: \(drawn)")
            Thread.sleep(forTimeInterval: 0.15)
        }
        burst("eye-close-rolling-despues", frames: 6, every: 0.2)
    }

    /// C4 (D2): la categoría de un pago: la ficha blanca se desliza a la elegida y su símbolo bota; luego se pliega.
    func testCategoryPick() throws {
        launch()
        waitForLaunchToEnd()
        let row = app.buttons.matching(identifier: "movementRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "No hay filas de movimientos")
        XCTAssertTrue(waitUntil(15) { row.isHittable }, "La primera fila no se puede tocar")
        row.tap()
        let chip = element("category-chip")
        XCTAssertTrue(chip.waitForExistence(timeout: 8), "La primera fila no es un pago con categoría")
        // Ronda 1 (I-2): los grupos de debajo del importe no reciben toques hasta que el importe se posa («Te quedaban»
        // dice entonces su cifra): se espera a eso antes de tocar el chip.
        let left = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Te quedaban")).firstMatch
        XCTAssertTrue(waitUntil(20) { left.label.hasSuffix(" euros") }, "El importe no llegó a posarse")
        // Ronda 2 (N-2): el grupo recibe toques cuando su entrada ya se ve (retardo + muelle `enter`, a ×4 ~1,5 s).
        Thread.sleep(forTimeInterval: 3)
        chip.tap()
        let tile = element("category-tile-ocio")
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "Falta la ficha Ocio")
        Thread.sleep(forTimeInterval: 2)
        tile.tap()
        burst("category-pick", frames: 10, every: 0.12)
    }

    /// Lo mismo con el ojo cerrado: ni una cifra en ningún fotograma.
    func testDetailAmountsWithTheEyeClosed() throws {
        launch(["-MiBancoDemoPrivate"])
        waitForLaunchToEnd()
        let row = app.buttons.matching(identifier: "movementRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "No hay filas de movimientos")
        row.tap()
        burst("detail-amount-ojo", frames: 24, every: 0.33)
        // Más abajo, el historial del comercio: con el ojo cerrado sus importes son máscaras, no cifras difuminadas.
        app.swipeUp()
        burst("detail-ojo-historial", frames: 2, every: 0.5)
    }

    /// El valor de una posición rueda al abrir su hoja.
    func testPositionAmount() throws {
        launch(["-MiBancoDemoPosition"])
        XCTAssertTrue(app.buttons["Cerrar"].waitForExistence(timeout: 30), "No se abrió la hoja de la posición")
        burst("position-amount", frames: 12, every: 0.3)
    }

    /// La hoja de una posición con el ojo cerrado: el valor es la máscara y, más abajo, los datos y las operaciones
    /// también (máscaras, no texto difuminado).
    func testPositionWithTheEyeClosed() throws {
        launch(["-MiBancoDemoPosition", "-MiBancoDemoPrivate"])
        XCTAssertTrue(app.buttons["Cerrar"].waitForExistence(timeout: 30), "No se abrió la hoja de la posición")
        burst("position-amount-ojo", frames: 6, every: 0.3)
        app.swipeUp()
        burst("position-ojo-abajo", frames: 2, every: 0.5)
    }

    /// El resumen con el ojo cerrado: ninguna cifra en ninguna línea.
    func testBriefingWithTheEyeClosed() throws {
        launch(["-MiBancoDemoBriefing", "busy", "-MiBancoDemoPrivate"])
        XCTAssertTrue(app.buttons["Vale"].waitForExistence(timeout: 30), "La hoja del resumen no se abrió")
        burst("briefing-total-ojo", frames: 8, every: 0.3)
    }

    /// C5 (B1): el resumen abierto desde la marca de Inicio, desde el toque: los bloques suben uno detrás de otro
    /// (120 ms × 0,92ⁿ) y sus importes ruedan.
    private func briefingBursts(_ name: String, extra: [String] = []) {
        launch(["-MiBancoDemoBriefing", "busy"] + extra)
        let done = app.buttons["Vale"]
        XCTAssertTrue(done.waitForExistence(timeout: 30), "La hoja del resumen no se abrió")
        done.tap()
        XCTAssertTrue(waitUntil(10) { !done.exists }, "La hoja del resumen no se cerró")
        let open = app.buttons["Tu resumen"]
        XCTAssertTrue(open.waitForExistence(timeout: 10), "Falta el botón «Tu resumen» de Inicio")
        open.tap()
        burst(name, frames: 16, every: 0.15)
    }

    func testBriefingEntrance() throws { briefingBursts("briefing") }

    func testBriefingEntranceWithTheEyeClosed() throws { briefingBursts("briefing-ojo", extra: ["-MiBancoDemoPrivate"]) }

    func testBriefingEntranceReduceMotion() throws { briefingBursts("briefing-reducir", extra: ["-MiBancoReduceMotion"]) }

    /// C5 (B2): «Escuchar»: las 28 barras se mueven encima de «Vale» mientras habla; «Parar» las funde.
    func testBriefingVoice() throws {
        launch(["-MiBancoDemoBriefing", "busy"])
        let listen = app.buttons["briefing-listen"]
        XCTAssertTrue(listen.waitForExistence(timeout: 30), "Falta «Escuchar»")
        Thread.sleep(forTimeInterval: 3)
        listen.tap()
        burst("briefing-voice", frames: 8, every: 0.15)
        listen.tap()
        burst("briefing-voice-parar", frames: 4, every: 0.15)
    }

    /// El total del resumen rueda dentro de su frase.
    func testBriefingTotal() throws {
        launch(["-MiBancoDemoBriefing", "busy"])
        XCTAssertTrue(app.buttons["Vale"].waitForExistence(timeout: 30), "La hoja del resumen no se abrió")
        burst("briefing-total", frames: 12, every: 0.3)
    }
}
