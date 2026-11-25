import SwiftUI
import Observation

/// Medidas que cambian en cada fotograma (posición del carrusel, desplazamiento de la lista).
/// Viven aquí, fuera del entorno y del `body` de Inicio: solo las leen modificadores pequeños
/// (indicador del segmentado, paralaje), así que desplazarse no vuelve a evaluar las tarjetas ni las filas.
@MainActor @Observable
final class HomeMotion {
    /// 0 = «Todo», 1 = Revolut… con decimales mientras se arrastra.
    var carouselPosition: CGFloat = 0
    /// Se ha tirado más allá del primer o el último tope (una háptica ligera por vez).
    var carouselOverscrolled = false
    /// Puntos desplazados hacia arriba desde el reposo (0 arriba del todo).
    var listOffset: CGFloat = 0
    /// El carrusel y la lista están quietos (ni dedo ni inercia). Solo se leen en el momento de decidir si soltar una
    /// tarjeta levantada abre el abanico: nadie se redibuja por ellos.
    @ObservationIgnored var carouselIdle = true
    @ObservationIgnored var listIdle = true
    /// El carrusel se está deslizando por programa (segmentado, llegada): las tarjetas por las que solo pasa no
    /// empiezan a contar su cifra.
    @ObservationIgnored var carouselAnimating = false
    /// Dónde está en pantalla la tarjeta de delante (de ahí sale el abanico). Se lee al abrirlo, nunca al dibujar.
    @ObservationIgnored var carouselFrame = CGRect.zero
    #if DEBUG
    /// Solo demo (`-MiBancoDemoCardMoment`): sube al tocar el segmento que ya está elegido.
    var demoMomentTick = 0
    #endif
}

/// Constantes del carrusel: tarjetas de 376 pt en 440 (32 de margen, se ven los vecinos) y 10 entre ellas.
enum CarouselMetrics {
    static let inset: CGFloat = 32
    static let spacing: CGFloat = 10
    static let minHeight: CGFloat = 236
}

/// Una pieza de Inicio que entra por capas. Dos entradas distintas (`Entrance.scope`):
/// - Montaje (`.assembly`, al arrancar y al desbloquear), con los tiempos de la maqueta aprobada contados desde que
///   empieza: la marca y los botones de cristal a 0 s (los botones crecen desde 0,6 con rebote), el título a 0,03 s
///   (sube 12 pt), el carrusel a 0,06 s (sube 40 pt, escala 0,95), el segmentado a 0,15 s (sube 14 pt) y las filas desde
///   0,20 s (suben 24 pt, 55 ms × 0,8ⁿ entre ellas; como mucho 9 animadas, el resto aparece en su sitio).
/// - Cambio de tarjeta (`.list`): solo las filas, 34 ms × 0,8ⁿ (menos de 150 ms en total), 14 pt.
/// Todo sale de `\.motion`: la intensidad escala tiempos, recorridos y rebote; con Reducir movimiento no hay recorrido
/// ni escala, solo un fundido; y la cámara lenta de las grabaciones lo alarga todo por igual. Solo se animan opacidad,
/// escala y desplazamiento, y fuera de una entrada la pieza ya está en su sitio: nunca se espera para poder tocar.
struct HomeEntrance: ViewModifier {
    enum Piece: Equatable {
        case brand, buttons, title, carousel, segments
        /// Orden dentro de la lista (acciones, resumen de 7 días, filas…), desde 0.
        case row(Int)
    }

    /// Como mucho 9 filas animadas.
    static let animatedRows = 9

    let piece: Piece
    @Environment(\.entrance) private var entrance
    @Environment(\.motion) private var motion
    @State private var landed = -1

    private struct Plan {
        var delay: Double
        var rise: CGFloat
        var scale: CGFloat
        var spring: SpringToken
    }

