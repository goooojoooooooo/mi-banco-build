import SwiftUI
import MiBancoCore

/// Lo que la hoja de un banco ha subido sobre su cabecera. Lo escribe el desplazamiento y lo leen solo las piezas
/// pequeñas que se mueven con él (cabecera, fondo de la hoja, título pequeño, barra negra): el contenido no se
/// redibuja en cada paso del dedo.
@MainActor @Observable final class BankHeaderScroll {
    /// Lo desplazado en puntos (0 = en reposo; negativo al tirar hacia abajo).
    var offset: CGFloat = 0
    /// Lo que tiene que subir la hoja para quedar acoplada bajo la barra: el alto de la cabecera.
    var dock: CGFloat = 1
    /// Alto visible de la pantalla del banco (sin barras).
    var viewport: CGFloat = 0
    /// Sube en cada petición de acoplar la hoja («Ver movimientos»).
    var dockRequests = 0

    /// 0 = hoja en reposo bajo la cabecera · 1 = hoja acoplada arriba.
    var progress: CGFloat { BankHeaderMath.unit(offset / max(1, dock)) }
}

/// Las cuentas de la hoja sobre la cabecera oscura (maqueta `shApply`): todo sale de `p`, lo que la hoja ha subido.
enum BankHeaderMath {
    static func unit(_ x: CGFloat) -> CGFloat { x.isFinite ? min(1, max(0, x)) : 0 }

    /// La cabecera se encoge hasta un 10 % (× la intensidad, como mucho 1,3).
    static func headerScale(_ p: CGFloat, distanceScale: CGFloat) -> CGFloat { 1 - 0.1 * min(1.3, distanceScale) * unit(p) }
    /// Donde la cabecera (con el saldo grande) ya se ha apagado del todo.
    static let headerGone: CGFloat = 0.62
    /// Donde empieza a entrar el título pequeño: después de `headerGone`, con un hueco entre los dos, así que nunca se
    /// ven a la vez el saldo grande y el del título pequeño.
    static let miniStart: CGFloat = 0.70

    /// La cabecera se apaga mientras la hoja sube y ha desaparecido en p = 0,62.
    static func headerOpacity(_ p: CGFloat) -> CGFloat { unit(1 - unit(p) / headerGone) }
    /// Las acciones rápidas siguen enteras hasta el 25 % del recorrido (con un toque de desplazamiento no parecen
    /// desactivadas, ojo de diseño 13.3) y se han ido en p = 0,55, antes que el resto de la cabecera.
    static func actionsOpacity(_ p: CGFloat) -> CGFloat { unit(1 - (unit(p) - 0.25) / 0.30) }
    /// Las acciones solo se tocan mientras se ven de verdad (menor m-11).
    static func actionsTouchable(_ p: CGFloat) -> Bool { actionsOpacity(p) > 0.3 }
    /// El asa de la hoja se apaga en el último 10 % del recorrido: acoplada no sirve de nada (13.4).
    static func handleOpacity(_ p: CGFloat) -> CGFloat { unit((1 - unit(p)) / 0.1) }
    /// Esquinas de la hoja: 30 pt hasta p = 0,82 y de ahí a 0.
    static func cornerRadius(_ p: CGFloat) -> CGFloat { 30 * (1 - unit((unit(p) - 0.82) / 0.18)) }
    /// El título pequeño («Banco · saldo») entra entre p = 0,7 y 1.
    static func miniTitle(_ p: CGFloat) -> CGFloat { unit((unit(p) - miniStart) / (1 - miniStart)) }
    /// La barra negra llega en cuanto la cabecera se ha ido (p 0,62–0,82), antes que el título pequeño.
    static func barOpacity(_ p: CGFloat) -> CGFloat { unit((unit(p) - headerGone) / 0.2) }

    /// Lo que se ven a la vez la cabecera y el título pequeño en `p` (0 = nunca los dos).
    static func overlap(_ p: CGFloat) -> CGFloat { min(headerOpacity(p), miniTitle(p)) }

