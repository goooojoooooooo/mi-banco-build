import SwiftUI
import MiBancoCore

/// Un paso de la guía por pantalla: dibujo, título, una sola acción, ayuda y «Siguiente».
/// Los pasos se deslizan con un muelle (Reducir movimiento: fundido). Se empuja dentro de la navegación de Ajustes.
struct GuideStepView: View {
    let track: GuideTrack
    let model: LedgerModel

    @State private var index: Int
    @State private var forward = true
    @State private var pendingStep: Int?
    @State private var helpOpen = false
    @State private var firstNoticeSeen = false
    @State private var shortcutsUnavailable = false
    /// Se abrió retomando una guía a medias: se ofrece «Empezar desde el principio».
    @State private var resumed: Bool
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// `start` es el paso de partida (demo), contando desde 0; `resume`, el paso en que se dejó la guía a medias.
    init(track: GuideTrack, model: LedgerModel, start: Int? = nil, resume: Int? = nil) {
        self.track = track
        self.model = model
        let count = guideSteps(for: track).count
        _index = State(initialValue: min(max(start ?? resume ?? 0, 0), count - 1))
        _resumed = State(initialValue: start == nil && resume != nil)
    }

    private var steps: [GuideStep] { guideSteps(for: track) }
    private var step: GuideStep { steps[index] }
    private var isLast: Bool { index == steps.count - 1 }
    private var bigText: Bool { typeSize.isAccessibilitySize }
    private var status: GuideStatus { guideStatus(track, in: model.state, now: Date()) }