    /// Cómo entra esta pieza en la entrada en curso; `nil` = no se anima (ya está en su sitio).
    private var plan: Plan? {
        guard entrance.active else { return nil }
        switch (entrance.scope, piece) {
        case (.assembly, .brand):
            return Plan(delay: 0, rise: 0, scale: 1, spring: .enter)
        case (.assembly, .buttons):
            return Plan(delay: 0, rise: 0, scale: 0.6, spring: .release)
        case (.assembly, .title):
            return Plan(delay: motion.seconds(0.03), rise: 12, scale: 1, spring: .enter)
        case (.assembly, .carousel):
            return Plan(delay: motion.seconds(0.06), rise: 40, scale: 0.95, spring: .enter)
        case (.assembly, .segments):
            return Plan(delay: motion.seconds(0.15), rise: 14, scale: 1, spring: .enter)
        case (.assembly, .row(let index)):
            guard index < Self.animatedRows else { return nil }
            return Plan(delay: motion.seconds(0.20) + motion.stagger(index, firstGap: 0.055, decay: 0.8),
                        rise: 24, scale: 1, spring: .row)
        case (.list, .row(let index)):
            guard index < Self.animatedRows else { return nil }
            return Plan(delay: motion.stagger(index, firstGap: 0.034, decay: 0.8), rise: 14, scale: 1, spring: .row)
        case (.list, _):
            return nil
        }
    }

    func body(content: Content) -> some View {
        let plan = plan
        let waiting = plan != nil && landed != entrance.token
        content
            .opacity(waiting ? 0 : 1)
            .scaleEffect(waiting && !motion.reduce ? (plan?.scale ?? 1) : 1)
            .offset(y: waiting ? motion.distance(plan?.rise ?? 0) : 0)
            .onAppear(perform: land)
            .onChange(of: entrance.token) { _, _ in land() }
    }

    private func land() {
        guard let plan else { return }
        let token = entrance.token
        // Con Reducir movimiento todas las piezas se funden a la vez, sin escalonado.
        withAnimation(motion.animation(plan.spring).delay(motion.reduce ? 0 : plan.delay)) { landed = token }
    }
}

extension View {
    /// Esta pieza entra por capas con Inicio (ver `HomeEntrance`).
    func homeEntrance(_ piece: HomeEntrance.Piece) -> some View {
        modifier(HomeEntrance(piece: piece))
    }
}

/// El carrusel se queda algo atrás (paralaje), se encoge y se apaga mientras la lista sube por encima.
/// Al tirar hacia abajo desde arriba, se estira un poco (hasta un 4 %, anclado arriba), como una goma.
struct CarouselParallax: ViewModifier {
    let motion: HomeMotion
    let enabled: Bool

    func body(content: Content) -> some View {
        let y: CGFloat = enabled ? max(motion.listOffset, 0) : 0
        let pull: CGFloat = enabled ? max(-motion.listOffset, 0) : 0
        // Resistencia: crece rápido al principio y se frena (nunca pasa del 4 %).
        let stretch: CGFloat = 0.04 * (1 - 1 / (pull / 120 + 1))
        content
            .offset(y: y * 0.32)
            .scaleEffect(1 - min(y / 1_400, 0.06) + stretch, anchor: .top)
            .opacity(1 - min(y / 420, 0.45))
    }
}

/// Degradado negro bajo la barra superior: solo aparece cuando hay contenido pasando por debajo.
struct TopEdgeFade: View {
    let motion: HomeMotion
    @Environment(\.motion) private var kit

    var body: some View {
        LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.55), .init(color: .black.opacity(0), location: 1)],
                       startPoint: .top, endPoint: .bottom)
            .opacity(motion.listOffset > 8 ? 1 : 0)
            .animation(kit.fade, value: motion.listOffset > 8)
            .allowsHitTesting(false)
    }
}

/// Un importe escrito como texto que el ojo tapa. Con el ojo cerrado se dibuja la máscara (`masked`, nunca una cifra) y
/// no la cifra bajo un desenfoque: un texto difuminado sigue estando ahí para cualquier lector de pantalla o prueba de
/// toques. El cambio es instantáneo (sin fundido entre cifra y máscara) y la etiqueta dice «importe oculto».
/// `masked` no lleva nunca un dígito: en DEBUG se comprueba (ver `DrawnTextAudit`).
struct MaskedAmountText: View {
    let shown: String
    let masked: String