    /// El mayor solape de las dos curvas en todo el recorrido (p de 0 a 1 en pasos de 0,005).
    static var maxOverlap: CGFloat { (0...200).map { overlap(CGFloat($0) / 200) }.max() ?? 0 }

    /// Al soltar a medio camino: dónde se asienta la hoja (lo desplazado), abajo (0) o acoplada (`dock`), la más cercana;
    /// `nil` si ya está en uno de los dos (o más allá: leyendo los movimientos, o tirando hacia abajo).
    static let settleTolerance: CGFloat = 2

    static func settleTarget(offset: CGFloat, dock: CGFloat) -> CGFloat? {
        // 2 pt de tolerancia: el aterrizaje de `scrollTo(id:)` puede quedar a una fracción de punto del borde exacto y
        // eso no debe pedir otro asentamiento (nota diferida 2 de la re-revisión).
        guard offset.isFinite, dock > 1, offset > settleTolerance, offset < dock - settleTolerance else { return nil }
        return offset < dock / 2 ? 0 : dock
    }
}

/// La pantalla de un banco: una hoja que sube sobre una cabecera oscura (momento 5 de los vídeos del dueño).
/// Al desplazar, la cabecera se queda atrás (paralaje), se encoge y se apaga; las esquinas de la hoja se cuadran al
/// llegar arriba y en la barra aparece el título pequeño «Banco · saldo» sobre una barra negra. Al entrar, la cabecera
/// sube 12 pt y la hoja llega desde 260 pt más abajo. Solo se animan desplazamiento, escala, opacidad y la forma de
/// la hoja; nada de desenfoque. Con Reducir movimiento la cabecera no se mueve ni se encoge: solo se apaga.
///
/// `hidden` (el ojo) viene de `AppPreferences`: el saldo del título pequeño es una máscara, nunca cifras tapadas.
/// `headerShown = false` deja la cabecera invisible (la tarjeta que vuela desde Inicio aún no ha aterrizado).
struct BankHeaderSheet<Header: View, Sheet: View>: View {
    let scroll: BankHeaderScroll
    let title: String
    let balanceCents: Int?
    let hidden: Bool
    var headerShown = true
    @ViewBuilder let header: Header
    @ViewBuilder let sheet: Sheet

    @Environment(\.motion) private var motion
    @State private var entered = false
    @State private var position = ScrollPosition(edge: .top)
    /// El desplazamiento está quieto (ni dedo ni inercia).
    @State private var scrollIdle = true

