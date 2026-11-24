import SwiftUI
import MiBancoCore

/// Ajustes › «Cuentas y contactos» (Plan 4b, tarea 8).
/// Guarda IBAN propios, colchones mínimos y contactos únicamente en el Llavero (`AccountBookStore`).
struct AccountsView: View {
    let accountBook: AccountBookModel

    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.presentationGate) private var gate
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var editingIBANBank: BankID?
    @State private var ibanDraft = ""
    @State private var ibanError: String?
    @State private var floorTexts: [BankID: String] = [:]
    @State private var floorDirty: Set<BankID> = []
    @State private var floorErrors: [BankID: String] = [:]
    @State private var floorSaved: Set<BankID> = []
    @State private var addingPayee = false
    @State private var payeeName = ""
    @State private var payeeIBAN = ""
    @State private var payeePhone = ""
    @State private var payeeError: String?
    @State private var payeeListError: String?
    @State private var saveTick = 0
    @State private var errorTick = 0
    @State private var revealedBank: BankID? = nil
    @State private var revealedPayee: UUID? = nil
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case iban(BankID)
        case floor(BankID)
        case payeeName
        case payeeIBAN
        case payeePhone
    }

    var body: some View {
        Form {
            Section {
                ForEach(BankID.allCases, id: \.self) { bank in
                    bankSectionRow(bank)
                }
            } header: {
                SettingsHeader("Tus cuentas")
            } footer: {
                SettingsFooter("Te lo diré en el resumen del día si un cobro deja una cuenta por debajo de su colchón.")
            }

            Section {
                ForEach(accountBook.book.payees) { payee in
                    payeeRow(payee)
                }
                .onDelete(perform: deletePayees)

                if let payeeListError {
                    Text(payeeListError)
                        .titan(.meta)
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .listRowBackground(Theme.grouped)
                        .listRowSeparatorTint(Theme.separator)
                }

                Button {
                    withAnimation(reduceMotion ? nil : Theme.Motion.reveal) {
                        addingPayee.toggle()
                        payeeError = nil
                    }
                } label: {
                    OptionLabel(title: "Añadir contacto", detail: "Con IBAN o móvil para Bizum", systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("accounts-add-payee")
                .listRowBackground(Theme.grouped)
                .listRowSeparatorTint(Theme.separator)

                if addingPayee {
                    addPayeeForm
                        .listRowBackground(Theme.grouped)
                        .listRowSeparatorTint(Theme.separator)
                }
            } header: {
                SettingsHeader("Contactos")
            } footer: {
                SettingsFooter("Para mover dinero rápido sin volver a teclear un IBAN ni un número.")
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .listSectionSpacing(.compact)
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Cuentas y contactos")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadFloorTexts)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                clearSensitiveState()
            }
        }
        .onChange(of: gate?.isLocked) { _, locked in
            if locked == true {
                clearSensitiveState()
            }
        }
        .onChange(of: focusedField) { old, _ in
            if case .floor(let bank) = old { commitFloor(bank) }
        }
        .onDisappear {
            for bank in floorDirty { commitFloor(bank) }
        }
        .sensoryFeedback(Haptics.success, trigger: saveTick)
        .sensoryFeedback(Haptics.error, trigger: errorTick)
    }

    // MARK: - Banco: IBAN + Colchón mínimo

    @ViewBuilder
    private func bankSectionRow(_ bank: BankID) -> some View {
        let iban = accountBook.book.ibans[bank]
        let isRevealed = revealedBank == bank && scenePhase == .active && gate?.isLocked != true
        let stacked = typeSize.isAccessibilitySize

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                BankLogo(bank: bank, size: 28)
                Text(bank.displayName)
                    .titan(.option)
                    .foregroundStyle(Theme.label)
                Spacer(minLength: 0)
                Button(iban == nil ? "Añadir IBAN" : "Editar") {
                    startEditingIBAN(bank)
                }
                .titan(.meta)
                .foregroundStyle(Theme.label2)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .accessibilityIdentifier("accounts-edit-iban-\(bank.rawValue)")
            }

            if let iban {
                HStack(spacing: 10) {
                    Text(isRevealed ? formatIBAN(iban) : maskedIBAN(iban))
                        .titan(.subtitle)
                        .foregroundStyle(isRevealed ? Theme.label : Theme.label2)
                        .monospacedDigit()
                        .lineLimit(isRevealed ? 2 : 1)
                        .privacySensitive()
                    Spacer(minLength: 8)
                    Button {
                        // Con VoiceOver el doble toque alterna; sin VoiceOver la pulsación mantenida se sigue en `HoldRevealButtonStyle` (U27).
                        guard UIAccessibility.isVoiceOverRunning, scenePhase == .active, gate?.isLocked != true else { return }
                        revealedBank = isRevealed ? nil : bank
                    } label: {
                        Text("Ver")
                            .titan(.meta)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.label)
                            .padding(.horizontal, 14)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(Theme.raised, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(HoldRevealButtonStyle { pressed in
                        if pressed {
                            guard scenePhase == .active, gate?.isLocked != true else { return }
                            revealedBank = bank
                        } else if revealedBank == bank {
                            endReveal { if revealedBank == bank { revealedBank = nil } }
                        }
                    })
                    .accessibilityLabel("Mantén pulsado para ver el IBAN de \(bank.displayName)")
                    .accessibilityIdentifier("accounts-reveal-iban-\(bank.rawValue)")
                    .accessibilityAction(named: isRevealed ? "Ocultar IBAN" : "Ver IBAN") {
                        guard scenePhase == .active, gate?.isLocked != true else { return }
                        revealedBank = isRevealed ? nil : bank
                    }
                }
            } else {
                Text("Sin IBAN guardado")
                    .titan(.meta)
                    .foregroundStyle(Theme.label3)
            }

            if editingIBANBank == bank {
                let draftEmpty = ibanDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                VStack(alignment: .leading, spacing: 8) {
                    TextField(iban.map(maskedIBAN) ?? "Pega o escribe el IBAN", text: $ibanDraft)
                        .titan(.body)
                        .foregroundStyle(Theme.label)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .iban(bank))
                        .submitLabel(.done)
                        .onSubmit { if !draftEmpty { commitIBAN(bank) } }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(Theme.fieldFill, in: .rect(cornerRadius: Theme.Radius.field))
                        .privacySensitive()
                        .accessibilityLabel("IBAN de \(bank.displayName)")
                        .accessibilityIdentifier("accounts-iban-field-\(bank.rawValue)")
                    if let ibanError {
                        Text(ibanError)
                            .titan(.meta)
                            .foregroundStyle(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 10) {
                        Button {
                            commitIBAN(bank)
                        } label: {
                            Text("Guardar")
                                .titan(.subtitle)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.onTileSelected)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 44)
                                .background(Theme.tileSelected, in: Capsule())
                                .opacity(draftEmpty ? 0.45 : 1)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.pressable)
                        .disabled(draftEmpty)
                        Button {
                            editingIBANBank = nil
                            ibanDraft = ""
                            ibanError = nil
                            focusedField = nil
                        } label: {
                            Text("Cancelar")
                                .titan(.subtitle)
                                .foregroundStyle(Theme.label2)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Rectangle().fill(Theme.separator).frame(height: 0.5)

            let floorLayout = stacked
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(spacing: 10))
            floorLayout {
                Text("Colchón mínimo")
                    .titan(.subtitle)
                    .foregroundStyle(Theme.label2)
                if !stacked { Spacer(minLength: 8) }
                HStack(spacing: 8) {
                    if floorSaved.contains(bank) {
                        DrawnCheck(lineWidth: 2, color: Theme.label)
                            .frame(width: 16, height: 16)
                            .transition(.opacity)
                            .accessibilityLabel("Guardado")
                    }
                    let textVal = floorTexts[bank] ?? ""
                    let isEditing = focusedField == .floor(bank)
                    TextField("0,00 €", text: floorBinding(bank))
                        .titan(.option)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.label)
                        .multilineTextAlignment(stacked ? .leading : .trailing)
                        .keyboardType(.numbersAndPunctuation)
                        .submitLabel(.done)
                        .focused($focusedField, equals: .floor(bank))
                        .onSubmit { commitFloor(bank) }
                        .padding(.horizontal, 10)
                        .frame(minWidth: 96, maxWidth: stacked ? .infinity : 128, minHeight: 44)
                        .background(Theme.fieldFill.opacity(isEditing ? 1 : 0), in: .rect(cornerRadius: Theme.Radius.field))
                        .privateField(editing: isEditing)
                        .accessibilityLabel("Colchón mínimo de \(bank.displayName)")
                        .accessibilityValue(preferences.privateMode && !isEditing && !textVal.isEmpty ? "importe oculto" : textVal)
                        .accessibilityIdentifier("accounts-floor-field-\(bank.rawValue)")
                }
            }
            if let err = floorErrors[bank] {
                Text(err)
                    .titan(.meta)
                    .foregroundStyle(Theme.warning)
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(Theme.grouped)
        .listRowSeparatorTint(Theme.separator)
    }

    // MARK: - Contactos

    private func payeeRow(_ payee: Payee) -> some View {
        let isRevealed = revealedPayee == payee.id && scenePhase == .active && gate?.isLocked != true
        return HStack(spacing: 12) {
            ContactMonogramTile(name: payee.name, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(payee.name)
                    .titan(.option)
                    .foregroundStyle(Theme.label)
                if let iban = payee.iban {
                    Text(isRevealed ? formatIBAN(iban) : maskedIBAN(iban))
                        .titan(.meta)
                        .foregroundStyle(isRevealed ? Theme.label : Theme.label3)
                        .privacySensitive()
                }
                if let phone = payee.phone {
                    Text(isRevealed ? phone : maskedPhone(phone))
                        .titan(.meta)
                        .foregroundStyle(isRevealed ? Theme.label : Theme.label3)
                        .privacySensitive()
                        .accessibilityLabel(isRevealed ? phone : spokenMaskedPhone(phone))
                }
            }
            Spacer(minLength: 8)
            if payee.iban != nil || payee.phone != nil {
                Button {
                    guard UIAccessibility.isVoiceOverRunning, scenePhase == .active, gate?.isLocked != true else { return }
                    revealedPayee = isRevealed ? nil : payee.id
                } label: {
                    Text("Ver")
                        .titan(.meta)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.label)
                        .padding(.horizontal, 14)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(Theme.raised, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(HoldRevealButtonStyle { pressed in
                    if pressed {
                        guard scenePhase == .active, gate?.isLocked != true else { return }
                        revealedPayee = payee.id
                    } else if revealedPayee == payee.id {
                        endReveal { if revealedPayee == payee.id { revealedPayee = nil } }
                    }
                })
                .accessibilityLabel("Mantén pulsado para ver los datos de \(payee.name)")
                .accessibilityAction(named: isRevealed ? "Ocultar datos" : "Ver datos") {
                    guard scenePhase == .active, gate?.isLocked != true else { return }
                    revealedPayee = isRevealed ? nil : payee.id
                }
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 52)
        .listRowBackground(Theme.grouped)
        .listRowSeparatorTint(Theme.separator)
    }

    private var addPayeeForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Nombre", text: $payeeName)
                .titan(.body)
                .foregroundStyle(Theme.label)
                .submitLabel(.done)
                .focused($focusedField, equals: .payeeName)
                .onSubmit { focusedField = nil }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Theme.fieldFill, in: .rect(cornerRadius: Theme.Radius.field))
                .accessibilityIdentifier("payeeNameField")

            TextField("IBAN (opcional)", text: $payeeIBAN)
                .titan(.body)
                .foregroundStyle(Theme.label)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focusedField, equals: .payeeIBAN)
                .onSubmit { focusedField = nil }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Theme.fieldFill, in: .rect(cornerRadius: Theme.Radius.field))
                .privacySensitive()
                .accessibilityIdentifier("payeeIBANField")

            TextField("Móvil español (opcional)", text: $payeePhone)
                .titan(.body)
                .foregroundStyle(Theme.label)
                .keyboardType(.phonePad)
                .submitLabel(.done)
                .focused($focusedField, equals: .payeePhone)
                .onSubmit { focusedField = nil }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Theme.fieldFill, in: .rect(cornerRadius: Theme.Radius.field))
                .privacySensitive()
                .accessibilityIdentifier("payeePhoneField")

            if let payeeError {
                Text(payeeError)
                    .titan(.meta)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                commitPayee()
            } label: {
                Text("Guardar contacto")
                    .titan(.option)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.onTileSelected)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Theme.tileSelected, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.pressable)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Acciones

    private func loadFloorTexts() {
        for bank in BankID.allCases {
            if let cents = accountBook.book.floors[bank], cents > 0 {
                floorTexts[bank] = formatEUR(cents)
            } else {
                floorTexts[bank] = ""
            }
        }
    }

    private func startEditingIBAN(_ bank: BankID) {
        ibanDraft = ""
        ibanError = nil
        withAnimation(reduceMotion ? nil : Theme.Motion.reveal) {
            editingIBANBank = bank
        }
        focusedField = .iban(bank)
    }

    private func commitIBAN(_ bank: BankID) {
        focusedField = nil
        let trimmed = ibanDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard isValidIBAN(trimmed) else {
            ibanError = "Ese IBAN no es correcto: revisa los números."
            errorTick += 1
            return
        }
        do {
            try accountBook.setIBAN(trimmed, for: bank)
            editingIBANBank = nil
            ibanDraft = ""
            ibanError = nil
            saveTick += 1
        } catch {
            ibanError = "No se pudo guardar. Inténtalo de nuevo."
            errorTick += 1
        }
    }

    private func floorBinding(_ bank: BankID) -> Binding<String> {
        Binding(
            get: { floorTexts[bank] ?? "" },
            set: { new in
                guard new != (floorTexts[bank] ?? "") else { return }
                floorTexts[bank] = new
                floorErrors[bank] = nil
                floorDirty.insert(bank)
            }
        )
    }

    private func commitFloor(_ bank: BankID) {
        guard floorDirty.contains(bank) else { return }
        let raw = (floorTexts[bank] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty {
            do {
                try accountBook.setFloor(nil, for: bank)
                floorDirty.remove(bank)
                floorErrors[bank] = nil
                flashFloorSaved(bank)
            } catch {
                floorErrors[bank] = "No se pudo guardar. Inténtalo de nuevo."
                errorTick += 1
            }
            return
        }
        guard let cents = parseBalanceInput(raw), cents >= 0 else {
            floorErrors[bank] = "Escribe un importe como 100,00"
            errorTick += 1
            return
        }
        do {
            try accountBook.setFloor(cents > 0 ? cents : nil, for: bank)
            floorDirty.remove(bank)
            floorTexts[bank] = cents > 0 ? formatEUR(cents) : ""
            floorErrors[bank] = nil
            flashFloorSaved(bank)
        } catch {
            floorErrors[bank] = "No se pudo guardar. Inténtalo de nuevo."
            errorTick += 1
        }
    }

    private func flashFloorSaved(_ bank: BankID) {
        saveTick += 1
        withAnimation(reduceMotion ? nil : Theme.Motion.quick) { _ = floorSaved.insert(bank) }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(.easeOut(duration: 0.3)) { _ = floorSaved.remove(bank) }
        }
    }

    private func commitPayee() {
        focusedField = nil
        let trimmedName = payeeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            payeeError = "Escribe el nombre del contacto."
            errorTick += 1
            return
        }
        let rawIBAN = payeeIBAN.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawPhone = payeePhone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawIBAN.isEmpty || !rawPhone.isEmpty else {
            payeeError = "Escribe un IBAN o un número de móvil."
            errorTick += 1
            return
        }
        var cleanIBAN: String?
        if !rawIBAN.isEmpty {
            guard isValidIBAN(rawIBAN) else {
                payeeError = "Ese IBAN no es correcto: revisa los números."
                errorTick += 1
                return
            }
            cleanIBAN = normalizeIBAN(rawIBAN)
        }
        var cleanPhone: String?
        if !rawPhone.isEmpty {
            guard let normalized = normalizeSpanishMobile(rawPhone) else {
                payeeError = "Escribe un móvil español de 9 cifras."
                errorTick += 1
                return
            }
            cleanPhone = normalized
        }
        do {
            try accountBook.addPayee(Payee(name: trimmedName, iban: cleanIBAN, phone: cleanPhone))
            payeeName = ""
            payeeIBAN = ""
            payeePhone = ""
            payeeError = nil
            payeeListError = nil
            addingPayee = false
            saveTick += 1
        } catch {
            payeeError = "No se pudo guardar. Inténtalo de nuevo."
            errorTick += 1
        }
    }

    private func clearSensitiveState() {
        revealedBank = nil
        revealedPayee = nil
        focusedField = nil
        editingIBANBank = nil
        ibanDraft = ""
        ibanError = nil
        addingPayee = false
        payeeName = ""
        payeeIBAN = ""
        payeePhone = ""
        payeeError = nil
        payeeListError = nil
    }

    private func deletePayees(at offsets: IndexSet) {
        let targets = offsets.compactMap { idx in
            idx < accountBook.book.payees.count ? accountBook.book.payees[idx].id : nil
        }
        for id in targets {
            do {
                try accountBook.deletePayee(id: id)
                payeeListError = nil
            } catch {
                payeeListError = "No se pudo guardar. Inténtalo de nuevo."
                errorTick += 1
                return
            }
        }
    }
}