    private var slide: AnyTransition {
        if reduceMotion { return .opacity }
        let edge: Edge = forward ? .trailing : .leading
        let back: Edge = forward ? .leading : .trailing
        return .asymmetric(insertion: .move(edge: edge).combined(with: .opacity),
                           removal: .move(edge: back).combined(with: .opacity))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                page
                    .id(step.id)
                    .transition(slide)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .simultaneousGesture(
                DragGesture(minimumDistance: 30).onEnded { value in
                    let dx = value.translation.width
                    guard abs(dx) > 70, abs(dx) > abs(value.translation.height) * 1.5 else { return }
                    if dx < 0 { advance() } else { goBack() }
                })
            controls
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Avisos al instante")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pendingStep) { _, target in
            if let target { applyPending(target) }
        }
        .onChange(of: index) { _, now in preferences.setGuideStep(track, now) }
        .onChange(of: status) { old, new in
            if case .notYet = old, case .working = new {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.reveal) { firstNoticeSeen = true }
            }
        }
        .sensoryFeedback(trigger: firstNoticeSeen) { _, seen in seen ? SensoryFeedback.success : nil }
    }

    // MARK: Cabecera: «Parte 2 de 4 · Paso 9 de 22», la parte y los puntos de avance agrupados por parte

    private var header: some View {
        VStack(spacing: Theme.Space.small) {
            Text(guideProgressLabel(step, number: index + 1, total: steps.count))
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.label)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Space.gutter)
                .accessibilityIdentifier("guide-step-counter")
            Text("\(guideParts[step.part - 1]) · \(track.title)")
                .font(.system(.footnote))
                .foregroundStyle(Theme.label2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Space.gutter)
                .accessibilityIdentifier("guide-step-part")
            HStack(spacing: 12) {
                ForEach(1...guideParts.count, id: \.self) { part in
                    HStack(spacing: 5) {
                        ForEach(steps.indices.filter { steps[$0].part == part }, id: \.self) { i in
                            Capsule()
                                .fill(i == index ? Theme.label : (i < index ? Theme.label2 : Theme.passive))
                                .frame(width: i == index ? 18 : 6, height: 6)
                        }
                    }
                }
            }
            .animation(reduceMotion ? nil : Theme.Motion.morph, value: index)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        // La cabecera es una guía de orientación: con letra enorme se queda en un tamaño que no come la pantalla.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.top, Theme.Space.small)
        .padding(.bottom, Theme.Space.row)
    }

    // MARK: Contenido del paso

    /// Con letra normal el dibujo es el elemento flexible: se encoge (con sus proporciones) hasta el alto que deja el texto,
    /// y todo cabe sin deslizar. Solo si el dibujo quedaría por debajo de `minDrawing` pt el contenido se desliza.
    private static let minDrawing: CGFloat = 180

    @ViewBuilder private var page: some View {
        if bigText {
            // Con letra de accesibilidad primero lo que hay que hacer y después el dibujo; se desliza.
            ScrollView {
                VStack(spacing: Theme.Space.gutter) {
                    stepText
                    GuideIllustrationView(step: step, track: track)
                }
                .padding(.horizontal, Theme.Space.gutter)
                .padding(.bottom, Theme.Space.gutter)
            }
            .scrollIndicatorsFlash(onAppear: true)
        } else {
            ViewThatFits(in: .vertical) {
                GuideFitLayout(spacing: Theme.Space.gutter, minDrawing: Self.minDrawing, maxDrawing: 395) {
                    GuideIllustrationView(step: step, track: track, fitted: true)
                    stepText
                }
                .padding(.horizontal, Theme.Space.gutter)
                .padding(.bottom, Theme.Space.small)
                ScrollView {
                    VStack(spacing: Theme.Space.gutter) {
                        GuideIllustrationView(step: step, track: track, fitted: true)
                            .frame(height: 240)
                        stepText
                    }
                    .padding(.horizontal, Theme.Space.gutter)
                    .padding(.bottom, Theme.Space.gutter)
                }
                .scrollIndicatorsFlash(onAppear: true)
            }
        }
    }

    private var stepText: some View {
        VStack(spacing: Theme.Space.row) {
            if firstNoticeSeen { workingBanner.transition(.opacity.combined(with: .scale(scale: 0.96))) }
            textBlock
        }
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Space.row) {
            Text(step.title)
                .font(.system(.title, weight: .bold))
                .foregroundStyle(Theme.label)
                .accessibilityAddTraits(.isHeader)
            Text(Self.styled(step.instruction))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("guide-instruction")
            helpDisclosure
            // Solo en una guía retomada y nunca en el primer paso: texto dentro del contenido, después de la ayuda.
            if resumed && index > 0 {
                Button {
                    resumed = false
                    move(to: 0)
                } label: {
                    Text("Empezar desde el principio")
                        .font(.system(.callout, weight: .semibold))
                        .foregroundStyle(Theme.label2)
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("guide-restart")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// «¡Funciona!»: el ✓ se traza cuando llega el primer aviso real con la guía abierta.
    private var workingBanner: some View {
        HStack(spacing: Theme.Space.row) {
            DrawnCheck(lineWidth: 3, color: Theme.label)
                .frame(width: 26, height: 26)
            Text(track.isApplePay ? "¡Funciona! Ha llegado el primer pago con Apple Pay de \(track.bankName)."
                                  : "¡Funciona! Ha llegado el primer aviso de \(track.bankName).")
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(Theme.label)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.row)
        .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("guide-working")
    }

    private var helpDisclosure: some View {
        VStack(alignment: .leading, spacing: Theme.Space.small) {
            Button {
                withAnimation(reduceMotion ? .easeOut(duration: 0.15) : Theme.Motion.reveal) { helpOpen.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("¿No te sale esto?")
                        .font(.system(.callout, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(.caption, weight: .bold))
                        .rotationEffect(.degrees(helpOpen ? 180 : 0))
                }
                .foregroundStyle(Theme.label)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("guide-help")
            .accessibilityValue(helpOpen ? "Abierto" : "Cerrado")
            if helpOpen {
                Text(step.help)
                    .font(.callout)
                    .foregroundStyle(Theme.label2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Theme.Space.row)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .accessibilityIdentifier("guide-help-text")
            }
        }
    }

    // MARK: Botones fijos: Abrir Atajos, Atrás, Siguiente

    private var controls: some View {
        VStack(spacing: Theme.Space.row) {
            if shortcutsUnavailable {
                Text("No se pudo abrir \(GuideNames.shortcutsApp). Búscala en tu iPhone o descárgala del App Store.")
                    .font(.footnote)
                    .foregroundStyle(Theme.label2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("guide-open-failed")
                    .transition(.opacity)
            }
            Button {
                shortcutsUnavailable = false
                guard let url = URL(string: "shortcuts://") else { return }
                // El sistema avisa si no ha podido abrirla (por ejemplo, si no está instalada).
                openURL(url) { accepted in
                    if !accepted { withAnimation(reduceMotion ? nil : Theme.Motion.quick) { shortcutsUnavailable = true } }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.forward.app")
                    Text("Abrir \(GuideNames.shortcutsApp)")
                }
                .font(.system(.callout, weight: .semibold))
                .foregroundStyle(Theme.label)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.white.opacity(0.12), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("guide-open-shortcuts")

            HStack(spacing: Theme.Space.row) {
                if index > 0 {
                    Button { goBack() } label: {
                        Text("Atrás")
                            .font(.system(.body, weight: .semibold))
                            .foregroundStyle(Theme.label)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Color.white.opacity(0.12), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityIdentifier("guide-back")
                    .transition(.opacity)
                }
                Button { advance() } label: {
                    Text(isLast ? "Hecho" : "Siguiente")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.white, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("guide-next")
            }
            .animation(reduceMotion ? nil : Theme.Motion.quick, value: index > 0)
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.top, Theme.Space.row)
        // Los botones van siempre fijos abajo; con letra enorme se quedan en un tamaño que deja sitio al contenido.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.bottom, Theme.Space.row)
        .background(Theme.canvas)
        .sensoryFeedback(Haptics.detent, trigger: index)
    }

    // MARK: Navegación entre pasos

    private func advance() {
        if isLast {
            preferences.setGuideStep(track, nil)
            dismiss()
        } else { move(to: index + 1) }
    }

    private func goBack() {
        if index > 0 { move(to: index - 1) }
    }

    /// Primero se fija el sentido y el paso al que ir; el cambio de paso se hace en `onChange`, ya con el sentido
    /// pintado, para que el paso que sale y el que entra se deslicen hacia el mismo lado (sin temporizadores).
    private func move(to target: Int) {
        forward = target > index
        pendingStep = target
    }

    private func applyPending(_ target: Int) {
        pendingStep = nil
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0.18)) {
            index = target
            helpOpen = false
            shortcutsUnavailable = false
        }
    }

    /// Lo que va entre «» en blanco y seminegrita; el resto, apagado.
    static func styled(_ text: String) -> AttributedString {
        var out = AttributedString()
        var inside = false
        var buffer = ""
        func flush() {
            guard !buffer.isEmpty else { return }
            var part = AttributedString(buffer)
            part.foregroundColor = inside ? Theme.label : Theme.label2
            if inside { part.font = .body.weight(.semibold) }
            out += part
            buffer = ""
        }
        for ch in text {
            if ch == "«" {
                flush()
                inside = true
                buffer.append(ch)
            } else if ch == "»" {
                buffer.append(ch)
                flush()
                inside = false
            } else {
                buffer.append(ch)
            }
        }
        flush()
        return out
    }
}

/// Dibujo flexible arriba y texto debajo: el texto toma su alto y el dibujo, lo que queda (entre `minDrawing` y
/// `maxDrawing`). Sin alto propuesto devuelve el mínimo, que es lo que `ViewThatFits` necesita para decidir si cabe.
private struct GuideFitLayout: Layout {
    let spacing: CGFloat
    let minDrawing: CGFloat
    let maxDrawing: CGFloat

    private func drawingHeight(room: CGFloat?, text: CGFloat) -> CGFloat {
        guard let room else { return minDrawing }
        return min(max(room - text - spacing, minDrawing), maxDrawing)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let width = proposal.width ?? 295
        let text = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        return CGSize(width: width, height: drawingHeight(room: proposal.height, text: text) + spacing + text)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let text = subviews[1].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
        let drawing = drawingHeight(room: bounds.height, text: text)
        subviews[0].place(at: bounds.origin, anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: drawing))
        subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + drawing + spacing), anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: text))
    }
}