    private static var sheetID: String { "bank-sheet" }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                BankHeaderLayer(scroll: scroll, shown: headerShown, entered: entered) { header }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { scroll.dock = max(1, $0) }
                BankSheetLayer(scroll: scroll, entered: entered) { sheet }
                    .id(Self.sheetID)
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollPosition($position)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, new in
            scroll.offset = new
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.height - $0.contentInsets.top - $0.contentInsets.bottom } action: { _, new in
            scroll.viewport = max(0, new)
        }
        .accessibilityIdentifier("bank-screen-scroll")
        // Al soltar a medio camino, la hoja nunca se queda entre medias: se asienta abajo o acoplada.
        .onScrollPhaseChange { _, new in
            scrollIdle = new == .idle
            if new == .idle { settle() }
        }
        // Si la cabecera cambia de alto con la hoja parada (pasos → «conectado»), la hoja puede quedar entre medias sin
        // que el desplazamiento cambie de fase: se asienta también entonces (nota diferida 3).
        .onChange(of: scroll.dock) { _, _ in
            if scrollIdle { settle() }
        }
        .background { BankHeaderBackdrop() }
        .overlay(alignment: .top) {
            BankHeaderBar(scroll: scroll, title: title, balanceCents: balanceCents, hidden: hidden, reduce: motion.reduce,
                          fade: motion.fade)
            #if DEBUG
            if DemoMode.exposesDockProbe {
                BankDockProbe(scroll: scroll)
            }
            #endif
        }
        // El título del sistema no se dibuja (el banco ya está en la cabecera y, acoplada la hoja, en el título pequeño):
        // en su sitio va una pieza vacía. El nombre de la pantalla sigue siendo el del banco para VoiceOver y la pila.
        .toolbar {
            ToolbarItem(placement: .principal) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityHidden(true)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .environment(scroll)
        .onChange(of: scroll.dockRequests) { _, _ in
            // Hasta el borde de arriba de la hoja, mida lo que mida la cabecera en ese momento.
            withAnimation(motion.animation(.sheet)) { position.scrollTo(id: Self.sheetID, anchor: .top) }
        }
        .onAppear {
            guard !entered else { return }
            // La hoja llega desde abajo con un muelle de 0,55 s que se pasa un poco; con Reducir movimiento, un fundido.
            let spring = Animation.spring(response: motion.seconds(0.55),
                                          dampingFraction: max(0.5, 1 - 0.16 * motion.level.bounceScale))
            withAnimation(motion.reduce ? motion.fade : spring) { entered = true }
        }
    }

    /// La hoja quedó parada entre abajo y acoplada: va a la más cercana con el muelle de la hoja del kit. Con Reducir
    /// movimiento no viaja: salta a su sitio y la cabecera, la barra y el título pequeño se funden (ver sus `fade`).
    private func settle() {
        guard let target = BankHeaderMath.settleTarget(offset: scroll.offset, dock: scroll.dock) else { return }
        let move = {
            if target > 0 {
                position.scrollTo(id: Self.sheetID, anchor: .top)
            } else {
                position.scrollTo(edge: .top)
            }
        }
        if motion.reduce {
            var jump = Transaction()
            jump.disablesAnimations = true
            withTransaction(jump, move)
        } else {
            withAnimation(motion.animation(.sheet), move)
        }
    }
}

/// La cabecera: va dentro del desplazamiento (sus botones se tocan) y compensa lo desplazado para quedarse atrás.
private struct BankHeaderLayer<Content: View>: View {
    let scroll: BankHeaderScroll
    let shown: Bool
    let entered: Bool
    @ViewBuilder let content: Content

    @Environment(\.motion) private var motion

    var body: some View {
        let p = scroll.progress
        let y = max(0, scroll.offset)
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            // La cabecera se mueve como una sola pieza: las entradas de sus partes (cada una con su muelle) no se
            // mezclan con el desplazamiento del conjunto.
            .geometryGroup()
            .scaleEffect(motion.reduce ? 1 : BankHeaderMath.headerScale(p, distanceScale: motion.level.distanceScale), anchor: .top)
            // Sube al 32 % de lo desplazado (paralaje); con Reducir movimiento se queda quieta bajo la hoja.
            .offset(y: motion.reduce ? y : 0.68 * y)
            // Con Reducir movimiento, cuando la hoja salta a su sitio al soltar, la cabecera se funde (no viaja).
            .animation(motion.reduce ? motion.fade : nil) { $0.opacity(BankHeaderMath.headerOpacity(p)) }
            .opacity(entered && shown ? 1 : 0)
            .offset(y: entered ? 0 : motion.distance(12))
            // Lo que sube por encima del borde de arriba de la zona visible (la barra, con el botón de volver) no se
            // dibuja: la cabecera se corta ahí, con un borde suave de hasta 16 pt por debajo, nunca por encima.
            .mask(alignment: .top) {
                VStack(spacing: 0) {
                    // Un degradado de hasta 24 pt (nunca un corte a cuchillo bajo la flecha de volver, 13.2).
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: min(24, 2 * y))
                    Rectangle()
                        .frame(height: 4000)
                }
                .offset(y: y)
            }
            // Tapada por la hoja ya no se toca ni se lee.
            .allowsHitTesting(p < 0.5 && shown)
            .accessibilityHidden(p > 0.6 || !shown)
    }
}

