import UIKit
import XCTest

/// Ráfagas de movimiento del flujo «Inicio» (nadie más edita este fichero). Cada momento se dispara con un toque real y
/// la ráfaga empieza en el acto, a cámara lenta ×4 (`MotionTourCase.launch`). Cada ráfaga con importes se repite con el
/// ojo cerrado (`-MiBancoDemoPrivate`, sufijo `-eye`): en ningún fotograma puede verse una cifra.
/// - El montaje por capas se dispara al quitarse solo el bloqueo de demo.
/// - Levantar, inclinar y la pista del volteo no se pueden provocar y fotografiar a la vez (una pulsación larga bloquea
///   la prueba; el simulador no tiene giroscopio): `-MiBancoDemoCardMoment` los dispara al tocar el segmento ya elegido.
final class MotionTourHomeTests: MotionTourCase {
    // MARK: Ayudas

    private func waitForHome() {
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 20), "Inicio no aparece")
        // Mientras está la capa del arranque (a cámara lenta dura varios segundos), un toque la salta en vez de llegar
        // a Inicio: se espera a que se quite y, después, a que termine el montaje por capas.
        let layer = app.descendants(matching: .any).matching(identifier: "launch-layer").firstMatch
        let limit = Date().addingTimeInterval(30)
        while layer.exists && Date() < limit { Thread.sleep(forTimeInterval: 0.2) }
        Thread.sleep(forTimeInterval: 7)
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func segment(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    private func carousel() -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label ENDSWITH %@", " de 4")).firstMatch
    }

    private func tapCard() {
        carousel().coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
    }

    /// Abre con el bloqueo de demo, que se quita solo a los 6 s (en el simulador, tocar «Desbloquear» abre la hoja del
    /// código del sistema), y empieza la ráfaga en cuanto el botón del bloqueo deja de existir: Inicio se monta debajo.
    private func unlockAndBurst(_ name: String, extra: [String] = [], frames: Int = 24, every: TimeInterval = 0.28) {
        launch(["-MiBancoDemoLock", "-MiBancoDemoLockSeconds", "6"] + extra)
        let unlock = app.buttons["Desbloquear"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 20), "Falta la pantalla de bloqueo")
        let limit = Date().addingTimeInterval(20)
        while unlock.exists && Date() < limit {}
        burst(name, frames: frames, every: every)
    }

    // MARK: A2 — Inicio se monta por capas (y el total cuenta desde 0)

    func testHomeBuild() throws {
        unlockAndBurst("home-build")
    }

    func testHomeBuildEyeClosed() throws {
        unlockAndBurst("home-build-eye", extra: ["-MiBancoDemoPrivate"])
    }

    /// Montado con el ojo cerrado y abierto a mitad del montaje (a cámara lenta la ventana del montaje dura 5,6 s):
    /// «Gastado en 7 días» aparece en cuanto se abre el ojo, sin quedarse invisible hasta el final de la ventana.
    func testHomeBuildEyeOpensMidway() throws {
        // El ojo lo abre la demo 0,3 s (× cámara lenta) tras empezar el montaje: un toque de la prueba esperaría a que
        // la app estuviera quieta, o sea, a que el montaje acabara.
        unlockAndBurst("home-build-eye-opens", extra: ["-MiBancoDemoPrivate", "-MiBancoDemoEyeOpensMidBuild"], frames: 20,
                       every: 0.25)
    }

    func testHomeBuildReduceMotion() throws {
        unlockAndBurst("home-build-reduce", extra: ["-MiBancoReduceMotion"], frames: 12, every: 0.15)
    }

    // MARK: A1 / A3 — cifras que ruedan y carrusel

    /// Tocar un segmento: el carrusel se desliza con sus vecinos girados y el brillo cruzando; la tarjeta que llega se
    /// pasa un poco de su sitio y vuelve (el rebote de su muelle) y cuenta su saldo desde 0; el resumen de 7 días rueda al de esa tarjeta.
    private func glideBursts(_ suffix: String, extra: [String]) {
        launch(extra)
        waitForHome()
        segment("Revolut").tap()
        burst("carousel-drag" + suffix, frames: 20, every: 0.2)
        Thread.sleep(forTimeInterval: 2)
        segment("imagin").tap()
        burst("total-roll" + suffix, frames: 20, every: 0.2)
    }

    func testCarouselGlideAndTotalRoll() throws {
        glideBursts("", extra: [])
    }

    func testCarouselGlideAndTotalRollEyeClosed() throws {
        glideBursts("-eye", extra: ["-MiBancoDemoPrivate"])
    }

    func testCarouselChangeReduceMotion() throws {
        launch(["-MiBancoReduceMotion"])
        waitForHome()
        segment("Revolut").tap()
        burst("carousel-drag-reduce", frames: 20, every: 0.12)
    }

    /// El ojo en Inicio: al cerrarlo las cifras se barajan y pasan a puntos; al abrirlo ruedan hasta la cifra.
    func testEye() throws {
        launch()
        waitForHome()
        app.buttons["Ocultar importes"].tap()
        burst("eye-close", frames: 10, every: 0.1)
        Thread.sleep(forTimeInterval: 1.5)
        app.buttons["Mostrar importes"].tap()
        burst("eye-open", frames: 14, every: 0.2)
    }

    // MARK: A3 — voltear, levantar, inclinar, pista

    private func flipBursts(_ suffix: String, extra: [String]) {
        launch(extra)
        waitForHome()
        tapCard()
        burst("card-flip" + suffix, frames: 18, every: 0.2)
        Thread.sleep(forTimeInterval: 2)
        // En el reverso, lejos de su botón.
        carousel().coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        burst("card-flip-back" + suffix, frames: 18, every: 0.2)
    }

    func testCardFlip() throws {
        flipBursts("", extra: [])
    }

    func testCardFlipEyeClosed() throws {
        flipBursts("-eye", extra: ["-MiBancoDemoPrivate"])
    }

    func testCardFlipReduceMotion() throws {
        launch(["-MiBancoReduceMotion"])
        waitForHome()
        tapCard()
        burst("card-flip-reduce", frames: 10, every: 0.1)
    }

    func testCardLift() throws {
        launch(["-MiBancoDemoCardMoment", "lift"])
        waitForHome()
        segment("Todo").tap()
        // Sube (~1,3 s a ×4), se queda arriba hasta los 3 s y baja con rebote (~2,5 s).
        burst("card-lift", frames: 24, every: 0.3)
    }

    func testCardTilt() throws {
        // A velocidad real: el barrido de la inclinación es de la demo, no una animación del kit.
        launch(["-MiBancoDemoCardMoment", "tilt"], scale: 1)
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 20), "Inicio no aparece")
        Thread.sleep(forTimeInterval: 3)
        segment("Todo").tap()
        burst("card-tilt", frames: 16, every: 0.3)
    }

    func testCardPeek() throws {
        launch(["-MiBancoDemoCardMoment", "peek"])
        waitForHome()
        segment("Todo").tap()
        burst("card-peek", frames: 20, every: 0.3)
    }

    // MARK: Ronda de arreglos 1 — el deslizamiento programado, fotografiado entero

    /// Ráfaga densa: como `burst`, pero captura la pantalla directamente (sin consultar antes el árbol de la app, que es
    /// lo que más tarda), primero todas las capturas y después los adjuntos, para sacar un fotograma cada pocas
    /// centésimas a velocidad real. `crop` (en puntos de pantalla, con `screenWidth` = ancho de la pantalla en puntos)
    /// recorta una zona para verla ampliada en la hoja. Mismos nombres de adjunto que `burst` («<name>-NN_tTTT», TTT =
    /// décimas reales desde la primera captura): con ráfagas densas, dos fotogramas pueden compartir décima.
    private func fastBurst(_ name: String, frames: Int, every: TimeInterval, crop: CGRect? = nil, screenWidth: CGFloat = 0) {
        XCTAssertNotNil(name.range(of: "^[a-z0-9]+(-[a-z0-9]+)*$", options: .regularExpression),
                        "El nombre de la ráfaga solo admite minúsculas, números y guiones: \(name)")
        XCTAssertTrue((1...99).contains(frames), "Una ráfaga lleva de 1 a 99 fotogramas")
        var shots: [XCUIScreenshot] = []
        var times: [TimeInterval] = []
        let start = Date()
        for index in 0..<min(max(frames, 1), 99) {
            let wait = start.addingTimeInterval(Double(index) * every).timeIntervalSinceNow
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            times.append(Date().timeIntervalSince(start))
            shots.append(XCUIScreen.main.screenshot())
        }
        for (index, shot) in shots.enumerated() {
            let tenths = Int((times[index] * 10).rounded())
            let attachment: XCTAttachment
            if let crop, screenWidth > 0, let whole = shot.image.cgImage {
                let k = CGFloat(whole.width) / screenWidth
                let pixels = CGRect(x: crop.minX * k, y: crop.minY * k, width: crop.width * k, height: crop.height * k).integral
                guard let cut = whole.cropping(to: pixels) else {
                    XCTFail("No se pudo recortar el fotograma \(index + 1) de \(name)")
                    return
                }
                attachment = XCTAttachment(image: UIImage(cgImage: cut), quality: .original)
            } else {
                attachment = XCTAttachment(screenshot: shot, quality: .original)
            }
            attachment.name = "\(name)-" + String(format: "%02d", index + 1) + "_t" + String(format: "%03d", tenths)
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    /// La zona del borde izquierdo de la tarjeta de delante (170 pt de ancho), con el título encima y el segmentado
    /// debajo, que no se mueven y sirven de referencia.
    private func leftEdgeCrop() -> (crop: CGRect, screenWidth: CGFloat) {
        let screen = app.windows.firstMatch.frame
        let card = carousel().frame
        let top = max(0, card.minY - 50)
        let crop = CGRect(x: 0, y: top, width: 170, height: min(card.height + 110, screen.height - top))
        return (crop, screen.width)
    }

    /// El deslizamiento programado, fotografiado ENTERO: `-MiBancoDemoCardMoment glide` lo dispara 0,8 s después de
    /// tocar el segmento ya elegido (por el mismo camino que un toque en otro segmento), así que la ráfaga densa ya
    /// está en marcha cuando empieza. `tap()` vuelve cuando el toque ya ha pasado: con un toque directo en «Revolut»
    /// la ráfaga llegaba con la tarjeta casi en su sitio.
    private func glideBurst(_ name: String, level: String, scale: Double, moment: String = "glide",
                            frames: Int, every: TimeInterval, zoomed: Bool = false) {
        launch(["-MiBancoMotionLevel", level, "-MiBancoDemoCardMoment", moment], scale: scale)
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 20), "Inicio no aparece")
        Thread.sleep(forTimeInterval: scale > 1 ? 7 : 3)
        let zone = zoomed ? leftEdgeCrop() : (crop: CGRect.null, screenWidth: CGFloat(0))
        segment("Todo").tap()
        if zoomed {
            fastBurst(name, frames: frames, every: every, crop: zone.crop, screenWidth: zone.screenWidth)
        } else {
            fastBurst(name, frames: frames, every: every)
        }
    }

    /// A velocidad real, Expresivo: de «Todo» a Revolut.
    func testCarouselGlideRealTimeExpressive() throws {
        glideBurst("carousel-drag-expressive", level: "expressive", scale: 1, frames: 18, every: 0.04)
    }

    /// A velocidad real, Sutil: las vecinas giran y se apagan menos, y la tarjeta se pasa menos al llegar.
    func testCarouselGlideRealTimeSubtle() throws {
        glideBurst("carousel-drag-subtle", level: "subtle", scale: 1, frames: 18, every: 0.04)
    }

    /// A cámara lenta ×4, Expresivo: el mismo deslizamiento con el muelle cuatro veces más lento.
    func testCarouselGlideSlowMotion() throws {
        glideBurst("carousel-drag-slow", level: "expressive", scale: 4, frames: 30, every: 0.12)
    }

    /// A velocidad real, de «Todo» a la última tarjeta (tres de recorrido).
    func testCarouselGlideFar() throws {
        glideBurst("carousel-glide-far", level: "expressive", scale: 1, moment: "glideFar", frames: 18, every: 0.04)
    }

    /// La llegada a velocidad real, ampliada sobre el borde izquierdo de la tarjeta que llega: cuánto se pasa de su
    /// sitio y cómo vuelve, en Expresivo y en Sutil.
    func testCarouselLandingExpressive() throws {
        glideBurst("carousel-landing-expressive", level: "expressive", scale: 1, frames: 20, every: 0.04, zoomed: true)
    }

    func testCarouselLandingSubtle() throws {
        glideBurst("carousel-landing-subtle", level: "subtle", scale: 1, frames: 20, every: 0.04, zoomed: true)
    }

    // MARK: Lote 2 — A4: llega un movimiento

    /// `-MiBancoDemoCardMoment arrival|arrivalIncome`: tocar el segmento ya elegido ingesta un movimiento por el camino
    /// real. El modelo lo publica 0,56 s después (tiempo real): la cifra rueda, el ✓ con el importe salta sobre la cifra
    /// y la fila cae con su luz.
    private func arrivalBurst(_ name: String, moment: String, extra: [String] = [], from segmentTitle: String = "Todo",
                              frames: Int = 24, every: TimeInterval = 0.4) {
        launch(["-MiBancoDemoCardMoment", moment] + extra)
        waitForHome()
        segment(segmentTitle).tap()
        burst(name, frames: frames, every: every)
    }

    func testArrivalPayment() throws {
        arrivalBurst("arrival-payment", moment: "arrival")
    }

    func testArrivalPaymentEyeClosed() throws {
        arrivalBurst("arrival-payment-eye", moment: "arrival", extra: ["-MiBancoDemoPrivate"])
    }

    func testArrivalIncome() throws {
        arrivalBurst("arrival-income", moment: "arrivalIncome")
    }

    func testArrivalIncomeEyeClosed() throws {
        arrivalBurst("arrival-income-eye", moment: "arrivalIncome", extra: ["-MiBancoDemoPrivate"])
    }

    func testArrivalPaymentReduceMotion() throws {
        arrivalBurst("arrival-payment-reduce", moment: "arrival", extra: ["-MiBancoReduceMotion"], frames: 16, every: 0.3)
    }

    /// Con la tarjeta de otro banco delante: el carrusel se desliza hasta la del banco del pago.
    func testArrivalPaymentGlide() throws {
        arrivalBurst("arrival-payment-glide", moment: "arrival", extra: ["-MiBancoDemoCard", "rev"], from: "Revolut")
    }

    // MARK: Lote 2 — A5: listas

    /// Cambiar de tarjeta: la lista sale con un fundido y la nueva entra escalonada (34 ms × 0,8ⁿ).
    private func listStagger(_ name: String, extra: [String], frames: Int = 16, every: TimeInterval = 0.2) {
        launch(extra)
        waitForHome()
        segment("imagin").tap()
        burst(name, frames: frames, every: every)
    }

    func testListStagger() throws {
        listStagger("list-stagger", extra: [])
    }

    func testListStaggerEyeClosed() throws {
        listStagger("list-stagger-eye", extra: ["-MiBancoDemoPrivate"])
    }

    func testListStaggerReduceMotion() throws {
        listStagger("list-stagger-reduce", extra: ["-MiBancoReduceMotion"], frames: 12, every: 0.12)
    }

    /// `-MiBancoDemoCardMoment rowSwipe`: la primera fila se abre (como al deslizarla) y, al tocar otra vez, se cierra.
    private func rowSwipe(_ suffix: String, extra: [String], frames: Int = 12, bringRowsUp: Bool = false) {
        launch(["-MiBancoDemoCardMoment", "rowSwipe"] + extra)
        waitForHome()
        if bringRowsUp {
            // Con el texto más grande las filas quedan bajo el borde: se sube la lista hasta ver la primera (el
            // segmentado se queda arriba, fijo).
            let row = app.buttons.matching(identifier: "movementRow").firstMatch
            let centre = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            let bottom = app.windows.firstMatch.frame.maxY - 160
            for _ in 0..<10 where !(row.exists && row.isHittable && row.frame.maxY < bottom) {
                centre.press(forDuration: 0.1, thenDragTo: centre.withOffset(CGVector(dx: 0, dy: -260)), withVelocity: 500,
                             thenHoldForDuration: 0.3)
            }
            Thread.sleep(forTimeInterval: 2)
        }
        segment("Todo").tap()
        burst("row-swipe" + suffix, frames: frames, every: 0.2)
        Thread.sleep(forTimeInterval: 1.5)
        segment("Todo").tap()
        burst("row-swipe-close" + suffix, frames: frames, every: 0.2)
    }

    func testRowSwipe() throws {
        rowSwipe("", extra: [])
    }

    func testRowSwipeEyeClosed() throws {
        rowSwipe("-eye", extra: ["-MiBancoDemoPrivate"])
    }

    /// Con el texto de accesibilidad más grande (fila apilada, el importe debajo del nombre): al abrirse, el importe se
    /// apaga antes de que se lean las acciones.
    func testRowSwipeLargestText() throws {
        rowSwipe("-ax", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"],
                 bringRowsUp: true)
    }

    func testRowSwipeLargestTextEyeClosed() throws {
        rowSwipe("-ax-eye", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                                    "-MiBancoDemoPrivate"], bringRowsUp: true)
    }

    func testRowSwipeReduceMotion() throws {
        rowSwipe("-reduce", extra: ["-MiBancoReduceMotion"], frames: 6)
    }

    /// `-MiBancoDemoCardMoment refresh`: la actualización de «tirar para actualizar» sin dedo: la lista baja, la ola
    /// brilla, dice «Al día» y se recoge. (El tirón con el dedo no se puede fotografiar mientras se arrastra.) Con
    /// `-MiBancoDemoBanks`: «Al día» solo se dice con bancos conectados y al día (`RefreshVerdict`).
    func testPullRefresh() throws {
        launch(["-MiBancoDemoCardMoment", "refresh", "-MiBancoDemoBanks"])
        waitForHome()
        segment("Todo").tap()
        burst("pull-refresh", frames: 28, every: 0.4)
    }

    func testPullRefreshReduceMotion() throws {
        launch(["-MiBancoDemoCardMoment", "refresh", "-MiBancoDemoBanks", "-MiBancoReduceMotion"])
        waitForHome()
        segment("Todo").tap()
        burst("pull-refresh-reduce", frames: 16, every: 0.4)
    }

    // MARK: Lote 2 — A6: abanico de tarjetas

    /// `-MiBancoDemoCardMoment fan`: el abanico se abre; después, tocar la tarjeta de Revolut: las demás caen y se abre
    /// la pantalla del banco.
    private func fanBursts(_ suffix: String, extra: [String]) {
        launch(["-MiBancoDemoCardMoment", "fan"] + extra)
        waitForHome()
        segment("Todo").tap()
        burst("wallet-fan" + suffix, frames: 20, every: 0.25)
        Thread.sleep(forTimeInterval: 1)
        // En su franja visible (arriba): el resto de la tarjeta queda bajo la siguiente.
        app.buttons["wallet-card-rev"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        burst("wallet-fan-pick" + suffix, frames: 14, every: 0.25)
    }

    func testWalletFan() throws {
        fanBursts("", extra: [])
    }

    func testWalletFanEyeClosed() throws {
        fanBursts("-eye", extra: ["-MiBancoDemoPrivate"])
    }

    func testWalletFanReduceMotion() throws {
        fanBursts("-reduce", extra: ["-MiBancoReduceMotion"])
    }

    /// El camino de verdad: mantener el dedo sobre la tarjeta (se levanta a los 0,42 s y a los 0,92 s se abre el
    /// abanico). La pulsación bloquea la prueba 1,6 s, así que la ráfaga empieza con el abanico a medio abrir; después,
    /// «Cerrar»: las tarjetas vuelven bajo la tarjeta de la que salieron.
    /// Abanico con Reducir movimiento, fotograma a fotograma: a cámara lenta ×8 y con capturas seguidas (~15 ms reales
    /// entre fotogramas), para ver el paso de Inicio al abanico entero (ni un fotograma negro ni dos títulos).
    func testWalletFanReduceMotionFine() throws {
        launch(["-MiBancoDemoCardMoment", "fan", "-MiBancoReduceMotion"], scale: 8)
        waitForHome()
        segment("Todo").tap()
        fastBurst("wallet-fan-reduce-fine", frames: 32, every: 0.05)
    }

    func testWalletFanFromLongPress() throws {
        launch()
        waitForHome()
        carousel().coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).press(forDuration: 1.6)
        burst("wallet-fan-hold", frames: 16, every: 0.25)
        app.buttons["wallet-fan-close"].tap()
        burst("wallet-fan-close", frames: 12, every: 0.2)
    }

    // MARK: Lote 2 — A7: tarjeta de inversiones

    private func investments(_ name: String, extra: [String]) {
        launch(["-MiBancoDemoPortfolio"] + extra)
        waitForHome()
        segment("Cartera").tap()
        burst(name, frames: 20, every: 0.3)
    }

    func testInvestments() throws {
        investments("investments", extra: [])
    }

    func testInvestmentsEyeClosed() throws {
        investments("investments-eye", extra: ["-MiBancoDemoPrivate"])
    }

    // MARK: Lote 2 — A8: «Mover dinero»

    /// Abre «Mover dinero» desde «Todo» y elige Revolut como destino: queda en el paso del importe.
    private func openMoveAmountStep() {
        let move = app.buttons["Mover dinero"]
        XCTAssertTrue(move.waitForExistence(timeout: 10), "Falta «Mover dinero»")
        move.tap()
        let target = element("move-target-rev")
        XCTAssertTrue(target.waitForExistence(timeout: 10), "Falta Revolut como destino")
        target.tap()
        XCTAssertTrue(app.buttons["1"].waitForExistence(timeout: 10), "No se llegó al teclado")
        Thread.sleep(forTimeInterval: 1.5)
    }

    /// `-MiBancoDemoKeypadDelay 0.8`: cada tecla hace efecto 0,8 s después del toque, así que la ráfaga ya está en marcha
    /// cuando el dígito entra. Con «123» escrito, el «4» entra y aparece el punto de millar; después se borra.
    private func keypad(_ suffix: String, extra: [String], frames: Int = 14) {
        launch(["-MiBancoDemoKeypadDelay", "0.8"] + extra)
        waitForHome()
        openMoveAmountStep()
        // Con el ojo cerrado, primero el importe vacío (la máscara atenuada).
        if extra.contains("-MiBancoDemoPrivate") { burst("keypad" + suffix + "-empty", frames: 3, every: 0.2) }
        for key in ["1", "2", "3"] {
            app.buttons[key].tap()
            Thread.sleep(forTimeInterval: 2.6)
        }
        app.buttons["4"].tap()
        burst("keypad" + suffix, frames: frames, every: 0.2)
        Thread.sleep(forTimeInterval: 1)
        app.buttons["keypad-backspace"].tap()
        burst("keypad-delete" + suffix, frames: frames, every: 0.2)
    }

    func testKeypad() throws {
        keypad("", extra: [])
    }

    func testKeypadEyeClosed() throws {
        keypad("-eye", extra: ["-MiBancoDemoPrivate"])
    }

    func testKeypadReduceMotion() throws {
        keypad("-reduce", extra: ["-MiBancoReduceMotion"], frames: 8)
    }

    /// Deslizar «Desliza para preparar»: el paso «listo» (preparado, no enviado: el ✓ neutro en aro de titanio aparece y
    /// se traza; el titular, los datos y los botones entran por turnos sin rebote). Después, «Copiar IBAN» → «Copiado».
    private func success(_ suffix: String, extra: [String], copies: Bool) {
        launch(extra)
        waitForHome()
        openMoveAmountStep()
        for key in ["2", "0"] {
            app.buttons[key].tap()
            Thread.sleep(forTimeInterval: 0.8)
        }
        let slider = element("move-slide")
        XCTAssertTrue(slider.waitForExistence(timeout: 10), "Falta «Desliza para preparar»")
        let frame = slider.frame
        let origin = slider.coordinate(withNormalizedOffset: .zero)
        let from = origin.withOffset(CGVector(dx: 28, dy: frame.height / 2))
        let to = origin.withOffset(CGVector(dx: frame.width - 6, dy: frame.height / 2))
        from.press(forDuration: 0.3, thenDragTo: to, withVelocity: 400, thenHoldForDuration: 0.1)
        burst("success-sheet" + suffix, frames: 24, every: 0.3)
        guard copies else { return }
        let again = app.scrollViews["move-ready-scroll"].buttons["Copiar IBAN"]
        XCTAssertTrue(again.waitForExistence(timeout: 10), "Falta «Copiar IBAN»")
        again.tap()
        burst("move-money", frames: 16, every: 0.25)
    }

    func testSuccessSheet() throws {
        success("", extra: [], copies: true)
    }

    func testSuccessSheetEyeClosed() throws {
        success("-eye", extra: ["-MiBancoDemoPrivate"], copies: false)
    }

    func testSuccessSheetReduceMotion() throws {
        success("-reduce", extra: ["-MiBancoReduceMotion"], copies: false)
    }

    // MARK: Lote 2 — menores: la búsqueda cambia el contenido sin mover la maquetación

    /// La búsqueda abierta y cerrada por la demo (0,8 s después del toque): la ráfaga ve el fundido del cambio entero.
    func testSearchSwapDelayed() throws {
        launch(["-MiBancoDemoCardMoment", "search"])
        waitForHome()
        segment("Todo").tap()
        // Una sola ráfaga: se abre a los 0,8 s y se cierra a los 3,8 s.
        burst("search-swap", frames: 32, every: 0.15)
    }

    // MARK: Retoques de diseño

    /// Tirar para actualizar con un banco que no está al día (consentimiento caducado): la ola trabaja y se recoge
    /// SIN decir «Al día».
    func testPullRefreshNotFresh() throws {
        launch(["-MiBancoDemoCardMoment", "refresh", "-MiBancoDemoBanks", "-MiBancoDemoRefresh", "consentExpired"])
        waitForHome()
        segment("Todo").tap()
        burst("pull-refresh-stale", frames: 20, every: 0.4)
    }

    /// El montaje tras el desbloqueo en Expresivo: la cifra grande no se queda quieta en «0,00 €» y se asienta antes.
    func testHomeBuildExpressive() throws {
        unlockAndBurst("home-build-expressive", extra: ["-MiBancoMotionLevel", "expressive"])
    }

    func testHomeBuildExpressiveEyeClosed() throws {
        unlockAndBurst("home-build-expressive-eye", extra: ["-MiBancoMotionLevel", "expressive", "-MiBancoDemoPrivate"])
    }

    func testSearchSwap() throws {
        launch()
        waitForHome()
        app.buttons["Buscar movimientos"].tap()
        burst("search-open", frames: 10, every: 0.15)
        Thread.sleep(forTimeInterval: 1)
        app.buttons["Cancelar"].tap()
        burst("search-close", frames: 10, every: 0.15)
    }
}
