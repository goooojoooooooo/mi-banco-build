import SwiftUI

/// Deslizar para confirmar una acción que no se puede deshacer (en vez de una alerta).
/// El pulgar sigue al dedo 1:1, el carril se llena tras él; al soltar antes del 85 % vuelve con un muelle;
/// al llegar, el control se recoge en un círculo con un ✓ que se traza y entonces se ejecuta `action`.
/// VoiceOver: un botón normal con la etiqueta de la acción.
struct SlideToConfirm: View {
    let title: String
    var systemImage = "trash"
    var tint = Theme.warning
    let action: () -> Void

    @State private var offset: CGFloat = 0
    @State private var done = false
    @State private var confirmCount = 0
    @Environment(\.motion) private var motion

    private let height: CGFloat = 56
    private let inset: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let thumb = height - inset * 2
            let travel = max(geo.size.width - thumb - inset * 2, 1)
            let progress = min(max(offset / travel, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                Capsule()
                    .fill(tint.opacity(0.22))
                    .frame(width: done ? height : offset + thumb + inset * 2)
                Text(title)
                    .titan(.option)
                    .foregroundStyle(Theme.label2)
                    .frame(maxWidth: .infinity)
                    .padding(.leading, thumb)
                    .opacity(done ? 0 : Double(1 - progress * 1.4))
                Circle()
                    .fill(tint)
                    .frame(width: thumb, height: thumb)
                    .overlay {
                        if done {
                            DrawnCheck(lineWidth: 2.6, color: .black)
                                .padding(15)
                        } else {
                            Image(systemName: progress > 0.85 ? "checkmark" : systemImage)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.black)
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .offset(x: done ? 0 : offset)
                    .padding(.leading, inset)
                    .gesture(drag(travel: travel))
            }
            .frame(width: done ? height : geo.size.width, height: height)
            .frame(maxWidth: .infinity)
        }
        .frame(height: height)
        .sensoryFeedback(Haptics.confirm, trigger: confirmCount)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { complete() }
    }

    private func drag(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard !done else { return }
                offset = min(max(value.translation.width, 0), travel)
            }
            .onEnded { value in
                guard !done else { return }
                if offset >= travel * 0.85 || value.predictedEndTranslation.width >= travel * 1.2 {
                    complete()
                } else {
                    withAnimation(motion.animation(.snap)) { offset = 0 }
                }
            }
    }

    private func complete() {
        guard !done else { return }
        confirmCount += 1
        withAnimation(motion.animation(.snap)) {
            done = true
        } completion: {
            action()
        }
    }
}