/// La hoja: fondo #141416 con las esquinas de arriba redondeadas, un filo de luz y sombra hacia la cabecera.
private struct BankSheetLayer<Content: View>: View {
    let scroll: BankHeaderScroll
    let entered: Bool
    @ViewBuilder let content: Content

    @Environment(\.motion) private var motion

    var body: some View {
        content
            // Al menos el alto de la pantalla: acoplada, tapa la cabecera entera.
            .frame(maxWidth: .infinity, minHeight: scroll.viewport, alignment: .top)
            .background { BankSheetBackground(scroll: scroll) }
            // La hoja sube como una sola pieza: sin esto, cada fila (que entra con su propio muelle y su retraso) se
            // quedaba atrás o se adelantaba a la hoja mientras esta llegaba.
            .geometryGroup()
            .offset(y: entered ? 0 : motion.distance(260))
            .opacity(entered || !motion.reduce ? 1 : 0)
    }
}

private struct BankSheetBackground: View {
    let scroll: BankHeaderScroll

    var body: some View {
        let radius = BankHeaderMath.cornerRadius(scroll.progress)
        let shape = UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius, style: .continuous)
        shape
            .fill(Theme.grouped)
            .overlay { shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.20), .white.opacity(0)], startPoint: .top, endPoint: .init(x: 0.5, y: 0.06)), lineWidth: 1) }
            .shadow(color: .black.opacity(0.6), radius: 20, y: -10)
            // Sigue por debajo del final del contenido: bajo la barra de pestañas se ve hoja, no el fondo.
            .padding(.bottom, -600)
            .accessibilityHidden(true)
    }
}

/// El fondo oscuro detrás de la cabecera: un resplandor gris muy tenue arriba que se funde en negro.
private struct BankHeaderBackdrop: View {
    var body: some View {
        RadialGradient(colors: [Color(hex: "#1E1F22"), Color(hex: "#0A0A0B"), .black],
                       center: .top, startRadius: 0, endRadius: 440)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

/// Lo que llega a la barra de navegación cuando la hoja sube: una barra negra (el saldo grande ya no se ve debajo) y,
/// centrado en ella, el título pequeño. Va dibujado en la zona de la barra del sistema (que aquí es transparente), justo
/// encima del contenido; no recibe toques (los botones de la barra siguen siendo los del sistema).
private struct BankHeaderBar: View {
    let scroll: BankHeaderScroll
    let title: String
    let balanceCents: Int?
    let hidden: Bool
    let reduce: Bool
    /// El fundido del kit: con Reducir movimiento, la barra y el título pequeño se funden cuando la hoja salta a su sitio.
    let fade: Animation

    var body: some View {
        GeometryReader { geo in
            let inset = geo.safeAreaInsets.top
            let p = scroll.progress
            ZStack(alignment: .bottom) {
                Color.black
                    .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5) }
                    .animation(reduce ? fade : nil) { $0.opacity(BankHeaderMath.barOpacity(p)) }
                    .accessibilityHidden(true)
                BankMiniTitle(scroll: scroll, title: title, balanceCents: balanceCents, hidden: hidden, reduce: reduce)
                    .frame(height: 44)
                    // Sitio para el botón de volver a la izquierda (y lo mismo a la derecha, para quedar centrado).
                    .padding(.horizontal, 76)
                    // Con Reducir movimiento (sin recorrido), su llegada y su ida también son un fundido.
                    .animation(reduce ? fade : nil, value: BankHeaderMath.miniTitle(p))
            }
            .frame(width: geo.size.width, height: inset)
            .offset(y: -inset)
        }
        .allowsHitTesting(false)
    }
}

/// «Revolut · 340,20 €» en la barra, cuando la hoja ya ha tapado el saldo grande. Con el ojo cerrado, la máscara.
private struct BankMiniTitle: View {
    let scroll: BankHeaderScroll
    let title: String
    let balanceCents: Int?
    let hidden: Bool
    let reduce: Bool

