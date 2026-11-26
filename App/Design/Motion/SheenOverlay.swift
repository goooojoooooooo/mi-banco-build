import SwiftUI

/// Brillo diagonal que cruza una superficie (tarjeta, fila nueva). `phase` (0…1) lo desplaza; `tilt` (−1…1) lo mueve
/// con la inclinación o el dedo. Solo se anima el desplazamiento (`offset`). Con Bajo consumo o Reducir movimiento
/// no sigue la inclinación. No recibe toques: va encima, con el mismo recorte que la superficie.
struct SheenOverlay: View {
    let phase: CGFloat
    let tilt: CGFloat
    @Environment(\.motion) private var motion

    var body: some View {
        let tiltShift = motion.richEffects ? tilt : 0
        Rectangle()
            .fill(LinearGradient(
                stops: [.init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.30),
                        .init(color: .white.opacity(0.09), location: 0.45),
                        .init(color: .white.opacity(0.035), location: 0.53),
                        .init(color: .clear, location: 0.64),
                        .init(color: .clear, location: 1)],
                // ≈ 112° en CSS: casi horizontal, algo inclinado hacia abajo.
                startPoint: UnitPoint(x: 0.04, y: 0.31), endPoint: UnitPoint(x: 0.96, y: 0.69)))
            .scaleEffect(x: 2.2, anchor: .center)
            .visualEffect { content, proxy in
                content.offset(x: (phase - 0.5) * proxy.size.width * 0.9 + tiltShift * proxy.size.width * 0.3)
            }
            .opacity(0.75)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
