import SwiftUI

/// Segmentado de Titanio: pastilla oscura con un indicador que se desliza con el muelle `indicator` y se aplasta (hasta
/// un 28 %) mientras corre. El aplastamiento sale de lo que le falta por recorrer, que en un muelle es proporcional a
/// su velocidad. `continuousPosition` (en segmentos, 0…n−1) hace que el indicador siga a otra cosa en continuo (el
/// carrusel) en lugar de animarse él. Cada segmento mide 44 pt de alto y se toca entero. Háptica de tope al elegir.
struct TitanSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    var continuousPosition: CGFloat? = nil

    @Environment(\.motion) private var motion

    private var index: Int { options.firstIndex { $0.value == selection } ?? 0 }
    private var position: CGFloat { continuousPosition ?? CGFloat(index) }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color(hex: "#0F0F11"))
                .overlay(Capsule().strokeBorder(.white.opacity(0.07), lineWidth: 0.5))
            Thumb(position: position, target: CGFloat(index), count: max(options.count, 1),
                  squash: motion.reduce || continuousPosition != nil ? 0 : motion.level.bounceScale)
                .padding(3)
                .animation(continuousPosition == nil ? (motion.reduce ? nil : motion.animation(.indicator)) : nil, value: index)
            HStack(spacing: 0) {
                ForEach(options.indices, id: \.self) { i in
                    let selected = i == index
                    Button {
                        selection = options[i].value
                    } label: {
                        Text(options[i].title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(selected ? Theme.label : Theme.label2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .animation(motion.calmAnimation(.indicator), value: index)
        }
        .frame(height: 44)
        .clipShape(Capsule())
        .sensoryFeedback(Haptics.detent, trigger: index)
    }

    /// El indicador. `Animatable`: SwiftUI interpola `position` y vuelve a dibujar en cada fotograma; `target` salta
    /// de golpe, así que `|target − position|` es lo que queda por recorrer.
    private struct Thumb: View, Animatable {
        var position: CGFloat
        let target: CGFloat
        let count: Int
        let squash: Double

        nonisolated var animatableData: CGFloat {
            get { position }
            set { position = newValue }
        }

        var body: some View {
            GeometryReader { proxy in
                let width = proxy.size.width / CGFloat(count)
                let stretch = min(0.28, Double(abs(target - position)) * 0.16 * squash)
                Capsule()
                    .fill(Color(hex: "#2A2A2D"))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
                    .frame(width: width, height: proxy.size.height)
                    .scaleEffect(x: 1 + stretch, y: 1 - stretch * 0.4)
                    .offset(x: position * width)
            }
        }
    }
}