    init(_ shown: String, masked: String) {
        self.shown = shown
        self.masked = masked
    }

    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        let hidden = preferences.privateMode
        let drawn = hidden ? masked : shown
        let text = Text(drawn)
            .contentTransition(.identity)
            .privacySensitive()
            .accessibilityLabel(hidden ? "importe oculto" : shown)
        #if DEBUG
        text.modifier(DrawnTextRecorder(text: drawn, hidden: hidden))
        #else
        text
        #endif
    }
}

#if DEBUG
/// Solo DEBUG (`-MiBancoDemoDrawnText`): cuenta los importes en texto que se han DIBUJADO con el ojo cerrado y cuántos
/// llevaban una cifra. Es lo que las etiquetas de accesibilidad no pueden probar: qué cadena se le dio a `Text` para
/// pintar. Solo cuenta; no decide nada.
@MainActor @Observable final class DrawnTextAudit {
    static let shared = DrawnTextAudit()

    private(set) var hiddenTexts = 0
    private(set) var withDigits = 0

    func record(_ text: String, hidden: Bool) {
        guard hidden, DemoMode.auditsDrawnText else { return }
        hiddenTexts += 1
        if text.contains(where: { $0.isNumber }) { withDigits += 1 }
    }

    var summary: String { "ocultos=\(hiddenTexts);conCifras=\(withDigits)" }
}

private struct DrawnTextRecorder: ViewModifier {
    let text: String
    let hidden: Bool

    func body(content: Content) -> some View {
        content
            .onAppear { DrawnTextAudit.shared.record(text, hidden: hidden) }
            .onChange(of: text) { _, new in DrawnTextAudit.shared.record(new, hidden: hidden) }
    }
}

/// El elemento invisible que publica `DrawnTextAudit.summary` (identificador `drawn-text-audit`).
struct DrawnTextAuditProbe: View {
    var body: some View {
        if DemoMode.auditsDrawnText {
            Color.clear
                .frame(width: 2, height: 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(DrawnTextAudit.shared.summary)
                .accessibilityIdentifier("drawn-text-audit")
        }
    }
}

/// Solo DEBUG (`-MiBancoDemoHomeProbes`): contadores de Inicio para las pruebas de toque. Solo cuenta.
@MainActor @Observable final class HomeProbe {
    static let shared = HomeProbe()

    /// Veces que Inicio se ha montado por capas (arranque o desbloqueo).
    var assemblies = 0
    /// Si los sensores de inclinación están leyendo ahora.
    var tiltRunning = false
    /// Veces que tirar de la lista ha lanzado una actualización, y veces que ha acabado diciendo «Al día».
    var refreshes = 0
    var refreshesDone = 0
    /// Si el abanico de tarjetas está abierto y cuántas veces se ha abierto.
    var fanOpen = false
    var fanOpenings = 0
    /// La última tarjeta del abanico tocada y si se pidió su vuelo (`CardFlight.request`).
    var fanPicked = "-"
    var flightRequests = 0
    /// Llegadas que han enseñado su ✓ en la tarjeta y llegadas que solo han latido (ojo cerrado).
    var arrivalBadges = 0
    var arrivalPulses = 0
    /// Cuántas veces ha entrado la lista escalonada por un cambio de tarjeta.
    var listEntrances = 0

    var summary: String {
        [
            "montajes=\(assemblies)", "inclinacion=\(tiltRunning ? 1 : 0)", "tirones=\(refreshes)", "alDia=\(refreshesDone)",
            "abanico=\(fanOpen ? 1 : 0)", "abanicos=\(fanOpenings)", "elegida=\(fanPicked)", "vuelos=\(flightRequests)",
            "insignias=\(arrivalBadges)", "latidos=\(arrivalPulses)", "listas=\(listEntrances)",
        ].joined(separator: ";")
    }
}

/// El elemento invisible que publica `HomeProbe.summary` en su valor (identificador `home-probe`).
struct HomeProbeElement: View {
    var body: some View {
        if DemoMode.exposesHomeProbes {
            Color.clear
                .frame(width: 2, height: 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Sonda de Inicio")
                .accessibilityValue(HomeProbe.shared.summary)
                .accessibilityIdentifier("home-probe")
        }
    }
}
#endif
