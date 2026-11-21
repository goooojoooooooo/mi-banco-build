import SwiftUI
import MiBancoCore

/// Hoja de «Mover dinero» (Plan 4b, tarea 8): solo lectura, nunca inicia pagos.
/// Tres pasos dentro de su propia `NavigationStack`: 1) «¿A dónde?», 2) importe + «Desde», 3) listo (IBAN o teléfono
/// copiado durante 3 min + guía o botón para abrir el banco). Vive en `RootSheet` y se cierra al bloquear o salir.
struct MoveMoneySheet: View {
    let model: LedgerModel
    let accountBook: AccountBookModel
    let request: MoveRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(AppPreferences.self) private var preferences

    private enum Step: Equatable {
        case target
        case amount
        case ready(from: BankID, target: MoveTarget, amountCents: Int, kind: PasteKind)
    }

    @State private var step: Step = .target
    @State private var chosenTarget: MoveTarget?
    @State private var chosenFrom: BankID?
    @State private var amount = KeypadAmount()
    /// Destino propio elegido al que aún le falta el IBAN (se pide en línea antes de seguir).
    @State private var missingIBANBank: BankID?
    @State private var inlineIBAN = ""
    @State private var inlineIBANError: String?
    /// Formulario en línea para añadir un contacto desde el paso 1.
    @State private var addingPayee = false
    @State private var newPayeeName = ""
    @State private var newPayeeIBAN = ""
    @State private var newPayeePhone = ""
    @State private var newPayeeError: String?
    @State private var successTick = 0
    @State private var errorTick = 0
    @State private var slideAttempt = 0
    @State private var initialized = false
    @FocusState private var fieldFocused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize: CGFloat = 46

    private var demoKeepsVisible: Bool {
        #if DEBUG
        return DemoMode.isActive && DemoMode.demoMoveStep != nil
        #else
        return false
        #endif
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .target:
                    targetStep
                case .amount:
                    amountStep
                case let .ready(from, target, cents, kind):
                    readyStep(from: from, target: target, amountCents: cents, kind: kind)
                }
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("Mover dinero")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if case .amount = step, request.target == nil {
                        Button("Atrás") {
                            withAnimation(reduceMotion ? nil : Theme.Motion.quick) {
                                step = .target
                            }
                        }
                        .foregroundStyle(Theme.label2)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                        .foregroundStyle(Theme.label)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .overlay {
            if scenePhase != .active && !demoKeepsVisible {
                Theme.canvas
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { fieldFocused = false }
        }
        .onAppear(perform: configureInitialState)
        .sensoryFeedback(Haptics.success, trigger: successTick)
        .sensoryFeedback(Haptics.error, trigger: errorTick)
    }

    // MARK: - Paso 1: ¿A dónde?

    private var targetStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("¿A dónde?")
                    .titan(.homeTitle)
                    .foregroundStyle(Theme.label)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 8)

