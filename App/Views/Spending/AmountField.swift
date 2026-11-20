import SwiftUI

/// Campo de importe en euros (mismo aspecto que el de los saldos de Ajustes): sin foco es texto; con foco, fondo #2A2A2D.
/// 44 pt de alto y su zona de toque entera enfoca el campo. El ✓ se traza junto al campo cuando se acaba de guardar.
/// Con el modo privado, el valor se difumina salvo mientras se edita.
struct AmountField<ID: Hashable>: View {
    let id: ID
    @Binding var text: String
    var focused: FocusState<ID?>.Binding
    let placeholder: String
    let label: String
    let identifier: String
    let saved: Bool
    let stacked: Bool
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if saved {
                DrawnCheck(lineWidth: 2, color: Theme.label)
                    .frame(width: 16, height: 16)
                    .transition(.opacity)
                    .accessibilityLabel("Guardado")
            }
            TextField(placeholder, text: $text)
                .titan(.option)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.label)
                .multilineTextAlignment(stacked ? .leading : .trailing)
                .keyboardType(.numbersAndPunctuation)
                .submitLabel(.done)
                .focused(focused, equals: id)
                .onSubmit(onSubmit)
                .padding(.horizontal, 10)
                .frame(minWidth: 96, maxWidth: stacked ? .infinity : 128, minHeight: 44)
                .background(Color(hex: "#2A2A2D").opacity(focused.wrappedValue == id ? 1 : 0),
                            in: .rect(cornerRadius: Theme.Radius.field))
                .animation(Theme.Motion.quick, value: focused.wrappedValue == id)
                .privateField(editing: focused.wrappedValue == id)
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier)
        }
        .contentShape(Rectangle())
        .onTapGesture { focused.wrappedValue = id }
    }
}
