import SwiftUI

/// Interruptor en blanco y negro (el verde es solo para el dinero que entra): carril #39393D → #F2F2F7,
/// bolita blanca → negra con un muelle. Zona táctil de toda la fila; para VoiceOver sigue siendo un interruptor.
struct TitanToggleStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.32, bounce: 0.25)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack(spacing: Theme.Space.row) {
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
                Capsule()
                    .fill(configuration.isOn ? Color(hex: "#F2F2F7") : Color(hex: "#39393D"))
                    .frame(width: 51, height: 31)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(configuration.isOn ? Color.black : Color.white)
                            .shadow(color: .black.opacity(0.3), radius: 3, y: 1.5)
                            .frame(width: 27, height: 27)
                            .padding(2)
                    }
                    .frame(minHeight: 44)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
        }
    }
}
