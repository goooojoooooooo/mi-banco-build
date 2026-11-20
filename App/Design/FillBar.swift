import SwiftUI
import MiBancoCore

/// Barra de progreso de gasto: se llena con un muelle que se pasa un poco y, al cruzar `warnAt` mientras se ve, pasa a
/// ámbar con un fundido, un pulso de luz (solo con efectos ricos) y una háptica de aviso, una sola vez por cruce.
/// Una barra que NACE ya pasada del límite sale en ámbar sin pulso ni háptica (las listas perezosas no deben vibrar al
/// desplazarse). Solo se anima `scaleEffect` (la barra va recortada a su pista). Con Reducir movimiento se llena con un
/// fundido y el ámbar se queda. `warnAt = nil` la deja siempre blanca.
/// `label` dice qué mide la barra («Comida»); VoiceOver lee ese nombre y el porcentaje.
struct FillBar: View {
    let fraction: Double
    var warnAt: Double? = 0.9
    var animatesOnAppear = true
    var label = "Progreso"

    @Environment(\.motion) private var motion
    @State private var shown: Double = 0
    @State private var warned = false
    @State private var warnCount = 0
    @State private var pulse = 0
    /// El valor más reciente: la espera del ámbar lo lee en vivo.
    @State private var latest: Double = 0
    @State private var appeared = false
    @State private var pending: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Color(hex: "#2E2E32"))
            Rectangle()
                .fill(Theme.label)
                .scaleEffect(x: MotionMath.unit(shown), anchor: .leading)
            Rectangle()
                .fill(Theme.warning)
                .scaleEffect(x: MotionMath.unit(shown), anchor: .leading)
                .opacity(warned ? 1 : 0)
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
        .accessibilityLabel(label)
        .accessibilityValue("\(MotionMath.percent(fraction)) %")
        .onAppear {
            // Reaparecer al desplazarse una lista no repite nada.
            guard !appeared else { return }
            appeared = true
            latest = fraction
            let over = isOver(fraction)
            // Nace pasada del límite: ámbar ya puesto, sin pulso ni háptica.
            warned = over
            shown = animatesOnAppear && !motion.reduce ? 0 : fraction
            if animatesOnAppear { fill(to: fraction, animated: true) }
        }
        .onChange(of: fraction) { _, new in change(to: new) }
    }

    private func isOver(_ value: Double) -> Bool {
        warnAt.map { value >= $0 } ?? false
    }

    private func fill(to target: Double, animated: Bool) {
        if motion.reduce {
            withAnimation(motion.fade) { shown = target }
            return
        }
        let spring = Animation.spring(
            response: motion.seconds(0.62),
            dampingFraction: 1 - min(0.62, 0.22 * motion.level.bounceScale))
        withAnimation(animated ? spring : nil) { shown = target }
    }

    private func change(to target: Double) {
        pending?.cancel()
        latest = target
        fill(to: target, animated: true)
        if isOver(target), !warned {
            // El ámbar entra cuando la barra llega al límite, con pulso y aviso. Si el valor cambia antes, la tarea se
            // cancela y, además, se vuelve a comprobar el valor en vivo.
            pending = Task {
                try? await Task.sleep(for: .seconds(motion.seconds(0.2)))
                guard !Task.isCancelled, isOver(latest) else { return }
                withAnimation(motion.calmAnimation(.row)) { warned = true }
                pulse += 1
                warnCount += 1
            }
        } else if !isOver(target), warned {
            withAnimation(motion.calmAnimation(.row)) { warned = false }
        }
    }
}
