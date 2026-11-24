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
        // Que termine el montaje del arranque (a cámara lenta) antes de tocar nada.
        Thread.sleep(forTimeInterval: 7)
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
        burst("carousel-drag-reduce", frames: 12, every: 0.12)
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
}
