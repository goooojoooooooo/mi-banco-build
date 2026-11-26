import SwiftUI

/// Esqueleto de carga de una lista de movimientos: filas de fichas grises (logo, dos líneas, importe) con un brillo que
/// las barre de izquierda a derecha cada 1,15 s. Solo se usa mientras una lista se llena por PRIMERA vez (tras conectar un
/// banco): nunca tapa datos que ya había. No lleva ningún dato (ni cifras ni nombres), así que con el ojo cerrado es
/// igual. El brillo es una sola `TimelineView` que existe mientras el esqueleto está montado (quien lo usa lo quita al
/// llegar las filas) y que no se monta con Reducir movimiento ni con Bajo consumo: ahí el esqueleto se queda quieto.
struct SkeletonRows: View {
    var count = 5

    @Environment(\.motion) private var motion
    @Environment(\.scenePhase) private var scenePhase

    /// Anchos de las dos líneas y del importe de cada fila (no todas iguales: parece una lista, no una rejilla).
    private static let widths: [(title: CGFloat, subtitle: CGFloat, amount: CGFloat)] = [
        (132, 88, 62), (104, 120, 54), (150, 76, 70), (96, 104, 48), (124, 92, 58), (112, 68, 64),
    ]

    var body: some View {
        bones(Color.white.opacity(0.09))
            .overlay {
                if motion.richEffects {
                    // Parado con la app fuera de primer plano (menor m-1).
                    TimelineView(.animation(minimumInterval: nil, paused: scenePhase != .active)) { context in
                        let period = 1.15 * max(0.05, motion.level.timeScale * motion.timeMultiplier)
                        let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
                        GeometryReader { geo in
                            LinearGradient(colors: [.white.opacity(0), .white.opacity(0.16), .white.opacity(0)],
                                           startPoint: .leading, endPoint: .trailing)
                                .frame(width: geo.size.width * 0.55)
                                .offset(x: (-0.55 + 1.55 * phase) * geo.size.width)
                        }
                    }
                    // El brillo solo se ve sobre las fichas.
                    .mask { bones(.white) }
                    .allowsHitTesting(false)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Cargando movimientos")
            .accessibilityIdentifier("skeleton-rows")
    }

    private func bones(_ color: Color) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<max(1, count), id: \.self) { index in
                let width = Self.widths[index % Self.widths.count]
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: Theme.Radius.logo, style: .continuous)
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 7) {
                        Capsule().frame(width: width.title, height: 11)
                        Capsule().frame(width: width.subtitle, height: 9).opacity(0.6)
                    }
                    Spacer(minLength: 8)
                    Capsule().frame(width: width.amount, height: 11)
                }
                .padding(.horizontal, Theme.Space.gutter)
                .frame(height: 64)
            }
        }
        .foregroundStyle(color)
    }
}