                VStack(spacing: 0) {
                    ForEach(Array(BankID.allCases.enumerated()), id: \.element) { index, bank in
                        let iban = accountBook.book.ibans[bank]
                        Button {
                            selectOwnBank(bank)
                        } label: {
                            HStack(spacing: 14) {
                                BankLogo(bank: bank, size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bank.displayName)
                                        .titan(.option)
                                        .foregroundStyle(Theme.label)
                                    Text(iban.map(maskedIBAN) ?? "Falta el IBAN")
                                        .titan(.meta)
                                        .foregroundStyle(iban == nil ? Theme.warning : Theme.label3)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.passive)
                                    .accessibilityHidden(true)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 60)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle(background: Theme.raised))
                        .accessibilityIdentifier("move-target-\(bank.rawValue)")
                        .overlay(alignment: .top) {
                            if index > 0 {
                                Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 62)
                            }
                        }
                    }
                }
                .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))

                if let bank = missingIBANBank {
                    inlineMissingIBANCard(for: bank)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Contactos")
                        .titan(.header)
                        .foregroundStyle(Theme.label3)
                        .padding(.horizontal, 4)
                        .accessibilityAddTraits(.isHeader)

                    VStack(spacing: 0) {
                        ForEach(Array(accountBook.book.payees.enumerated()), id: \.element.id) { index, payee in
                            Button {
                                selectPayee(payee)
                            } label: {
                                HStack(spacing: 14) {
                                    PositionMonogramTile(name: payee.name, size: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(payee.name)
                                            .titan(.option)
                                            .foregroundStyle(Theme.label)
                                        Text(payeeSubtitle(payee))
                                            .titan(.meta)
                                            .foregroundStyle(Theme.label3)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.passive)
                                        .accessibilityHidden(true)
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 60)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(RowPressStyle(background: Theme.raised))
                            .overlay(alignment: .top) {
                                if index > 0 {
                                    Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 62)
                                }
                            }
                        }

                        Button {
                            withAnimation(reduceMotion ? nil : Theme.Motion.reveal) {
                                addingPayee.toggle()
                                newPayeeError = nil
                            }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "plus")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.iconGlyph)
                                    .frame(width: 32, height: 32)
                                    .background(Theme.iconTile, in: .rect(cornerRadius: 8, style: .continuous))
                                    .accessibilityHidden(true)
                                Text("Añadir contacto")
                                    .titan(.option)
                                    .foregroundStyle(Theme.label)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle(background: Theme.raised))
                        .overlay(alignment: .top) {
                            if !accountBook.book.payees.isEmpty {
                                Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 62)
                            }
                        }
                    }
                    .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
                }

                if addingPayee {
                    inlineAddPayeeCard
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, 32)
            .animation(reduceMotion ? nil : Theme.Motion.reveal, value: missingIBANBank)
            .animation(reduceMotion ? nil : Theme.Motion.reveal, value: addingPayee)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private func inlineMissingIBANCard(for bank: BankID) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("IBAN de \(bank.displayName)")
                .titan(.option)
                .foregroundStyle(Theme.label)
            TextField("ES00 0000 0000 0000 0000 0000", text: $inlineIBAN)
                .titan(.body)
                .foregroundStyle(Theme.label)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($fieldFocused)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Theme.fieldFill, in: .rect(cornerRadius: Theme.Radius.field))
                .accessibilityLabel("IBAN de \(bank.displayName)")
            Text("Se guarda solo en este iPhone.")
                .titan(.meta)
                .foregroundStyle(Theme.label3)
            if let inlineIBANError {
                Text(inlineIBANError)
                    .titan(.meta)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                saveInlineIBAN(for: bank)
            } label: {
                Text("Guardar y seguir")
                    .titan(.option)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.onTileSelected)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Theme.tileSelected, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.pressable)
        }
        .padding(16)
        .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
    }

    private var inlineAddPayeeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Nombre", text: $newPayeeName)
                .titan(.body)
                .foregroundStyle(Theme.label)
                .focused($fieldFocused)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Theme.fieldFill, in: .rect(cornerRadius: Theme.Radius.field))
            TextField("IBAN (opcional)", text: $newPayeeIBAN)
                .titan(.body)
                .foregroundStyle(Theme.label)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($fieldFocused)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Theme.fieldFill, in: .rect(cornerRadius: Theme.Radius.field))
            TextField("Móvil para Bizum (opcional)", text: $newPayeePhone)
                .titan(.body)
                .foregroundStyle(Theme.label)
                .keyboardType(.phonePad)
                .focused($fieldFocused)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Theme.fieldFill, in: .rect(cornerRadius: Theme.Radius.field))
            Text("Se guarda solo en este iPhone.")
                .titan(.meta)
                .foregroundStyle(Theme.label3)
            if let newPayeeError {
                Text(newPayeeError)
                    .titan(.meta)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                saveInlinePayee()
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
        .padding(16)
        .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
    }

    // MARK: - Paso 2: Importe y Desde

    private var amountStep: some View {
        let hidden = preferences.privateMode
        let options = sourceOptions(for: amount.cents)
        let activeFrom = resolvedFrom(among: options)
        let canConfirm = amount.cents > 0 && activeFrom != nil && chosenTarget != nil

        return ScrollView {
            VStack(spacing: 18) {
                if let target = chosenTarget {
                    Text("Para \(accountBook.displayName(for: target))")
                        .titan(.subtitle)
                        .foregroundStyle(Theme.label2)
                        .padding(.top, 4)
                }

                Text(amount.formattedEUR)
                    .font(.system(size: amountSize, weight: .semibold))
                    .tracking(-amountSize * 0.03)
                    .monospacedDigit()
                    .foregroundStyle(amount.cents > 0 ? Theme.label : Theme.label3)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(maxWidth: .infinity)
                    .privateAmount(radius: 14)
                    .accessibilityLabel(spokenAmount(amount.cents, hidden: hidden))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Desde")
                        .titan(.header)
                        .foregroundStyle(Theme.label3)
                        .padding(.horizontal, 4)
                        .accessibilityAddTraits(.isHeader)

                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(options, id: \.bank) { option in
                                sourceChip(option: option, selected: activeFrom == option.bank, hidden: hidden)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }

                AmountKeypad(amount: $amount)

                if canConfirm, let from = activeFrom, let target = chosenTarget {
                    SlideToConfirm(
                        title: "Desliza para preparar",
                        systemImage: "doc.on.doc",
                        tint: Theme.label
                    ) {
                        prepareTransfer(from: from, target: target, cents: amount.cents)
                    }
                    .id(slideAttempt)
                    .accessibilityIdentifier("move-slide")
                    .padding(.top, 4)
                } else {
                    Text("Escribe un importe para preparar el traspaso.")
                        .titan(.meta)
                        .foregroundStyle(Theme.label3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
    }

    private func sourceChip(option: PayOption, selected: Bool, hidden: Bool) -> some View {
        let prefix = option.isEstimated ? "≈\u{00A0}" : ""
        let detail = option.fits
            ? "te quedarían \(prefix)\(formatEUR(option.leftAfterCents))"
            : "no llega"
        let spokenDetail = option.fits
            ? (hidden ? "importe oculto" : "te quedarían \(spokenAmount(option.leftAfterCents, hidden: false))")
            : "no llega"

        return Button {
            withAnimation(reduceMotion ? nil : Theme.Motion.quick) {
                chosenFrom = option.bank
            }
        } label: {
            HStack(spacing: 10) {
                BankLogo(bank: option.bank, size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.bank.displayName)
                        .titan(.subtitle)
                        .fontWeight(.semibold)
                        .foregroundStyle(selected ? Theme.onTileSelected : Theme.label)
                    Group {
                        if option.fits {
                            Text(detail)
                                .foregroundStyle(selected ? Color.black.opacity(0.7) : Theme.label2)
                                .privateAmount()
                        } else {
                            Text(detail)
                                .foregroundStyle(selected ? Color.black.opacity(0.75) : Theme.warning)
                        }
                    }
                    .titan(.caption)
                    .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 52)
            .background(
                selected ? Theme.tileSelected : Theme.grouped,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(option.bank.displayName), \(spokenDetail)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
    }

    // MARK: - Paso 3: Listo

    private func readyStep(from: BankID, target: MoveTarget, amountCents: Int, kind: PasteKind) -> some View {
        let targetName = accountBook.displayName(for: target)
        let headline = kind == .iban ? "IBAN de \(targetName) copiado" : "Teléfono copiado"
        let rawHint = bankTransferHint(from: from, kind: kind, amountCents: amountCents)
        let shownHint = preferences.privateMode ? maskingAmounts(rawHint) : rawHint
        let spokenHint = preferences.privateMode ? maskingAmounts(rawHint, with: "importe oculto") : rawHint
        let canOpenBank = BankApps.canOpen(from)

        return ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Theme.income.opacity(0.16))
                        .frame(width: 72, height: 72)
                    DrawnCheck(lineWidth: 3, color: Theme.income)
                        .frame(width: 30, height: 30)
                }
                .padding(.top, 28)

                VStack(spacing: 8) {
                    Text(headline)
                        .titan(.homeTitle)
                        .foregroundStyle(Theme.label)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text("Se borra del portapapeles en 3 minutos.")
                        .titan(.subtitle)
                        .foregroundStyle(Theme.label2)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(shownHint)
                        .titan(.body)
                        .foregroundStyle(Theme.label)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(spokenHint)
                    if !canOpenBank {
                        Text(kind == .iban
                             ? "Abre \(from.displayName) y pega el IBAN."
                             : "Abre \(from.displayName) y pega el número.")
                            .titan(.subtitle)
                            .foregroundStyle(Theme.label2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))

                if canOpenBank, let url = BankApps.url(for: from) {
                    Button {
                        openURL(url)
                    } label: {
                        Text("Abrir \(from.displayName)")
                            .titan(.option)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.onTileSelected)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Theme.tileSelected, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                }

                Button {
                    dismiss()
                } label: {
                    Text("Listo")
                        .titan(.option)
                        .fontWeight(.medium)
                        .foregroundStyle(canOpenBank ? Theme.label : Theme.onTileSelected)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(canOpenBank ? Theme.raised : Theme.tileSelected, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Lógica

    private func configureInitialState() {
        guard !initialized else { return }
        initialized = true
        chosenFrom = request.from
        chosenTarget = request.target
        if let cents = request.amountCents, cents > 0 {
            amount = KeypadAmount(cents: cents)
        }
        #if DEBUG
        if let demoStep = request.demoStep {
            switch demoStep {
            case 2:
                chosenTarget = request.target ?? .own(.rev)
                chosenFrom = request.from ?? .ima
                amount = KeypadAmount(cents: request.amountCents ?? 20_000)
                step = .amount
                return
            case 3:
                let target = request.target ?? .own(.rev)
                let from = request.from ?? .ima
                let cents = request.amountCents ?? 20_000
                chosenTarget = target
                chosenFrom = from
                amount = KeypadAmount(cents: cents)
                step = .ready(from: from, target: target, amountCents: cents, kind: .iban)
                return
            default:
                step = .target
                return
            }
        }
        #endif
        if let target = request.target {
            switch target {
            case .own(let bank):
                if accountBook.book.ibans[bank] != nil {
                    if chosenFrom == bank { chosenFrom = nil }
                    step = .amount
                } else {
                    missingIBANBank = bank
                    step = .target
                }
            case .payee(let id):
                if let payee = accountBook.payee(id: id), payee.iban != nil || payee.phone != nil {
                    step = .amount
                } else {
                    step = .target
                }
            }
        }
    }

    private func selectOwnBank(_ bank: BankID) {
        if accountBook.book.ibans[bank] == nil {
            inlineIBAN = ""
            inlineIBANError = nil
            withAnimation(reduceMotion ? nil : Theme.Motion.reveal) {
                missingIBANBank = bank
            }
            return
        }
        missingIBANBank = nil
        chosenTarget = .own(bank)
        if chosenFrom == bank { chosenFrom = nil }
        withAnimation(reduceMotion ? nil : Theme.Motion.quick) {
            step = .amount
        }
    }

    private func saveInlineIBAN(for bank: BankID) {
        fieldFocused = false
        guard isValidIBAN(inlineIBAN) else {
            inlineIBANError = "Ese IBAN no es correcto: revisa los números."
            errorTick += 1
            return
        }
        do {
            try accountBook.setIBAN(inlineIBAN, for: bank)
            inlineIBANError = nil
            missingIBANBank = nil
            chosenTarget = .own(bank)
            if chosenFrom == bank { chosenFrom = nil }
            withAnimation(reduceMotion ? nil : Theme.Motion.quick) {
                step = .amount
            }
        } catch {
            inlineIBANError = "No se pudo guardar en el Llavero. Inténtalo de nuevo."
            errorTick += 1
        }
    }

    private func selectPayee(_ payee: Payee) {
        guard payee.iban != nil || payee.phone != nil else { return }
        chosenTarget = .payee(payee.id)
        withAnimation(reduceMotion ? nil : Theme.Motion.quick) {
            step = .amount
        }
    }

    private func saveInlinePayee() {
        fieldFocused = false
        let trimmedName = newPayeeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            newPayeeError = "Escribe el nombre del contacto."
            errorTick += 1
            return
        }
        let rawIBAN = newPayeeIBAN.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawPhone = newPayeePhone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawIBAN.isEmpty || !rawPhone.isEmpty else {
            newPayeeError = "Escribe un IBAN o un número de móvil."
            errorTick += 1
            return
        }
        var cleanIBAN: String?
        if !rawIBAN.isEmpty {
            guard isValidIBAN(rawIBAN) else {
                newPayeeError = "Ese IBAN no es correcto: revisa los números."
                errorTick += 1
                return
            }
            cleanIBAN = normalizeIBAN(rawIBAN)
        }
        var cleanPhone: String?
        if !rawPhone.isEmpty {
            guard let normalized = normalizeSpanishMobile(rawPhone) else {
                newPayeeError = "Escribe un móvil español de 9 cifras."
                errorTick += 1
                return
            }
            cleanPhone = normalized
        }
        let payee = Payee(name: trimmedName, iban: cleanIBAN, phone: cleanPhone)
        do {
            try accountBook.addPayee(payee)
            newPayeeName = ""
            newPayeeIBAN = ""
            newPayeePhone = ""
            newPayeeError = nil
            addingPayee = false
            chosenTarget = .payee(payee.id)
            withAnimation(reduceMotion ? nil : Theme.Motion.quick) {
                step = .amount
            }
        } catch {
            newPayeeError = "No se pudo guardar el contacto. Inténtalo de nuevo."
            errorTick += 1
        }
    }

    private func payeeSubtitle(_ payee: Payee) -> String {
        if let iban = payee.iban { return maskedIBAN(iban) }
        if let phone = payee.phone { return phone }
        return "Sin datos"
    }

    private func sourceOptions(for cents: Int) -> [PayOption] {
        let now = Date()
        let cal = DateText.madridCalendar
        let snapshot = model.snapshot
        var balances: [BankID: Int] = [:]
        var estimated = Set<BankID>()
        for bank in BankID.allCases {
            if let info = snapshot.balances[bank] {
                balances[bank] = info.cents
                if info.estimated { estimated.insert(bank) }
            }
        }
        var included = Set(BankID.allCases)
        if case .own(let dest) = chosenTarget {
            included.remove(dest)
        }
        let upcoming = upcomingCalendar(state: model.state, book: accountBook.book, now: now, calendar: cal)
            .prefix(7)
            .flatMap(\.charges)
        let ranked = whereToPay(
            amountCents: cents,
            balances: balances,
            floors: accountBook.book.floors,
            upcoming: Array(upcoming),
            included: included,
            estimated: estimated
        )
        if !ranked.isEmpty { return ranked }
        return BankID.allCases
            .filter { included.contains($0) }
            .map { PayOption(bank: $0, leftAfterCents: -cents, fits: false, isEstimated: true) }
    }

    private func resolvedFrom(among options: [PayOption]) -> BankID? {
        if let chosenFrom, options.contains(where: { $0.bank == chosenFrom }) {
            return chosenFrom
        }
        return options.first(where: \.fits)?.bank ?? options.first?.bank
    }

    private func prepareTransfer(from: BankID, target: MoveTarget, cents: Int) {
        let clipboardValue: String?
        let kind: PasteKind
        switch target {
        case .own(let bank):
            clipboardValue = accountBook.book.ibans[bank].map(normalizeIBAN)
            kind = .iban
        case .payee(let id):
            if let iban = accountBook.payee(id: id)?.iban {
                clipboardValue = normalizeIBAN(iban)
                kind = .iban
            } else if let phone = accountBook.payee(id: id)?.phone {
                clipboardValue = phone
                kind = .phone
            } else {
                clipboardValue = nil
                kind = .iban
            }
        }
        guard let value = clipboardValue else {
            slideAttempt += 1
            errorTick += 1
            return
        }
        Pasteboard.copy(value)
        model.addPendingMove(PendingMove(from: from, target: target, amountCents: cents, createdAt: Date()))
        successTick += 1
        withAnimation(reduceMotion ? nil : Theme.Motion.morph) {
            step = .ready(from: from, target: target, amountCents: cents, kind: kind)
        }
    }
}
