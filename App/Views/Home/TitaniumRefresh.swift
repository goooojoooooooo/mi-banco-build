import SwiftUI
import Observation

/// «Tirar para actualizar» de Inicio, con el indicador de titanio de la maqueta aprobada: la ola de la marca se dibuja
/// con el tirón, un toque ligero avisa de que ya basta, al soltar la ola baja al 45 % y una luz al 100 % la recorre (0,9 s
/// por pasada) mientras se actualiza y, al terminar, dice «Al día» 0,6 s (si es verdad) y se recoge.
/// - No hay gesto propio: el tirón es el rebote del sistema de la lista (se lee su desplazamiento), así que no compite
///   con el carrusel, con las filas ni con bajar la lista.
/// - Mientras actualiza, la lista se queda 64 pt más abajo con un desplazamiento (`offset`), no cambiando la maquetación.
/// - Con Reducir movimiento no hay hueco ni luz: el indicador solo se ve mientras se tira (su opacidad sigue al tirón) y
///   el resultado lo dice el aviso breve de arriba.
/// - Nada se queda en marcha: las pasadas de la luz acaban cuando acaba la actualización (como mucho 12).
@MainActor @Observable
final class TitaniumRefreshState {
    /// Cuánto hay que tirar para que al soltar se actualice.
    static let armDistance: CGFloat = 70
    /// Cuánto se queda bajada la lista mientras actualiza.
    static let holdDistance: CGFloat = 64

    /// Puntos que la lista está bajada ahora (0 en reposo).
    private(set) var hold: CGFloat = 0
    private(set) var busy = false
    /// Avance de la luz por la ola: cada pasada suma 1,6 vueltas (se dibuja su parte decimal).
    private(set) var glint = 0.0
    private(set) var glinting = false
    /// «Al día» a la vista.
    private(set) var done = false
    /// Sube cada vez que una actualización termina bien (háptica de éxito y aviso de VoiceOver).
    private(set) var doneTick = 0

    @ObservationIgnored private var outcome: Bool?

    /// Se soltó la lista con `pull` puntos de tirón: si llega al umbral y no hay otra en marcha, actualiza.
    /// `action` devuelve si todo fue bien (con un fallo no se dice «Al día»).
    func released(pull: CGFloat, motion: MotionContext, action: @escaping @MainActor () async -> Bool) {
        guard !busy, pull >= Self.armDistance else { return }
        start(motion: motion, action: action)
    }

    func start(motion: MotionContext, action: @escaping @MainActor () async -> Bool) {
        guard !busy else { return }
        busy = true
        done = false
        outcome = nil
        #if DEBUG
        HomeProbe.shared.refreshes += 1
        #endif
        Task { await run(motion: motion, action: action) }
    }

    private func run(motion: MotionContext, action: @escaping @MainActor () async -> Bool) async {
        if !motion.reduce {
            withAnimation(motion.animation(.snap)) { hold = Self.holdDistance }
        }
        Task { outcome = await action() }
        // Una pasada cada 0,9 s: la ola tiene vida mientras actualiza (no parece un indicador parado).
        let pass = motion.seconds(0.9)
        var passes = 0
        repeat {
            if motion.richEffects {
                glinting = true
                withAnimation(.linear(duration: pass)) { glint += 1.6 }
            }
            try? await Task.sleep(for: .seconds(pass + motion.seconds(0.05)))
            passes += 1
        } while outcome == nil && passes < 12
        glinting = false
        if outcome == true {
            withAnimation(motion.reduce ? motion.fade : .easeOut(duration: motion.seconds(0.15))) { done = true }
            doneTick += 1
            #if DEBUG
            HomeProbe.shared.refreshesDone += 1
            #endif
            try? await Task.sleep(for: .seconds(motion.seconds(0.6)))
        }
        if hold != 0 {
            withAnimation(motion.calmAnimation(.snap)) { hold = 0 }
            try? await Task.sleep(for: .seconds(motion.seconds(0.45)))
        }
        withAnimation(motion.fade) { done = false }
        busy = false
    }
}

/// La lista, bajada mientras se actualiza (solo esta pieza lee `hold`).
struct TitaniumRefreshHold: ViewModifier {
    let state: TitaniumRefreshState

    func body(content: Content) -> some View {
        content.offset(y: state.hold)
    }
}

/// El indicador. Va como primera pieza del contenido de la lista, sin ocupar alto: se dibuja en el hueco que se abre
/// encima del título al tirar. Solo esta vista lee el desplazamiento de la lista en cada fotograma.
struct TitaniumRefreshIndicator: View {
    let state: TitaniumRefreshState
    let motion: HomeMotion

    @Environment(\.motion) private var kit

    var body: some View {
        let pull: CGFloat = max(-motion.listOffset, 0)
        let gap: CGFloat = pull + state.hold
        let drawn: CGFloat = state.busy ? 1 : min(pull / TitaniumRefreshState.armDistance, 1)
        // Su opacidad sigue al hueco: al recogerse la lista se apaga con él (no se queda encima de la barra).
        let visible: CGFloat = min(gap / 34, 1)
        let armed = pull >= TitaniumRefreshState.armDistance && !state.busy
        let line = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        Color.clear
            .frame(height: 0)
            .overlay(alignment: .top) {
                ZStack {
                    // Mientras la luz la recorre, la ola baja al 45 % y la luz va al 100 %: se ve que trabaja.
                    WaveShape()
                        .trim(from: 0, to: drawn)
                        .stroke(Color(hex: "#D8DBE0"), style: line)
                        .opacity(state.glinting ? 0.45 : 1)
                        .animation(kit.fade, value: state.glinting)
                    if state.glinting {
                        WaveGlint(phase: state.glint)
                            .stroke(Color.white, style: line)
                    }
                }
                .frame(width: 40, height: 40)
                .scaleEffect(kit.reduce ? 1 : 0.7 + 0.3 * drawn)
                .overlay(alignment: .bottom) {
                    if state.done {
                        // Legible en el poco tiempo que está: 13 pt, blanco al 70 %.
                        Text("Al día")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .fixedSize()
                            .offset(y: 16)
                            .transition(.opacity)
                            .accessibilityIdentifier("home-refresh-done")
                    }
                }
                .fixedSize()
                .opacity(visible)
                // Centrado en el hueco que deja la lista al bajar.
                .offset(y: -gap / 2 - 26)
                .allowsHitTesting(false)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: armed) { _, now in now }
            .sensoryFeedback(Haptics.success, trigger: state.doneTick)
            .onChange(of: state.doneTick) { _, _ in
                // Con Reducir movimiento lo anuncia el aviso breve de Inicio: una sola vez, no dos.
                if !kit.reduce { AccessibilityNotification.Announcement("Al día").post() }
            }
            .accessibilityHidden(!state.done)
    }
}

/// La luz que recorre la ola: un tramo corto (22 % del trazo) que avanza con `phase` (su parte decimal).
private struct WaveGlint: Shape {
    var phase: Double

    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let turn = phase - phase.rounded(.down)
        let head = CGFloat(turn * 1.22)
        return WaveShape().path(in: rect).trimmedPath(from: max(0, head - 0.22), to: min(1, head))
    }
}
