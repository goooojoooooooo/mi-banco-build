import XCTest

final class BanksUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-MiBancoDemo"] + extra + ["-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for name in ["Permitir", "Allow"] {
            let b = springboard.alerts.buttons[name]
            if b.waitForExistence(timeout: 2) { b.tap(); break }
        }
        return app
    }

    func testBanksScreenShowsStatus() {
        let app = launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoBanks"])

        let revRow = app.buttons["settings-bank-rev"]
        XCTAssertTrue(revRow.waitForExistence(timeout: 15), "Debe existir la fila de Revolut en Ajustes › Bancos")
        XCTAssertTrue(
            app.staticTexts["Actualizado hace 5 min · exacto"].waitForExistence(timeout: 10),
            "Debe verse el estado exacto de Revolut"
        )
        XCTAssertTrue(
            app.staticTexts["Importa su extracto"].waitForExistence(timeout: 10),
            "Debe verse el estado de Trade Republic sin conexión"
        )

        let imaRow = app.buttons["settings-bank-ima"]
        XCTAssertTrue(imaRow.waitForExistence(timeout: 5), "Debe existir la fila de imagin")
        imaRow.tap()

        XCTAssertTrue(
            app.staticTexts["Caduca en 9 días"].waitForExistence(timeout: 10),
            "En la pantalla de imagin debe verse que el consentimiento caduca en 9 días"
        )
        let renewBtn = app.buttons["Renovar conexión"]
        XCTAssertTrue(
            renewBtn.waitForExistence(timeout: 5),
            "Debe mostrarse el botón para renovar la conexión"
        )
        XCTAssertTrue(
            app.buttons["bank-import-statement"].waitForExistence(timeout: 5),
            "Debe mostrarse el botón para importar extracto"
        )
        // U49 #9: tocar «Renovar conexión» y afirmar su efecto visible en la demo.
        renewBtn.tap()
        XCTAssertTrue(
            app.staticTexts["Esperando a imagin…"].waitForExistence(timeout: 6),
            "U49: tocar Renovar conexión debe iniciar el estado de espera en demo"
        )
    }

    /// Unión #5 (mapa §4.3, rulings «Para la unión» #4): con el día de la demo fijado, Ajustes y la pantalla del banco cuentan
    /// desde ese día y no desde el reloj de verdad (si no, «hace 5 min» sería «hace meses» y el permiso de imagin, caducado).
    func testFixedDemoDayKeepsBankStatus() {
        let app = launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoBanks", "-MiBancoDemoToday", "2026-02-28"])

        XCTAssertTrue(app.buttons["settings-bank-rev"].waitForExistence(timeout: 15), "Debe existir la fila de Revolut en Ajustes › Bancos")
        XCTAssertTrue(
            app.staticTexts["Actualizado hace 5 min · exacto"].waitForExistence(timeout: 10),
            "Con -MiBancoDemoToday, Revolut debe contar desde el día de la demo"
        )
        let imaRow = app.buttons["settings-bank-ima"]
        XCTAssertTrue(imaRow.waitForExistence(timeout: 5), "Debe existir la fila de imagin")
        imaRow.tap()
        XCTAssertTrue(
            app.staticTexts["Caduca en 9 días"].waitForExistence(timeout: 10),
            "Con -MiBancoDemoToday, el permiso de imagin caduca en 9 días contados desde el día de la demo"
        )
        let expired = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "caducó"))
        XCTAssertEqual(expired.count, 0, "Con -MiBancoDemoToday no puede verse el permiso de imagin como caducado")
    }

    func testConnectionGuideSteps() {
        let app = launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoGuide"])

        XCTAssertTrue(
            app.staticTexts["Paso 1 de 4"].waitForExistence(timeout: 15),
            "Debe abrirse la guía de conexión en el paso 1"
        )
        XCTAssertTrue(
            app.staticTexts["Crea tu cuenta gratis"].waitForExistence(timeout: 5),
            "Debe verse el título del paso 1"
        )

        let nextButton = app.buttons["guide-next"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        nextButton.tap()

        XCTAssertTrue(
            app.staticTexts["Paso 2 de 4"].waitForExistence(timeout: 5),
            "Debe avanzar al paso 2"
        )
        let copyButton = app.buttons["guide-copy-redirect"]
        XCTAssertTrue(copyButton.waitForExistence(timeout: 5))
        copyButton.tap()
        XCTAssertTrue(
            app.staticTexts["Copiada"].waitForExistence(timeout: 5),
            "Copiar dirección debe cambiar la etiqueta a Copiada"
        )

        // U59: avanzar al paso 4 y comprobar el aviso de la clave no guardada.
        nextButton.tap()
        XCTAssertTrue(app.staticTexts["Paso 3 de 4"].waitForExistence(timeout: 5))
        nextButton.tap()
        XCTAssertTrue(app.staticTexts["Paso 4 de 4"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["Si sales de la app antes de guardar, tendrás que elegir la clave otra vez: no la guardo hasta que toques «Guardar»."].waitForExistence(timeout: 5),
            "U59: falta el aviso sobre la clave no guardada en el paso 4"
        )
    }

    /// U13 #4: en el reverso de la tarjeta de Revolut conectado, tocar «Actualizar» muestra confirmación visual.
    func testConnectedBankBackRefresh() {
        // `-MiBancoDemoCardElements` (DEBUG): el reverso de la tarjeta queda a la vista de XCUITest (U80).
        let app = launch(["-MiBancoDemoBanks", "-MiBancoDemoCard", "rev", "-MiBancoDemoCardElements"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15))

        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Revolut' AND label CONTAINS '2 de 4'"))
            .firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Falta la tarjeta de Revolut")
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()

        let refreshBtn = app.buttons["bank-card-refresh"]
        XCTAssertTrue(refreshBtn.waitForExistence(timeout: 8), "U13: falta el botón Actualizar en el reverso")
        // U74 (A-I1): el reverso ya dice «Actualizado hace 5 min · exacto» antes del toque, así que se mira SOLO el botón:
        // antes dice «Actualizar» y no lleva la marca; después del toque pasa a «Actualizado» con la marca.
        XCTAssertFalse(refreshBtn.label.contains("Actualizado"), "U13: el botón ya decía Actualizado antes del toque: \(refreshBtn.label)")
        XCTAssertFalse(app.descendants(matching: .any)["bank-card-refreshed"].exists, "U13: la marca ya estaba antes del toque")
        // U80: con el carrusel en `.contain`, el elemento de accesibilidad de «Actualizar» ocupa la tarjeta entera
        // (`{{32, 124}, {376, 236}}` en 45071172797) y `tap()` cae en su centro, que es el reverso (y le da la vuelta). Se toca
        // donde está el botón: abajo a la derecha del reverso.
        refreshBtn.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.82)).tap()
        // Mientras actualiza, el botón deja sitio a la rueda de progreso y vuelve con «Actualizado» unos 2 s: se espera al
        // botón con esa etiqueta (por consulta, porque en medio no existe).
        let refreshed = app.buttons.matching(
            NSPredicate(format: "identifier == 'bank-card-refresh' AND label CONTAINS 'Actualizado'")
        ).firstMatch
        XCTAssertTrue(refreshed.waitForExistence(timeout: 10), "U13: Actualizar no pasó a «Actualizado» tras el toque")
    }

    /// U45: Ajustes › Bancos calcula «Actualizado hace…» en vivo (240 min → «hace 4 h»).
    func testBankRowTimeIsLive() {
        let app = launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoBanks", "-MiBancoDemoBankSyncAgo", "240"])
        XCTAssertTrue(
            app.staticTexts["Actualizado hace 4 h · exacto"].waitForExistence(timeout: 15),
            "U45: la fila de Revolut debe mostrar «Actualizado hace 4 h · exacto»"
        )
    }

    /// U74 (B-M2) + U45: con la pantalla abierta, la fila cambia sola al pasar el minuto (59 min → 1 h). Con la línea guardada
    /// en la instantánea del arranque se quedaría en «hace 59 min» para siempre.
    func testBankRowTimeChangesWhileOpen() {
        let app = launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoBanks", "-MiBancoDemoBankSyncAgo", "59"])
        XCTAssertTrue(
            app.staticTexts["Actualizado hace 59 min · exacto"].waitForExistence(timeout: 15),
            "U45: al abrir, la fila de Revolut debe decir «Actualizado hace 59 min · exacto»"
        )
        // El minuto 60 llega como mucho 60 s después del arranque y `TimelineView(.everyMinute)` redibuja en el siguiente
        // cambio de minuto: hasta ~2 min sin tocar nada.
        XCTAssertTrue(
            app.staticTexts["Actualizado hace 1 h · exacto"].waitForExistence(timeout: 150),
            "U45: la fila no siguió al reloj con la pantalla abierta"
        )
    }

    /// U49 #1: tocar «Preparar conexión» en Ajustes abre el paso 1 de la guía.
    func testPrepareConnectionRowOpensGuide() {
        let app = launch(["-MiBancoDemoScreen", "ajustes"])
        let row = app.buttons["settings-prepare-connection"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "U49: falta settings-prepare-connection")
        row.tap()
        XCTAssertTrue(app.staticTexts["Crea tu cuenta gratis"].waitForExistence(timeout: 8), "U49: no abrió el paso 1 de la guía")
    }

    /// U49 #2 + U50: cancelar espera pregunta si ya lo aprobaste; «Dejarlo» vuelve al estado normal.
    func testCancelWaitAsksIfApproved() {
        let app = launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoConnectPhase", "waitingForBank", "rev"])
        let revRow = app.buttons["settings-bank-rev"]
        XCTAssertTrue(revRow.waitForExistence(timeout: 15))
        revRow.tap()

        let cancelWait = app.buttons["bank-cancel-wait"]
        XCTAssertTrue(cancelWait.waitForExistence(timeout: 8), "U49: falta bank-cancel-wait")
        cancelWait.tap()

        XCTAssertTrue(app.staticTexts["¿Ya lo has aprobado en la app de Revolut?"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["Seguir"].exists)
        XCTAssertTrue(app.buttons["Empezar de nuevo"].exists)

        let leave = app.buttons["Dejarlo"]
        XCTAssertTrue(leave.waitForExistence(timeout: 5), "U50: falta el botón Dejarlo")
        leave.tap()
        XCTAssertTrue(app.buttons["bank-import-statement"].waitForExistence(timeout: 6))
        XCTAssertFalse(leave.exists, "U50: Dejarlo no volvió al estado normal")
    }

    /// U49 #3: en fase `chooseASPSP`, «Elegir Revolut en la lista» abre el buscador de bancos.
    func testChooseBankInListOpensPicker() {
        let app = launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoConnectPhase", "chooseASPSP", "rev"])
        let revRow = app.buttons["settings-bank-rev"]
        XCTAssertTrue(revRow.waitForExistence(timeout: 15))
        revRow.tap()

        let choose = app.buttons["Elegir Revolut en la lista"]
        XCTAssertTrue(choose.waitForExistence(timeout: 8), "U49: falta Elegir Revolut en la lista")
        XCTAssertFalse(app.navigationBars["Elegir Revolut"].exists, "U49: el selector ya estaba abierto antes del toque")
        choose.tap()
        // U80: con dos bancos en la lista `ASPSPPickerView` no enseña buscador: se afirma su pantalla y su lista.
        XCTAssertTrue(app.navigationBars["Elegir Revolut"].waitForExistence(timeout: 8), "U49: no se abrió ASPSPPickerView")
        XCTAssertTrue(app.staticTexts["Elige tu banco en la lista"].exists, "U49: falta la lista de ASPSPPickerView")
        XCTAssertTrue(app.buttons["imaginBank"].exists, "U49: la lista de ASPSPPickerView no enseña los bancos")
    }

    /// U49 #4 + U55: confirmaciones «Desconectar» y «Olvidar clave y conexiones» con «Cancelar».
    func testDisconnectAndForgetDialogsCancel() {
        let app = launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoBanks"])
        let revRow = app.buttons["settings-bank-rev"]
        XCTAssertTrue(revRow.waitForExistence(timeout: 15))
        revRow.tap()

        let disconnect = app.buttons["Desconectar"]
        XCTAssertTrue(disconnect.waitForExistence(timeout: 8))
        disconnect.tap()
        XCTAssertTrue(app.staticTexts["Desconectar Revolut"].waitForExistence(timeout: 6))
        app.buttons["Cancelar"].tap()
        XCTAssertTrue(disconnect.waitForExistence(timeout: 6), "U49: tras Cancelar debe seguir conectado")

        let forget = app.buttons["Olvidar clave y conexiones"]
        XCTAssertTrue(forget.waitForExistence(timeout: 6))
        forget.tap()
        XCTAssertTrue(app.staticTexts["Se borran la clave de Enable Banking y las sesiones de este iPhone. Tus movimientos se quedan."].waitForExistence(timeout: 6))
        app.buttons["Cancelar"].tap()
        XCTAssertTrue(disconnect.waitForExistence(timeout: 6), "U49: tras Cancelar Olvidar debe seguir conectado")
    }

    /// U49 #5 + H10 + U55: «Importar extracto» y «Elegir clave» abren el selector de archivos único del sistema.
    func testImportStatementOpensSystemPicker() {
        let cancelNames = ["Cancelar", "Cancel", "Cerrar", "Close"]

        let app1 = launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoBanks"])
        let revRow = app1.buttons["settings-bank-rev"]
        XCTAssertTrue(revRow.waitForExistence(timeout: 15))
        revRow.tap()

        let importBtn = app1.buttons["bank-import-statement"]
        XCTAssertTrue(importBtn.waitForExistence(timeout: 8))
        importBtn.tap()
        let pickerCancel1 = app1.buttons.matching(NSPredicate(format: "label IN %@", cancelNames)).firstMatch
        XCTAssertTrue(pickerCancel1.waitForExistence(timeout: 20), "U49/H10: Importar extracto no abrió el selector del sistema")
        pickerCancel1.tap()
        XCTAssertTrue(importBtn.waitForExistence(timeout: 8), "U49: al cancelar el selector no volvió a Revolut")

        let app2 = launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoGuide"])
        XCTAssertTrue(app2.staticTexts["Paso 1 de 4"].waitForExistence(timeout: 15))
        for _ in 0..<3 {
            app2.buttons["guide-next"].tap()
        }
        let pickKey = app2.buttons["Elegir clave"]
        XCTAssertTrue(pickKey.waitForExistence(timeout: 8))
        pickKey.tap()
        let pickerCancel2 = app2.buttons.matching(NSPredicate(format: "label IN %@", cancelNames)).firstMatch
        XCTAssertTrue(pickerCancel2.waitForExistence(timeout: 20), "U49/H10: Elegir clave no abrió el selector del sistema")
        pickerCancel2.tap()
        XCTAssertTrue(pickKey.waitForExistence(timeout: 8), "U49: al cancelar el selector no volvió al paso 4")
    }

    /// U49 #8: «Paso anterior» retrocede y «Guardar» con clave de demo muestra los botones de conexión.
    func testGuideStepsButtons() {
        let app = launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoGuide", "-MiBancoDemoGuideKey"])
        XCTAssertTrue(app.staticTexts["Paso 1 de 4"].waitForExistence(timeout: 15))

        let next = app.buttons["guide-next"]
        next.tap()
        XCTAssertTrue(app.staticTexts["Paso 2 de 4"].waitForExistence(timeout: 5))
        app.buttons["Paso anterior"].tap()
        XCTAssertTrue(app.staticTexts["Paso 1 de 4"].waitForExistence(timeout: 5), "U49: Paso anterior no volvió al paso 1")

        for _ in 0..<3 {
            next.tap()
        }
        XCTAssertTrue(app.staticTexts["Paso 4 de 4"].waitForExistence(timeout: 5))
        let save = app.buttons["Guardar"]
        XCTAssertTrue(save.waitForExistence(timeout: 6), "U49: falta Guardar en el paso 4 con clave de demo")
        save.tap()
        XCTAssertTrue(app.buttons["Conectar Revolut"].waitForExistence(timeout: 8), "U49: Guardar no pasó a los botones de conexión")
    }

    /// U78 (U49 #8, B-M5): «Abrir Enable Banking» del paso 1 pone Safari en primer plano.
    func testGuideOpensEnableBankingInSafari() {
        let app = launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoGuide"])
        XCTAssertTrue(app.staticTexts["Paso 1 de 4"].waitForExistence(timeout: 15))
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        let open = app.buttons["Abrir Enable Banking"]
        XCTAssertTrue(open.waitForExistence(timeout: 5), "U49: falta «Abrir Enable Banking»")
        open.tap()
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 20), "U49: «Abrir Enable Banking» no abrió Safari")
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
    }

    /// U55: la confirmación de «Desconectar» (ahora en `RootSheet`) se cierra al salir a segundo plano.
    func testDisconnectConfirmClosesOnBackground() {
        let app = launch(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoBanks"])
        let revRow = app.buttons["settings-bank-rev"]
        XCTAssertTrue(revRow.waitForExistence(timeout: 15))
        revRow.tap()

        app.buttons["Desconectar"].tap()
        let cancel = app.buttons["Cancelar"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 6), "U55: falta Cancelar en la confirmación")

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1.0)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        XCTAssertFalse(cancel.waitForExistence(timeout: 2), "U55: la confirmación de Desconectar siguió abierta tras segundo plano")
    }

    /// Segundos tras el arranque a los que la demo «toca» el aviso de la mañana (`-MiBancoDemoRouteAfter`, solo DEBUG). El
    /// resumen de hoy se da por visto al arrancar (`-MiBancoDemoRoute briefing`), así que el resumen automático no sube solo:
    /// lo único que puede presentarlo es la ruta del aviso (`openManualBriefing`).
    private let routeDelay: TimeInterval = 18

    private func launchWithLateBriefingRoute(_ extra: [String]) -> (XCUIApplication, Date) {
        let start = Date()
        let app = launch(extra + ["-MiBancoDemoBriefing", "quiet", "-MiBancoDemoRoute", "briefing",
                                  "-MiBancoDemoRouteAfter", String(Int(routeDelay))])
        return (app, start)
    }

    /// U76 (B-I3) + U55: con la confirmación de «Desconectar» ya abierta, llega el aviso de la mañana: la confirmación sigue y
    /// el resumen NO se presenta encima.
    func testNoBriefingOverConfirm() {
        let (app, start) = launchWithLateBriefingRoute(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoBanks"])
        let revRow = app.buttons["settings-bank-rev"]
        XCTAssertTrue(revRow.waitForExistence(timeout: 15))
        revRow.tap()

        let disconnect = app.buttons["Desconectar"]
        XCTAssertTrue(disconnect.waitForExistence(timeout: 8))
        disconnect.tap()
        let cancel = app.buttons["Cancelar"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 6), "U55: falta Cancelar en la confirmación")
        XCTAssertLessThan(Date().timeIntervalSince(start), routeDelay - 1,
                          "La confirmación tenía que estar abierta antes de que llegara el aviso")
        XCTAssertFalse(app.buttons["Vale"].exists, "U55: el resumen ya estaba encima antes del aviso")

        // Se espera a que pase el aviso (más los 350 ms de la ruta) mirando que el resumen nunca sube.
        let deadline = start.addingTimeInterval(routeDelay + 6)
        while Date() < deadline {
            XCTAssertFalse(app.buttons["Vale"].exists, "U76: el aviso de la mañana abrió el resumen encima de la confirmación")
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(cancel.exists, "U76: la confirmación de Desconectar se cerró al llegar el aviso")
        XCTAssertFalse(app.buttons["Vale"].waitForExistence(timeout: 2), "U76: el resumen subió encima de la confirmación")
    }

    /// U76, caso de control: con los mismos argumentos y SIN abrir la confirmación, el aviso de la mañana sí abre el resumen.
    func testLateBriefingRouteOpensBriefing() {
        let (app, _) = launchWithLateBriefingRoute(["-MiBancoDemoScreen", "ajustes", "-MiBancoDemoBanks"])
        XCTAssertTrue(app.buttons["settings-bank-rev"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Vale"].exists, "Control: el resumen no debe subir antes del aviso")
        XCTAssertTrue(app.buttons["Vale"].waitForExistence(timeout: routeDelay + 10),
                      "Control: el aviso de la mañana debía abrir el resumen")
    }

    /// U58: el resumen del día no aparece mientras hay una conexión bancaria activa (`finishing`).
    func testNoBriefingDuringBankConnection() {
        let app = launch(["-MiBancoDemoConnectPhase", "finishing", "rev", "-MiBancoDemoBriefing", "quiet"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Vale"].waitForExistence(timeout: 5), "U58: el resumen subió durante una conexión bancaria")
    }

    /// U58, caso de control: sin la conexión a medias, el mismo resumen de demo sí sube al arrancar.
    func testBriefingShowsWithoutBankConnection() {
        let app = launch(["-MiBancoDemoBriefing", "quiet"])
        XCTAssertTrue(app.buttons["Vale"].waitForExistence(timeout: 15), "Control U58: sin conexión el resumen debía subir")
    }

    /// U76 (B-M1): la ruta del aviso de la mañana pasa por la misma guarda que U58: con «Terminando con Revolut…» a medias no
    /// abre el resumen.
    func testNoBriefingRouteDuringBankConnection() {
        let (app, start) = launchWithLateBriefingRoute(["-MiBancoDemoConnectPhase", "finishing", "rev"])
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15))
        let deadline = start.addingTimeInterval(routeDelay + 6)
        while Date() < deadline {
            XCTAssertFalse(app.buttons["Vale"].exists, "U76: el aviso de la mañana abrió el resumen durante una conexión bancaria")
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertFalse(app.buttons["Vale"].waitForExistence(timeout: 2), "U76: el resumen subió durante una conexión bancaria")
    }
}
