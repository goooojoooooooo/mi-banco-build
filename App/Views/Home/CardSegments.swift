import SwiftUI

/// Todo / Revolut / imagin / Trade Rep., sincronizado en los dos sentidos con el carrusel.
/// El indicador (cristal en iOS 26+, #1C1C1E antes) no se anima aparte: sigue de forma continua la posición
/// del carrusel mientras se arrastra, así que nunca va por detrás del dedo. Tocar un segmento desliza el carrusel.
struct CardSegments: View {
    let cards: [AccountCard]
    @Binding var selection: AccountCard?
    let motion: HomeMotion

    @Environment(\.motion) private var kit
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Con tamaños de accesibilidad los segmentos en anchura fija se montaban unos sobre otros («Revolutimagin»,
    /// «Trade…»): en una tira horizontal desplazable cada cápsula se lee entera y conserva 44 pt de alto mínimo.
    private var scrollsHorizontally: Bool {
        #if DEBUG
        if DemoMode.oldHomeAX { return false }
        #endif
        return typeSize.isAccessibilitySize
    }

    var body: some View {
        if scrollsHorizontally {
            accessibilityBar
        } else {
            standardBar
        }
    }

    private var standardBar: some View {
        HStack(spacing: 0) {
            ForEach(cards, id: \.self) { card in
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
        .animation(kit.fade, value: selection)
        .background(alignment: .leading) {
            GeometryReader { geo in
                SegmentIndicator(
                    motion: motion,
                    count: cards.count,
                    segmentWidth: geo.size.width / CGFloat(max(cards.count, 1))
                )
            }
        }
        .padding(.horizontal, Theme.Space.gutter)
    }

    private var accessibilityBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(cards, id: \.self) { card in
                        let selected = (selection ?? .all) == card
                        Button {
                            select(card)
                        } label: {
                            Text(card.segmentTitle)
                                .titan(.subtitle)
                                .fontWeight(.medium)
                                .lineLimit(1)
                                .fixedSize()
                                .foregroundStyle(selected ? Theme.label : Theme.label3)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .frame(minHeight: 44)
                                .background {
                                    if selected {
                                        Color.clear.glassSurface(Capsule())
                                    }
                                }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .id(card)
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                    }
                }
                .padding(.leading, Theme.Space.gutter)
                .padding(.trailing, Theme.Space.gutter + 16)
            }
            .scrollIndicators(.hidden)
            .overlay(alignment: .trailing) {
                LinearGradient(
                    colors: [.clear, Theme.canvas],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 24)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .onChange(of: selection) { _, new in
                guard let new else { return }
                withAnimation(kit.reduce ? nil : kit.animation(.snap)) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
        .animation(kit.fade, value: selection)
    }

    private func select(_ card: AccountCard) {
        #if DEBUG
        // Solo demo (`-MiBancoDemoCardMoment`): tocar el segmento que ya está elegido dispara ese momento de la tarjeta.
        if card == (selection ?? .all), DemoMode.cardMoment != nil {
            motion.demoMomentTick += 1
            return
        }
        #endif
        withAnimation(kit.reduce ? nil : kit.animation(.snap)) { selection = card }
    }
}

/// Solo esta vista lee la posición del carrusel en cada fotograma.
private struct SegmentIndicator: View {
    let motion: HomeMotion
    let count: Int
    let segmentWidth: CGFloat

    var body: some View {
        let last = CGFloat(max(count - 1, 0))
        let position = min(max(motion.carouselPosition, 0), last)
        Color.clear
            .frame(width: max(segmentWidth - 6, 0), height: 36)
            .glassSurface(Capsule())
            .offset(x: position * segmentWidth + 3, y: 4)
            .accessibilityHidden(true)
    }
}
