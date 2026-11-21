import SwiftUI

/// Botón que se transforma: cápsula blanca con su título → círculo (del alto de la cápsula) con rueda de carga → ✓ que se dibuja con
/// rebote → vuelve a la cápsula tras 1,1 s. Si `action` devuelve false, se sacude 6 pt dos veces y enseña el error.
/// Con Reducir movimiento la cápsula no cambia de forma: el título, la rueda y el ✓ se funden. Hápticas: éxito y aviso.
/// Todo el botón es un único elemento de accesibilidad: su etiqueta es el título y, al acabar, `doneTitle`.
/// Tamaño: nunca mayor que su sitio. El ancho es como mucho el escalado con el texto (220 pt a tamaño normal) y nunca más
/// que el contenedor; el alto sale del título más el relleno vertical (mínimo 52 pt) y no se estira con el hueco libre.
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
    /// Ancho máximo de la cápsula: crece con el tamaño de texto, pero el contenedor manda.
    @ScaledMetric(relativeTo: .body) private var width = 220.0
    /// Alto de la cápsula en reposo (lo mide `onGeometryChange`): el círculo de carga tiene ese mismo alto.
    @State private var idleHeight = Self.minHeight

    private static let minHeight: CGFloat = 52

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
        // El título (invisible en la carga) manda en el alto; el fondo es un fondo, no pide tamaño. El círculo es un
        // marco del alto de reposo, sin mínimos rígidos en el ancho: el contenedor lo acota.
        ZStack {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.black)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
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
        .frame(
            minWidth: isCircle ? idleHeight : nil, maxWidth: isCircle ? idleHeight : width,
            minHeight: isCircle ? idleHeight : Self.minHeight, maxHeight: isCircle ? idleHeight : nil)
        .background(Capsule().fill(.white))
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            // Solo en reposo: durante la carga el marco ya es el círculo.
            if phase == .idle { idleHeight = height }
        }
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
