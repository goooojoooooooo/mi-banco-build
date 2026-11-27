import SwiftUI

/// B2: las 28 barras que se mueven mientras Nyx lee el resumen en voz alta (prototipo `openSpoken`). Solo se mueven
/// mientras habla: su `TimelineView` está en pausa en cuanto `speaking` es falso, y entonces las barras se quedan bajas
/// y quietas. Con Reducir movimiento, barras quietas a media altura (se ve que habla, sin movimiento). Solo escala
/// vertical de cada barra: nada de maquetación. No tiene nada que leer para VoiceOver (el botón ya dice «Parar»).
struct VoiceWave: View {
    let speaking: Bool
    var height: CGFloat = 44
    @Environment(\.motion) private var motion

    static let barCount = 28

    var body: some View {
        TimelineView(.animation(paused: !speaking || motion.reduce)) { context in
            let t = context.date.timeIntervalSinceReferenceDate / max(motion.timeMultiplier, 0.01)
            HStack(spacing: 4) {
                ForEach(0..<Self.barCount, id: \.self) { i in
                    Capsule()
                        .fill(Theme.label2)
                        .frame(width: 4, height: height)
                        .scaleEffect(x: 1, y: Self.level(bar: i, time: t, speaking: speaking, reduce: motion.reduce), anchor: .center)
                }
            }
            .frame(height: height)
        }
        .animation(motion.calmAnimation(.snap), value: speaking)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    /// Altura de la barra `bar` (0…1) en el instante `time`: el mismo dibujo del prototipo
    /// (0,18 + 0,82·|sin(7,3 t + 0,55 i)·sin(3,1 t + 1,7 i)|). Callada, 0,12; con Reducir movimiento, 0,3.
    static func level(bar: Int, time: Double, speaking: Bool, reduce: Bool) -> CGFloat {
        guard speaking else { return 0.12 }
        guard !reduce else { return 0.3 }
        let i = Double(bar)
        return CGFloat(0.18 + 0.82 * abs(sin(time * 7.3 + i * 0.55) * sin(time * 3.1 + i * 1.7)))
    }
}