/// Enmascara un teléfono en listas («+34 ••• ••• 678», U29).
func maskedPhone(_ phone: String) -> String {
    let digits = phone.filter(\.isNumber)
    let tail = String(digits.suffix(3))
    guard !tail.isEmpty else { return "•••" }
    let hasPrefix = phone.trimmingCharacters(in: .whitespaces).hasPrefix("+34") || (digits.count == 11 && digits.hasPrefix("34"))
    return hasPrefix ? "+34 ••• ••• \(tail)" : "••• ••• \(tail)"
}

/// Lectura VoiceOver de un teléfono enmascarado («teléfono acabado en 678», U29).
func spokenMaskedPhone(_ phone: String) -> String {
    let tail = String(phone.filter(\.isNumber).suffix(3))
    return tail.isEmpty ? "teléfono oculto" : "teléfono acabado en \(tail)"
}

/// Estilo de botón para «Ver»: revela el IBAN solo mientras el dedo sigue pulsando, sin robar el desplazamiento vertical
/// del `Form`, y oculta al soltar o al cancelarse el gesto.
/// Al soltar «Ver» se tapa al instante. Solo en la demo de pruebas (`-MiBancoDemoRevealLinger <s>`) se tapa unos segundos
/// después, para que una prueba de interfaz pueda leer lo que reveló la pulsación (U74). El bloqueo y salir de primer plano
/// lo siguen tapando al momento (`isRevealed` mira `scenePhase` y el bloqueo).
@MainActor
private func endReveal(_ hide: @escaping @MainActor () -> Void) {
    #if DEBUG
    if let seconds = DemoMode.revealLingerSeconds {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            hide()
        }
        return
    }
    #endif
    hide()
}

private struct HoldRevealButtonStyle: ButtonStyle {
    let onPressedChange: (Bool) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
            .animation(configuration.isPressed ? Theme.Motion.pressIn : Theme.Motion.pressOut, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                onPressedChange(pressed)
            }
    }
}
