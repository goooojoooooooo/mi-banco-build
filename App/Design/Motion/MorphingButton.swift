import SwiftUI

/// Botón que se transforma: cápsula blanca con su título → círculo de 52 pt con rueda de carga → ✓ que se dibuja con
/// rebote → vuelve a la cápsula tras 1,1 s. Si `action` devuelve false, se sacude 6 pt dos veces y enseña el error.
/// Con Reducir movimiento la cápsula no cambia de forma: el título, la rueda y el ✓ se funden. Hápticas: éxito y aviso.
/// Todo el botón es un único elemento de accesibilidad: su etiqueta es el título y, al acabar, `doneTitle`.
struct MorphingButton: View {
    let title: String
    let doneTitle: String
    let action: () async -> Bool
    var failureText = "No se ha podido. Inténtalo otra vez."

    private enum Phase { case idle, loading, done }

    @State private var phase = Phase.idle
    @State private var errorShown = false
    @State private var doneCount = 0
    @State private var failCount = 0
    @Environment(\.motion) private var motion

    private var isCircle: Bool { phase != .idle && !motion.reduce }

    var body: some View {
        VStack(spacing: 8) {
            Button { Task { await run() } } label: { face }
                .buttonStyle(.pressable)
                .disabled(phase != .idle)
                .accessibilityLabel(phase == .done ? doneTitle : title)
            if errorShown {
                Text(failureText)
                    .titan(.meta)
                    .foregroundStyle(Theme.warning)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .keyframeAnimator(initialValue: 0.0, trigger: motion.reduce ? 0 : failCount) { content, x in
            content.offset(x: x)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(6.0, duration: 0.06)
                LinearKeyframe(-6.0, duration: 0.10)
                LinearKeyframe(6.0, duration: 0.10)
                LinearKeyframe(-6.0, duration: 0.10)
                LinearKeyframe(0.0, duration: 0.06)
            }
        }
        .sensoryFeedback(Haptics.success, trigger: doneCount)
        .sensoryFeedback(Haptics.warning, trigger: failCount)
    }

    private var face: some View {
        ZStack {
            Capsule().fill(.white)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.black)
                .lineLimit(1)
                .opacity(phase == .idle ? 1 : 0)
            ProgressView()
                .tint(.black)
                .opacity(phase == .loading ? 1 : 0)
            if phase == .done {
                DrawnCheck(lineWidth: 2.8, color: .black)
                    .frame(width: 24, height: 24)
                    .transition(motion.reduce ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .frame(width: isCircle ? 52 : 220, height: 52)
        .contentShape(Capsule())
        .frame(minWidth: 44, minHeight: 44)
    }

    private func run() async {
        errorShown = false
        withAnimation(motion.animation(.snap)) { phase = .loading }
        let began = Date()
        let ok = await action()
        // La rueda se ve al menos un instante, aunque la acción sea inmediata.
        let rest = 0.45 - Date().timeIntervalSince(began)
        if rest > 0 { try? await Task.sleep(for: .seconds(rest)) }
        if ok {
            withAnimation(motion.animation(.snap)) { phase = .done }
            doneCount += 1
            try? await Task.sleep(for: .milliseconds(1_100))
            withAnimation(motion.animation(.snap)) { phase = .idle }
        } else {
            withAnimation(motion.animation(.snap)) { phase = .idle }
            failCount += 1
            withAnimation(motion.fade) { errorShown = true }
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(motion.fade) { errorShown = false }
        }
    }
}