    var body: some View {
        let m = BankHeaderMath.miniTitle(scroll.progress)
        // Con la hoja abajo el título NO se monta: así no existe para nadie (un elemento suelto con opacidad 0 o marcado
        // como oculto sigue apareciendo en las pruebas de toque). Solo se monta mientras se ve.
        if m > 0.01 {
            VStack(spacing: 1) {
                Text(title)
                    .titan(.option)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.label)
                    .lineLimit(1)
                if let balanceCents {
                    Text(hidden ? maskedEUR(balanceCents, sign: false) : formatEUR(balanceCents).replacingOccurrences(of: "-", with: "\u{2212}"))
                        // Un punto más (13 pt): se lee de un vistazo (ojo de diseño 13.4).
                        .titan(.meta)
                        .foregroundStyle(Theme.label2)
                        .lineLimit(1)
                        .contentTransition(.identity)
                        .privacySensitive()
                        .accessibilityLabel(hidden ? "importe oculto" : formatEUR(balanceCents))
                }
            }
            // La barra es una guía de orientación: con letra enorme se queda en un tamaño que cabe en ella.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(balanceCents.map { "\(title), \(spokenAmount($0, hidden: hidden))" } ?? title)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("bank-mini-title")
            .opacity(m)
            .offset(y: reduce ? 0 : (1 - m) * 8)
            .transition(.opacity)
        }
    }
}

#if DEBUG
/// Solo en la demo con `-MiBancoDemoDockProbe`: un elemento invisible que dice lo acoplada que está la hoja (`p`), la
/// opacidad con la que se dibuja la cabecera (el saldo grande) y la del título pequeño, el mayor solape de las dos visto
/// en cada cambio de lo desplazado y el mayor solape de las curvas en todo el recorrido. Así una prueba puede fallar si
/// se ven dos saldos a la vez o si la hoja se queda a medio camino.
private struct BankDockProbe: View {
    let scroll: BankHeaderScroll
    @State private var seen: CGFloat = 0

    var body: some View {
        let p = scroll.progress
        let text = String(format: "p=%.3f;cabecera=%.3f;titulo=%.3f;solape=%.3f;curvas=%.3f",
                          Double(p), Double(BankHeaderMath.headerOpacity(p)), Double(BankHeaderMath.miniTitle(p)),
                          Double(seen), Double(BankHeaderMath.maxOverlap))
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityLabel("Sonda de la hoja")
            .accessibilityValue(text)
            .accessibilityIdentifier("bank-dock-probe")
            .allowsHitTesting(false)
            .onChange(of: p, initial: true) { _, new in
                seen = max(seen, BankHeaderMath.overlap(new))
            }
    }
}
#endif

/// Se apaga con la cabecera, más deprisa que ella: para las acciones rápidas (1 − 1,7·p).
private struct FadesWithBankHeader: ViewModifier {
    @Environment(BankHeaderScroll.self) private var scroll: BankHeaderScroll?

    func body(content: Content) -> some View {
        let p = scroll?.progress ?? 0
        content
            .opacity(BankHeaderMath.actionsOpacity(p))
            .allowsHitTesting(BankHeaderMath.actionsTouchable(p))
    }
}

/// El asa de la hoja: se apaga al acoplarse.
private struct FadesNearDock: ViewModifier {
    @Environment(BankHeaderScroll.self) private var scroll: BankHeaderScroll?

    func body(content: Content) -> some View {
        content.opacity(BankHeaderMath.handleOpacity(scroll?.progress ?? 0))
    }
}

extension View {
    /// Dentro de la cabecera de `BankHeaderSheet`: esta pieza se apaga antes que el resto al subir la hoja.
    func fadesWithBankHeader() -> some View { modifier(FadesWithBankHeader()) }
    /// Dentro de la hoja de `BankHeaderSheet`: se apaga en el último 10 % del recorrido (el asa).
    func fadesNearDock() -> some View { modifier(FadesNearDock()) }
}
