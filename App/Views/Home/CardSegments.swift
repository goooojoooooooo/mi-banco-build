import SwiftUI

/// Todo / Revolut / imagin / Trade Rep., sincronizado en los dos sentidos con el carrusel.
/// El indicador (cristal en iOS 26+, #1C1C1E antes) no se anima aparte: sigue de forma continua la posición
/// del carrusel mientras se arrastra, así que nunca va por detrás del dedo. Tocar un segmento desliza el carrusel.
struct CardSegments: View {
    @Binding var selection: AccountCard?
    let motion: HomeMotion

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AccountCard.allCases, id: \.self) { card in
                Button {
                    select(card)
                } label: {
                    Text(card.segmentTitle)
                        .titan(.subtitle)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle((selection ?? .all) == card ? Theme.label : Theme.label3)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits((selection ?? .all) == card ? [.isSelected] : [])
            }
        }
        .animation(.easeOut(duration: 0.2), value: selection)
        .background(alignment: .leading) {
            GeometryReader { geo in
                SegmentIndicator(motion: motion, segmentWidth: geo.size.width / CGFloat(AccountCard.allCases.count))
            }
        }
        .padding(.horizontal, Theme.Space.gutter)
    }

    private func select(_ card: AccountCard) {
        withAnimation(reduceMotion ? nil : Theme.Motion.cardSettle) { selection = card }
    }
}

/// Solo esta vista lee la posición del carrusel en cada fotograma.
private struct SegmentIndicator: View {
    let motion: HomeMotion
    let segmentWidth: CGFloat

    var body: some View {
        let last = CGFloat(AccountCard.allCases.count - 1)
        let position = min(max(motion.carouselPosition, 0), last)
        Color.clear
            .frame(width: max(segmentWidth - 6, 0), height: 36)
            .glassSurface(Capsule(), interactive: false)
            .offset(x: position * segmentWidth + 3, y: 4)
            .accessibilityHidden(true)
    }
}
