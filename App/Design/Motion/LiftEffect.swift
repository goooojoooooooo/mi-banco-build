import SwiftUI

/// Levantar un objeto (mantener pulsada una tarjeta): sube 9 pt, crece un 5 % y le sale una luz suave debajo.
/// Entra firme (`liftIn`) y al soltar rebota (`liftOut`). Con Reducir movimiento no se mueve nada; la luz solo con
/// efectos ricos (no con Bajo consumo). Háptica media al levantar.
private struct LiftEffect: ViewModifier {
    let lifted: Bool
    @Environment(\.motion) private var motion

    func body(content: Content) -> some View {
        let on = lifted && !motion.reduce
        content
            .background(alignment: .bottom) {
                RadialGradient(
                    colors: [Color(red: 0.88, green: 0.90, blue: 0.94).opacity(0.24), .clear],
                    center: .top, startRadius: 0, endRadius: 90)
                    .frame(height: 46)
                    .padding(.horizontal, 16)
                    .offset(y: 30)
                    .opacity(on && motion.richEffects ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .scaleEffect(on ? 1.05 : 1)
            .offset(y: on ? -motion.distance(9) : 0)
            .animation(lifted ? motion.animation(.liftIn) : motion.animation(.liftOut), value: lifted)
            .sensoryFeedback(.impact(weight: .medium), trigger: lifted) { _, new in new }
    }
}

extension View {
    func lift(_ lifted: Bool) -> some View { modifier(LiftEffect(lifted: lifted)) }
}
