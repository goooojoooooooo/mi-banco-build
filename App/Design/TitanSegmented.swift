import SwiftUI

/// Segmentado de Titanio: pastilla oscura con un indicador que se desliza con el muelle `indicator` y se aplasta (hasta
/// un 28 %) mientras corre. El aplastamiento sale de lo que le falta por recorrer, que en un muelle es proporcional a
/// su velocidad. `continuousPosition` (en segmentos, 0…n−1) hace que el indicador siga a otra cosa en continuo (el
/// carrusel) en lugar de animarse él.
/// Un solo tamaño de letra por control: los títulos nunca se encogen ni se recortan. Si TODOS caben en una línea a su
/// tamaño natural, los segmentos van en una fila; si no (texto muy grande), se apilan en vertical, una fila a todo el
/// ancho por opción (mínimo 44 pt, todas igual de altas) y el indicador se desliza en vertical por detrás de la elegida.
/// Cada opción se toca en toda su celda. Con Reducir movimiento el indicador no viaja: se funde de una celda a otra.
/// Háptica de tope al elegir.
struct TitanSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    var continuousPosition: CGFloat? = nil

    @Environment(\.motion) private var motion

    private var index: Int { options.firstIndex { $0.value == selection } ?? 0 }
    private var position: CGFloat { continuousPosition ?? CGFloat(index) }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            track(vertical: false)
            track(vertical: true)
        }
        .animation(motion.calmAnimation(.indicator), value: index)
        .sensoryFeedback(Haptics.detent, trigger: index)
    }

    /// La pastilla con las opciones en fila o apiladas. En fila, cada título va en una línea y a su ancho natural (si no
    /// cupiese, `ViewThatFits` pasa a la vertical); apilados, pueden ocupar las líneas que necesiten.
    private func track(vertical: Bool) -> some View {
        SegmentLayout(vertical: vertical) {
            ForEach(options.indices, id: \.self) { i in
                let selected = i == index
                Button {
                    selection = options[i].value
                } label: {
                    label(options[i].title, selected: selected, singleLine: !vertical)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .background { indicator(vertical: vertical) }
        .background {
            shape(vertical: vertical)
                .fill(Color(hex: "#0F0F11"))
                .overlay(shape(vertical: vertical).strokeBorder(.white.opacity(0.07), lineWidth: 0.5))
        }
        .clipShape(shape(vertical: vertical))
    }

    /// Toda la celda es el botón: el relleno la ocupa entera y `contentShape` es la celda.
    private func label(_ title: String, selected: Bool, singleLine: Bool) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(selected ? Theme.label : Theme.label2)
            .lineLimit(singleLine ? 1 : nil)
            .fixedSize(horizontal: singleLine, vertical: !singleLine)
            .multilineTextAlignment(.center)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity)
            .contentShape(Rectangle())
    }

    /// Lo que el indicador va por dentro de la pista.
    private static var inset: CGFloat { 3 }

    /// En fila, una cápsula (el radio se acota a la mitad del lado corto); apilada, esquinas de 26 pt en la pista y
    /// concéntricas (26 − 3 = 23 pt) en el indicador, que va 3 pt por dentro.
    private func shape(vertical: Bool, inset: Bool = false) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: vertical ? (inset ? 26 - Self.inset : 26) : 1_000, style: .continuous)
    }

    @ViewBuilder private func indicator(vertical: Bool) -> some View {
        if motion.reduce {
            // Sin viaje: un indicador por celda y solo se funde el elegido. El relleno es el MISMO que el del indicador
            // que viaja (3 pt alrededor de toda la pastilla), no uno por celda.
            let stack = options.indices.map { i in
                shape(vertical: vertical, inset: true)
                    .fill(Color(hex: "#2A2A2D"))
                    .overlay(shape(vertical: vertical, inset: true).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
                    .opacity(i == index ? 1 : 0)
            }
            Group {
                if vertical {
                    VStack(spacing: 0) { ForEach(stack.indices, id: \.self) { stack[$0] } }
                } else {
                    HStack(spacing: 0) { ForEach(stack.indices, id: \.self) { stack[$0] } }
                }
            }
            .padding(Self.inset)
            .animation(motion.fade, value: index)
        } else {
            Thumb(position: position, target: CGFloat(index), count: max(options.count, 1),
                  squash: continuousPosition != nil ? 0 : motion.level.bounceScale,
                  vertical: vertical, radius: vertical ? 26 - Self.inset : 1_000)
                .padding(Self.inset)
                .animation(continuousPosition == nil ? motion.animation(.indicator) : nil, value: index)
        }
    }

    /// El indicador. `Animatable`: SwiftUI interpola `position` y vuelve a dibujar en cada fotograma; `target` salta
    /// de golpe, así que `|target − position|` es lo que queda por recorrer. En vertical se desliza (y se aplasta) en y.
    private struct Thumb: View, Animatable {
        var position: CGFloat
        let target: CGFloat
        let count: Int
        let squash: Double
        let vertical: Bool
        let radius: CGFloat

        nonisolated var animatableData: CGFloat {
            get { position }
            set { position = newValue }
        }

        var body: some View {
            GeometryReader { proxy in
                let slot = (vertical ? proxy.size.height : proxy.size.width) / CGFloat(count)
                let stretch = min(0.28, Double(abs(target - position)) * 0.16 * squash)
                let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
                shape
                    .fill(Color(hex: "#2A2A2D"))
                    .overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
                    .frame(width: vertical ? proxy.size.width : slot, height: vertical ? slot : proxy.size.height)
                    .scaleEffect(x: vertical ? 1 - stretch * 0.4 : 1 + stretch, y: vertical ? 1 + stretch : 1 - stretch * 0.4)
                    .offset(x: vertical ? 0 : position * slot, y: vertical ? position * slot : 0)
            }
        }
    }
}

/// Reparte las celdas a partes iguales, en fila o en columna, todas con el mismo alto (el mayor). Su tamaño ideal es el
/// que necesitan los títulos a su ancho natural (en fila, n × el mayor): así `ViewThatFits` sabe si caben.
private struct SegmentLayout: Layout {
    let vertical: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let count = CGFloat(subviews.count)
        let widest = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        if vertical {
            let width = proposal.width ?? widest
            return CGSize(width: width, height: rowHeight(subviews, width: width) * count)
        }
        let width = proposal.width ?? widest * count
        return CGSize(width: width, height: rowHeight(subviews, width: width / count))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let count = CGFloat(subviews.count)
        let cellWidth = vertical ? bounds.width : bounds.width / count
        let cellHeight = vertical ? bounds.height / count : bounds.height
        for (i, subview) in subviews.enumerated() {
            let origin = CGPoint(
                x: bounds.minX + (vertical ? 0 : cellWidth * CGFloat(i)),
                y: bounds.minY + (vertical ? cellHeight * CGFloat(i) : 0))
            subview.place(at: origin, anchor: .topLeading, proposal: ProposedViewSize(width: cellWidth, height: cellHeight))
        }
    }

    private func rowHeight(_ subviews: Subviews, width: CGFloat) -> CGFloat {
        let cell = vertical ? width : width / CGFloat(subviews.count)
        return subviews.map { $0.sizeThatFits(ProposedViewSize(width: cell, height: nil)).height }.max() ?? 0
    }
}
