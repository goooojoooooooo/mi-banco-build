import SwiftUI

/// Aro de «toca aquí»: un círculo blanco que crece de 0,4 a 1,5 y se apaga en 760 ms (aparece en el primer 15 % y se va
/// en el resto), una sola vez cada vez que `trigger` cambia, tras `delay` segundos del kit. No se repite solo ni se queda
/// en marcha: en reposo no dibuja nada. Con Reducir movimiento el aro no crece: aparece quieto y se funde.
/// No recibe toques ni existe para VoiceOver (lo que hay que tocar lo dice el texto del paso).
struct TapRing: View {
    let trigger: Int
    var size: CGFloat = 40
    var delay: Double = 0

    @Environment(\.motion) private var motion

    private struct Frame {
        var scale: CGFloat = 0.4
        var opacity: Double = 0
    }

    var body: some View {
        Circle()
            .strokeBorder(.white, lineWidth: 2)
            .frame(width: size, height: size)
            .keyframeAnimator(initialValue: Frame(scale: motion.reduce ? 1 : 0.4), trigger: trigger) { content, frame in
                content
                    .scaleEffect(frame.scale)
                    .opacity(frame.opacity)
            } keyframes: { _ in
                let wait = max(0.001, motion.seconds(delay))
                let run = motion.seconds(0.76)
                KeyframeTrack(\.scale) {
                    LinearKeyframe(motion.reduce ? 1 : 0.4, duration: wait)
                    CubicKeyframe(motion.reduce ? 1 : 1.5, duration: run)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0, duration: wait)
                    LinearKeyframe(1, duration: run * 0.15)
                    LinearKeyframe(0, duration: run * 0.85)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
