import SwiftUI
import MiBancoCore

/// Hoja de la cuenta remunerada de Revolut (Plan 12), en la hoja única de `RootView` (U55): el saldo de hoy y, si se
/// quiere, el interés anual que enseña Revolut. Guardar es poner una base nueva: desde ahí se siguen los traspasos y se
/// estiman los intereses. Con el ojo cerrado los dos campos son `MaskedAmountTextField` (nunca una cifra a la vista).
struct SavingsEditorSheet: View {
    let model: LedgerModel
    let onClose: () -> Void

    private enum Field: Hashable { case balance, rate }

    @Environment(AppPreferences.self) private var preferences
    @Environment(\.motion) private var motion
    @Environment(\.scenePhase) private var scenePhase
    @State private var balanceText = ""
    @State private var rateText = ""
    @State private var error: String?
    @State private var errorTick = 0
    @FocusState private var focused: Field?

    var body: some View {
        let hidden = preferences.privateMode
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Cuenta remunerada")
                    .titan(.sheetTitle)
                    .foregroundStyle(Theme.label)
                    .accessibilityAddTraits(.isHeader)
                Text("\(AppIdentity.displayName) sigue los traspasos entre Revolut y esta cuenta, y estima los intereses.")
                    .titan(.callout)
                    .foregroundStyle(Theme.label2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 12)

            field(title: "Saldo de hoy") {
                MaskedAmountTextField(placeholder: "0,00 €", text: $balanceText, hidden: hidden, editing: focused == .balance)
                    .keyboardType(.numbersAndPunctuation)
                    .submitLabel(.next)
                    .focused($focused, equals: .balance)
                    .onSubmit { focused = .rate }
                    .accessibilityLabel("Saldo de hoy")
                    .accessibilityIdentifier("savings-balance-field")
            }
            field(title: "Interés anual (opcional)") {
                MaskedAmountTextField(placeholder: "2,00 %", text: $rateText, hidden: hidden, editing: focused == .rate,
                                      mask: "•,••\u{00A0}%")
                    .keyboardType(.numbersAndPunctuation)
                    .submitLabel(.done)
                    .focused($focused, equals: .rate)
                    .onSubmit(save)
                    .accessibilityLabel("Interés anual (opcional)")
                    .accessibilityIdentifier("savings-rate-field")
            }

            if let error {
                Text(error)
                    .titan(.meta)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            VStack(spacing: 10) {
                Button(action: save) {
                    Text("Guardar")
                        .titan(.option)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.onTileSelected)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Theme.tileSelected, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("savings-save")

                Button(action: onClose) {
                    Text("Cancelar")
                        .titan(.option)
                        .foregroundStyle(Theme.label)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.raised, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
            }
            Spacer(minLength: 0)
        }
        .animation(motion.fade, value: error)
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.canvas.ignoresSafeArea())
        .overlay {
            if scenePhase != .active {
                Theme.canvas.ignoresSafeArea().accessibilityHidden(true)
            }
        }
        .onAppear(perform: load)
        // Al cerrarse el ojo mientras se edita, soltar el foco en el acto y sin animación (como los demás importes).
        .onChange(of: preferences.privateMode) { _, on in
            guard on, focused != nil else { return }
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { focused = nil }
        }
        .sensoryFeedback(Haptics.error, trigger: errorTick)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func field<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .titan(.meta)
                .foregroundStyle(Theme.label2)
                .accessibilityHidden(true)
            content()
                .titan(.option)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(Theme.fieldFill, in: .rect(cornerRadius: Theme.Radius.field))
        }
    }

    /// El saldo que se ve ahora (base + traspasos + intereses) y el interés guardado: corregir es cambiar lo que haga falta.
    private func load() {
        if let current = model.snapshot.savings {
            balanceText = formatEUR(current.cents)
            rateText = current.annualRateBasisPoints.map { formatAnnualRate($0).replacingOccurrences(of: "\u{00A0}%", with: "") } ?? ""
        }
    }

    private func save() {
        focused = nil
        guard let cents = parseBalanceInput(balanceText.trimmingCharacters(in: .whitespacesAndNewlines)), cents >= 0 else {
            error = "Escribe solo el importe, con coma para los céntimos."
            errorTick += 1
            return
        }
        let rawRate = rateText.trimmingCharacters(in: .whitespacesAndNewlines)
        var rate: Int?
        if !rawRate.isEmpty {
            guard let parsed = parseAnnualRateInput(rawRate) else {
                error = "Escribe solo el interés, con coma para los decimales."
                errorTick += 1
                return
            }
            rate = parsed
        }
        do {
            try model.setSavings(cents: cents, annualRateBasisPoints: rate)
            error = nil
            onClose()
        } catch {
            self.error = "No se pudo guardar. Inténtalo de nuevo."
            errorTick += 1
        }
    }
}
