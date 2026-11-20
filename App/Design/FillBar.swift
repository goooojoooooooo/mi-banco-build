import SwiftUI

/// Barra de progreso de gasto: se llena con un muelle que se pasa un poco y, al cruzar `warnAt`, pasa a ámbar con un
/// fundido, un pulso de luz (solo con efectos ricos) y una háptica de aviso, una sola vez por cruce.
/// Solo se anima `scaleEffect` (la barra va recortada a su pista). Con Reducir movimiento se llena con un fundido y
/// el ámbar se queda. `warnAt = nil` la deja siempre blanca.
struct FillBar: View {
    let fraction: Double
    var warnAt: Double? = 0.9
    var animatesOnAppear = true

    @Environment(\.motion) private var motion
    @State private var shown: Double = 0
    @State private var warned = false
    @State private var warnCount = 0
    @State private var pulse = 0

    private var amber: Bool { warned }

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Color(hex: "#2E2E32"))
            Rectangle()
                .fill(Theme.label)
                .scaleEffect(x: max(0, shown), anchor: .leading)
            Rectangle()
                .fill(Theme.warning)
                .scaleEffect(x: max(0, shown), anchor: .leading)
                .opacity(amber ? 1 : 0)
            Rectangle()
                .fill(Theme.warning)
                .keyframeAnimator(initialValue: 0.0, trigger: motion.richEffects ? pulse : 0) { content, v in
                    content.opacity(v)
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(0.9, duration: 0.45)
                        CubicKeyframe(0.0, duration: 0.45)
                    }
                }
        }
        .frame(height: 8)
        .clipShape(Capsule())
        .sensoryFeedback(Haptics.warning, trigger: warnCount)
        .accessibilityElement(children: .ignore)
        .accessibilityValue("\(Int((fraction * 100).rounded())) %")
        .onAppear {
            if animatesOnAppear { shown = 0 } else { shown = fraction }
            apply(fraction, initial: true)
        }
        .onChange(of: fraction) { _, new in apply(new, initial: false) }
    }

    private func apply(_ target: Double, initial: Bool) {
        let willWarn = warnAt.map { target >= $0 } ?? false
        if motion.reduce {
            withAnimation(motion.fade) {
                shown = target
                warned = willWarn
            }
            return
        }
        let spring = Animation.spring(
            response: motion.seconds(0.62),
            dampingFraction: 1 - min(0.62, 0.22 * motion.level.bounceScale))
        withAnimation(initial && !animatesOnAppear ? nil : spring) { shown = target }
        if willWarn, !warned {
            // El ámbar entra cuando la barra llega al límite (a ~40 % del recorrido), con pulso y aviso.
            Task {
                try? await Task.sleep(for: .seconds(initial ? motion.seconds(0.38) : motion.seconds(0.2)))
                guard fraction >= (warnAt ?? .infinity) else { return }
                withAnimation(motion.calmAnimation(.row)) { warned = true }
                pulse += 1
                warnCount += 1
            }
        } else if !willWarn, warned {
            withAnimation(motion.calmAnimation(.row)) { warned = false }
        }
    }
}
