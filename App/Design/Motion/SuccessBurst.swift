import SwiftUI

/// Destello de luz (nunca confeti): un anillo que crece de 0,6 a 2,5 en 640 ms y 10 rayos que se alejan de 30 a 64 pt
/// en 560 ms. Se dispara cada vez que `trigger` cambia. Con Reducir movimiento o Bajo consumo no dibuja nada: el ✓ y
/// la háptica los pone quien lo usa. Se centra en el espacio que se le da y no recibe toques.
struct SuccessBurst: View {
    let trigger: Int
    var tint: Color = .white
    @Environment(\.motion) private var motion

    private static let rays = 10

    @State private var startedAt: Date?

    var body: some View {
        if motion.richEffects {
            // Una sola TimelineView, en pausa mientras no hay destello.
            TimelineView(.animation(paused: startedAt == nil)) { context in
                let elapsed = startedAt.map { context.date.timeIntervalSince($0) } ?? 0
                burst(elapsed / (0.64 * motion.timeMultiplier))
            }
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: trigger) { _, _ in startedAt = Date() }
            .task(id: startedAt) {
                guard startedAt != nil else { return }
                try? await Task.sleep(for: .seconds(0.7 * motion.timeMultiplier))
                guard !Task.isCancelled else { return }
                startedAt = nil
            }
        }
    }

    /// `progress` 0…1 sobre los 640 ms; fuera de 0…1 no hay nada que dibujar.
    @ViewBuilder private func burst(_ progress: Double) -> some View {
        if progress > 0, progress < 1 {
            ZStack {
                let ring = easeOut(progress)
                Circle()
                    .strokeBorder(tint.opacity(0.7), lineWidth: 1.5)
                    .frame(width: 80, height: 80)
                    .scaleEffect(0.6 + 1.9 * ring)
                    .opacity(0.85 * (1 - progress))
                ForEach(0..<Self.rays, id: \.self) { i in
                    ray(i, elapsed: progress * 640)
                }
            }
        }
    }

    private func ray(_ index: Int, elapsed: Double) -> some View {
        // 560 ms con un retardo de 40 ms (+ 30 ms en los rayos impares).
        let k = min(1, max(0, (elapsed - 40 - Double(index % 2) * 30) / 560))
        let v = easeOut(k)
        return Capsule()
            .fill(tint.opacity(0.85))
            .frame(width: 2, height: 12)
            .scaleEffect(y: 1 - 0.6 * v)
            .offset(y: -(30 + motion.distance(34) * v))
            .rotationEffect(.degrees(Double(index) * 36))
            .opacity(k <= 0 ? 0 : (k < 0.2 ? k / 0.2 : 1 - (k - 0.2) / 0.8))
    }

    private func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 4) }
}
