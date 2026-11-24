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
    /// La cabecera se apaga un poco antes de que la hoja llegue arriba.
    static func headerOpacity(_ p: CGFloat) -> CGFloat { unit(1 - 1.05 * unit(p)) }
    /// Las acciones rápidas se apagan antes que el resto.
    static func actionsOpacity(_ p: CGFloat) -> CGFloat { unit(1 - 1.7 * unit(p)) }
    /// Esquinas de la hoja: 30 pt hasta p = 0,82 y de ahí a 0.
    static func cornerRadius(_ p: CGFloat) -> CGFloat { 30 * (1 - unit((unit(p) - 0.82) / 0.18)) }
    /// El título pequeño («Banco · saldo») entra entre p = 0,7 y 1.
    static func miniTitle(_ p: CGFloat) -> CGFloat { unit((unit(p) - 0.7) / 0.3) }
    /// La barra negra llega con el título pequeño (p 0,74–0,94): el saldo grande ya no se ve debajo.
    static func barOpacity(_ p: CGFloat) -> CGFloat { unit((unit(p) - 0.74) / 0.2) }
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
        .background { BankHeaderBackdrop() }
        .overlay(alignment: .top) {
            BankHeaderBar(scroll: scroll, title: title, balanceCents: balanceCents, hidden: hidden, reduce: motion.reduce)
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
            .scaleEffect(motion.reduce ? 1 : BankHeaderMath.headerScale(p, distanceScale: motion.level.distanceScale), anchor: .top)
            // Sube al 32 % de lo desplazado (paralaje); con Reducir movimiento se queda quieta bajo la hoja.
            .offset(y: motion.reduce ? y : 0.68 * y)
            .opacity(BankHeaderMath.headerOpacity(p))
            .opacity(entered && shown ? 1 : 0)
            .offset(y: entered ? 0 : motion.distance(12))
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

    var body: some View {
        GeometryReader { geo in
            let inset = geo.safeAreaInsets.top
            ZStack(alignment: .bottom) {
                Color.black
                    .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5) }
                    .opacity(BankHeaderMath.barOpacity(scroll.progress))
                    .accessibilityHidden(true)
                BankMiniTitle(scroll: scroll, title: title, balanceCents: balanceCents, hidden: hidden, reduce: reduce)
                    .frame(height: 44)
                    // Sitio para el botón de volver a la izquierda (y lo mismo a la derecha, para quedar centrado).
                    .padding(.horizontal, 76)
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
        VStack(spacing: 1) {
            Text(title)
                .titan(.option)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.label)
                .lineLimit(1)
            if let balanceCents {
                Text(hidden ? maskedEUR(balanceCents, sign: false) : formatEUR(balanceCents).replacingOccurrences(of: "-", with: "\u{2212}"))
                    .titan(.caption)
                    .foregroundStyle(Theme.label2)
                    .lineLimit(1)
                    .contentTransition(.identity)
                    .privacySensitive()
            }
        }
        // La barra es una guía de orientación: con letra enorme se queda en un tamaño que cabe en ella.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(balanceCents.map { "\(title), \(spokenAmount($0, hidden: hidden))" } ?? title)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("bank-mini-title")
        .accessibilityHidden(m < 0.5)
        // La opacidad va por FUERA del elemento de accesibilidad: a 0 (hoja abajo) el título no existe para nadie.
        .opacity(m)
        .offset(y: reduce ? 0 : (1 - m) * 8)
    }
}

/// Se apaga con la cabecera, más deprisa que ella: para las acciones rápidas (1 − 1,7·p).
private struct FadesWithBankHeader: ViewModifier {
    @Environment(BankHeaderScroll.self) private var scroll: BankHeaderScroll?

    func body(content: Content) -> some View {
        content.opacity(BankHeaderMath.actionsOpacity(scroll?.progress ?? 0))
    }
}

extension View {
    /// Dentro de la cabecera de `BankHeaderSheet`: esta pieza se apaga antes que el resto al subir la hoja.
    func fadesWithBankHeader() -> some View { modifier(FadesWithBankHeader()) }
}
