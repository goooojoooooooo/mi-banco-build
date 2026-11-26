import SwiftUI

/// Campo de importe en euros (mismo aspecto que el de los saldos de Ajustes): sin foco es texto; con foco, fondo #2A2A2D.
/// 44 pt de alto y su zona de toque entera enfoca el campo. El ✓ se traza junto al campo cuando se acaba de guardar.
/// Con el modo privado, el valor no se dibuja (máscara del kit) salvo mientras se edita.
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

    @Environment(AppPreferences.self) private var preferences
    @Environment(\.motion) private var motion

    var body: some View {
        HStack(spacing: 8) {
            if saved {
                DrawnCheck(lineWidth: 2, color: Theme.label)
                    .frame(width: 16, height: 16)
                    .transition(.opacity)
                    .accessibilityLabel("Guardado")
            }
            // Con el ojo cerrado (y sin editar) el campo contiene la máscara del kit, no el límite.
            MaskedAmountTextField(placeholder: placeholder, text: $text, masked: masked)
                .titan(.option)
                .fontWeight(.semibold)
                .multilineTextAlignment(stacked ? .leading : .trailing)
                .keyboardType(.numbersAndPunctuation)
                .submitLabel(.done)
                .focused(focused, equals: id)
                .onSubmit(onSubmit)
                .padding(.horizontal, 10)
                .frame(minWidth: 96, maxWidth: stacked ? .infinity : 128, minHeight: 44)
                .background(Theme.fieldFill.opacity(focused.wrappedValue == id ? 1 : 0),
                            in: .rect(cornerRadius: Theme.Radius.field))
                .animation(motion.fade, value: focused.wrappedValue == id)
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier)
        }
        .contentShape(Rectangle())
        .onTapGesture { focused.wrappedValue = id }
    }

    /// Con el ojo cerrado y sin editar, el límite escrito se tapa con la máscara.
    private var masked: Bool {
        preferences.privateMode && focused.wrappedValue != id && !text.isEmpty
    }
}
