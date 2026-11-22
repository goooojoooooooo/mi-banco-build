import SwiftUI
import MiBancoCore

/// Ajustes en Titanio: grupos #141416 sobre negro, filas de 60 pt con su ficha de icono, interruptores en blanco y negro.
/// Los saldos se editan en su fila; solo se guarda un campo que el usuario ha tocado (`dirty`).
struct SettingsView: View {
    let model: LedgerModel
    let portfolio: PortfolioModel
    let accountBook: AccountBookModel
    let briefing: BriefingModel
    /// Pedido desde la tarjeta de Inicio ("Editar saldo"): enfoca ese banco y se vacía.
    @Binding var focusRequest: BankID?
    /// Pedido desde Inicio ("Añadir IBAN") o demo: abre «Cuentas y contactos».
    @Binding var openAccountsRequest: Bool
    /// Pedido desde un aviso de consentimiento, el resumen o el reverso de una tarjeta: abre ese banco en «Bancos».
    @Binding var openBankRequest: BankID?
    /// Copia de seguridad e importación: abren la hoja raíz y el selector de archivos único (U55).
    var present: (RootSheet) -> Void = { _ in }
    var requestImport: (ImportKind) -> Void = { _ in }
    var importBackup: () -> Void = {}
    var importTradeRepublic: () -> Void = {}

    @AppStorage("lockEnabled") private var lockEnabled = true
    @AppStorage(MerchantLogos.downloadsKey) private var logoDownloads = true
    @Environment(MerchantLogos.self) private var logos
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.presentationGate) private var gate
    /// Bancos recién guardados: un ✓ que se traza junto al campo.
    @State private var savedFlash: Set<BankID> = []
    @State private var saveCount = 0
    @State private var errorCount = 0
    @State private var texts: [BankID: String] = [:]
    @State private var errors: [BankID: String] = [:]
    /// Solo los campos que el usuario ha editado se guardan; el resto sigue al modelo.
    @State private var dirty: Set<BankID> = []
    @State private var showAccounts = false
    @State private var pushedBank: BankID?
    @State private var showConnectionGuide = false
    @FocusState private var focused: BankID?

    private var showsPrepareConnectionRow: Bool {
        #if DEBUG
        if DemoMode.isActive {
            return !DemoMode.banksConnected
        }
        #endif
        return !BankingCredentials.isReady
    }

    private func bankPrimaryStatus(for bank: BankID, now: Date) -> String {
        if BankSyncStatus.shared.running.contains(bank) {
            return "Conectado · actualizando…"
        }
        return bankStatusLines(
            bank: bank,
            link: model.state.links[bank],
            estimated: model.snapshot.balances[bank]?.estimated,
            canConnect: BankConnector.shared.canConnect(bank),
            now: now,
            calendar: DateText.madridCalendar
        ).primary
    }

    var body: some View {
        NavigationStack {
            // `timeline.date` es el comienzo del minuto (hasta 59 s antes de ahora): «hace 4 min» cuando ya son 5. Se dibuja con
            // la hora de verdad y el `TimelineView` solo marca cuándo volver a dibujar (U80).
            TimelineView(.everyMinute) { _ in
                let now = Date()
                Form {
                    Section {
                        ForEach(BankID.allCases, id: \.self) { bank in
                            Button {
                                pushedBank = bank
                            } label: {
                                HStack(spacing: 14) {
                                    BankLogo(bank: bank, size: 30)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(bank.displayName)
                                            .titan(.option)
                                            .foregroundStyle(Theme.label)
                                        Text(bankPrimaryStatus(for: bank, now: now))
                                            .titan(.meta)
                                            .foregroundStyle(Theme.label3)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.passive)
                                        .accessibilityHidden(true)
                                }
                                .padding(.vertical, 4)
                                .frame(minHeight: 52)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("settings-bank-\(bank.rawValue)")
                            .listRowBackground(Theme.grouped)
                            .listRowSeparatorTint(Theme.separator)
                        }
                        if showsPrepareConnectionRow {
                            Button {
                                showConnectionGuide = true
                            } label: {
                                HStack(spacing: Theme.Space.row) {
                                    OptionLabel(title: "Preparar conexión", detail: "Una vez, unos 15 minutos", systemImage: "key")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.passive)
                                        .accessibilityHidden(true)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("settings-prepare-connection")
                            .listRowBackground(Theme.grouped)
                            .listRowSeparatorTint(Theme.separator)
                        }
                    } header: {
                        SettingsHeader("Bancos")
                    } footer: {
                        SettingsFooter("Mi Banco habla con tu banco a través de Enable Banking, desde este iPhone. Tu clave no sale de aquí.")
                    }

                    Section {
                        ForEach(BankID.allCases, id: \.self) { bank in
                            BalanceRow(bank: bank, info: model.snapshot.balances[bank], link: model.state.links[bank],
                                       now: now, text: binding(bank), error: errors[bank], saved: savedFlash.contains(bank),
                                       focused: $focused, onSubmit: { commit(bank) })
                        }
                    Button {
                        showAccounts = true
                    } label: {
                        HStack(spacing: Theme.Space.row) {
                            OptionLabel(title: "Cuentas y contactos", detail: "IBAN, colchón mínimo y destinatarios", systemImage: "building.columns")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.passive)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings-accounts")
                    .listRowBackground(Theme.grouped)
                    .listRowSeparatorTint(Theme.separator)
                } header: {
                    SettingsHeader("Saldos")
                } footer: {
                    SettingsFooter(model.state.links.isEmpty
                        ? "Toca un saldo para corregirlo. imagin y Trade Republic no envían el saldo en sus avisos, así que lo estimamos."
                        : "Los bancos conectados ponen su saldo solos. Trade Republic y los que no conectes se corrigen aquí.")
                }

                Section {
                    NavigationLink {
                        AlertsGuideView(model: model)
                    } label: {
                        OptionLabel(title: "Avisos al instante", detail: "Guía de 2 minutos y aviso de prueba", systemImage: "bolt")
                    }
                    .listRowBackground(Theme.grouped)
                } header: {
                    SettingsHeader("Avisos")
                }

                Section {
                    Toggle(isOn: $lockEnabled) {
                        OptionLabel(title: "Face ID", detail: "Pedirlo al volver a la app", systemImage: "faceid")
                    }
                    .toggleStyle(TitanToggleStyle())
                    .listRowBackground(Theme.grouped)
                    Toggle(isOn: privacyBinding) {
                        OptionLabel(title: "Modo privado", detail: "Oculta los importes en toda la app", systemImage: "eye.slash")
                    }
                    .toggleStyle(TitanToggleStyle())
                    .listRowBackground(Theme.grouped)
                } header: {
                    SettingsHeader("Privacidad")
                } footer: {
                    SettingsFooter("Al volver a la app te pedirá Face ID o tu código. El ojo de Inicio es el mismo modo privado.")
                }

                InvestmentsSection(portfolio: portfolio, importTradeRepublic: importTradeRepublic)

                AssistantSettingsSection(briefing: briefing)

                BackupSection(model: model, portfolio: portfolio, present: present, importBackup: importBackup)

                Section {
                    Toggle(isOn: $logoDownloads) {
                        OptionLabel(title: "Descargar logos que falten", detail: "Para tiendas que la app no conoce", systemImage: "arrow.down.to.line")
                    }
                    .toggleStyle(TitanToggleStyle())
                    .listRowBackground(Theme.grouped)
                } header: {
                    SettingsHeader("Logos")
                } footer: {
                    VStack(alignment: .leading, spacing: Theme.Space.gutter) {
                        SettingsFooter("Mi Banco busca en internet el logo de las tiendas donde pagas y que no conoce. El servicio de logos ve la web de la tienda, nunca tus importes ni a quién envías dinero.")
                        Text(diagnostics)
                            .titan(.caption)
                            .foregroundStyle(Theme.label3)
                    }
                }
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .listSectionSpacing(.compact)
                .background(Theme.canvas.ignoresSafeArea())
            }
            .navigationTitle("Ajustes")
            .navigationDestination(isPresented: $showAccounts) {
                AccountsView(accountBook: accountBook)
            }
            .navigationDestination(item: $pushedBank) { bank in
                BankLinkView(model: model, portfolio: portfolio, bank: bank, present: present, requestImport: requestImport)
            }
            .navigationDestination(isPresented: $showConnectionGuide) {
                ConnectionGuideView(model: model, requestImport: requestImport)
            }
        }
        .onAppear {
            refreshUntouched()
            applyFocusRequest()
            applyAccountsRequest()
            applyBankRequest()
            #if DEBUG
            if DemoMode.isActive {
                if DemoMode.opensAccounts {
                    showAccounts = true
                } else if DemoMode.opensConnectionGuide {
                    showConnectionGuide = true
                } else if DemoMode.opensStatementImport {
                    pushedBank = .rev
                }
            }
            #endif
        }
        .onChange(of: focusRequest) { _, _ in applyFocusRequest() }
        .onChange(of: openAccountsRequest) { _, _ in applyAccountsRequest() }
        .onChange(of: openBankRequest) { _, _ in applyBankRequest() }
        // Un intent puede cambiar un saldo con Ajustes abierto: los campos sin tocar lo reflejan.
        .onChange(of: model.snapshot.balances) { _, _ in refreshUntouched() }
        .onChange(of: focused) { old, _ in
            if let old { commit(old) }
        }
        // Al salir de la app o bloquear se suelta el foco: guarda lo editado y quita el teclado de encima del bloqueo.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { focused = nil }
        }
        .onChange(of: gate?.isLocked) { _, locked in
            if locked == true { focused = nil }
        }
        .onDisappear { for bank in dirty { commit(bank) } }
        .onChange(of: logoDownloads) { _, on in logos.setDownloadsEnabled(on) }
        .sensoryFeedback(.success, trigger: saveCount)
        .sensoryFeedback(.error, trigger: errorCount)
    }

    /// El interruptor y el ojo de Inicio son el mismo estado, con la misma animación.
    private var privacyBinding: Binding<Bool> {
        Binding(get: { preferences.privateMode }, set: { on in
            withAnimation(reduceMotion ? nil : Theme.Motion.privacy) { preferences.privateMode = on }
        })
    }

    /// "Diagnóstico: datos en grupo compartido · Versión 0.3.0 (3)\nAbrir bancos: Revolut sí · imagin no · Trade Republic sí"
    private var diagnostics: String {
        let place = SharedStore.location == .appGroup ? "grupo compartido" : "carpeta de la app"
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Diagnóstico: datos en \(place) · Versión \(version) (\(build))\n\(BankApps.diagnosticsLine)"
    }

    private func applyAccountsRequest() {
        guard openAccountsRequest else { return }
        openAccountsRequest = false
        showAccounts = true
    }

    private func applyBankRequest() {
        guard let bank = openBankRequest else { return }
        openBankRequest = nil
        pushedBank = bank
    }

    private func applyFocusRequest() {
        guard let bank = focusRequest else { return }
        focusRequest = nil
        if model.state.links[bank] != nil {
            pushedBank = bank
            return
        }
        let generation = gate?.generation
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard scenePhase == .active,
                  gate?.canPresent != false,
                  gate == nil || gate?.generation == generation else { return }
            focused = bank
        }
    }

    /// Editar marca el campo como tocado y borra el error de ese banco.
    private func binding(_ bank: BankID) -> Binding<String> {
        Binding(get: { texts[bank] ?? "" }, set: { new in
            guard new != (texts[bank] ?? "") else { return }
            texts[bank] = new
            errors[bank] = nil
            dirty.insert(bank)
        })
    }

    private func saved(_ bank: BankID) -> Int? { model.snapshot.balances[bank]?.cents }

    private func refresh(_ bank: BankID) {
        texts[bank] = saved(bank).map { formatEUR($0) } ?? ""
        errors[bank] = nil
    }

    /// Los campos sin editar y sin foco muestran el saldo actual del modelo.
    private func refreshUntouched() {
        for bank in BankID.allCases where !dirty.contains(bank) && focused != bank {
            refresh(bank)
        }
    }

    /// Solo guarda un campo editado por el usuario, y solo si cambia el saldo:
    /// un campo sin tocar nunca pisa un pago o un saldo que llegó por un aviso.
    private func commit(_ bank: BankID) {
        guard dirty.contains(bank) else {
            refresh(bank)
            return
        }
        let text = texts[bank] ?? ""
        if text.isEmpty && saved(bank) == nil {
            dirty.remove(bank)
            return
        }
        guard let cents = parseBalanceInput(text) else {
            withAnimation(reduceMotion ? nil : Theme.Motion.quick) { errors[bank] = "Escribe un importe como 340,20" }
            errorCount += 1
            return
        }
        if cents == saved(bank) {
            dirty.remove(bank)
            refresh(bank)
            return
        }
        do {
            try model.setBalance(bank, cents: cents)
            dirty.remove(bank)
            refresh(bank)
            flashSaved(bank)
        } catch {
            withAnimation(reduceMotion ? nil : Theme.Motion.quick) { errors[bank] = "No se pudo guardar. Inténtalo de nuevo." }
            errorCount += 1
        }
    }

    /// ✓ trazado 1,4 s junto al campo.
    private func flashSaved(_ bank: BankID) {
        withAnimation(Theme.Motion.quick) { _ = savedFlash.insert(bank) }
        saveCount += 1
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(.easeOut(duration: 0.3)) { _ = savedFlash.remove(bank) }
        }
    }
}

/// Fila de saldo: logo, nombre, estado según origen real (banco conectado, extracto, aviso o a mano; R25) y el campo
/// (solo lectura si el banco está conectado). Para VoiceOver, el campo editable es "Saldo de Revolut".
private struct BalanceRow: View {
    let bank: BankID
    let info: BalanceInfo?
    var link: BankLinkInfo? = nil
    var now: Date = Date()
    @Binding var text: String
    let error: String?
    let saved: Bool
    var focused: FocusState<BankID?>.Binding
    let onSubmit: () -> Void

    @Environment(AppPreferences.self) private var preferences
    @Environment(\.dynamicTypeSize) private var typeSize

    private var isConnected: Bool { link != nil }

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let hidden = preferences.privateMode
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.small))
            : AnyLayout(HStackLayout(spacing: Theme.Space.row))
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            layout {
                HStack(spacing: 14) {
                    BankLogo(bank: bank, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bank.displayName).titan(.option).foregroundStyle(Theme.label)
                        Text(status).titan(.meta).foregroundStyle(Theme.label3)
                    }
                }
                .accessibilityElement(children: .combine)
                if !stacked { Spacer(minLength: Theme.Space.small) }
                if isConnected {
                    let formatted = info.map { formatEUR($0.cents).replacingOccurrences(of: "-", with: "\u{2212}") } ?? "—"
                    let spoken = info.map { spokenAmount($0.cents, hidden: hidden) } ?? "sin saldo"
                    Text(formatted)
                        .titan(.option)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.label)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 40)
                        .blur(radius: hidden && info != nil ? 9 : 0, opaque: false)
                        .opacity(hidden && info != nil ? 0.75 : 1)
                        .privacySensitive()
                        .accessibilityLabel("Saldo de \(bank.displayName): \(spoken)")
                } else {
                    let isEditing = focused.wrappedValue == bank
                    HStack(spacing: 8) {
                        if saved {
                            DrawnCheck(lineWidth: 2, color: Theme.label)
                                .frame(width: 16, height: 16)
                                .transition(.opacity)
                                .accessibilityLabel("Guardado")
                        }
                        TextField("0,00 €", text: $text)
                            .titan(.option)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.label)
                            .multilineTextAlignment(stacked ? .leading : .trailing)
                            .keyboardType(.numbersAndPunctuation)
                            .submitLabel(.done)
                            .focused(focused, equals: bank)
                            .onSubmit(onSubmit)
                            .padding(.horizontal, 10)
                            .frame(minWidth: 96, maxWidth: stacked ? .infinity : 128, minHeight: 40)
                            .background(Theme.fieldFill.opacity(isEditing ? 1 : 0), in: .rect(cornerRadius: Theme.Radius.field))
                            .animation(Theme.Motion.quick, value: isEditing)
                            .privateField(editing: isEditing)
                            .accessibilityLabel("Saldo de \(bank.displayName)")
                            .accessibilityValue(hidden && !isEditing && !text.isEmpty ? "importe oculto" : text)
                    }
                }
            }
            if !isConnected, let error {
                Text(error)
                    .titan(.meta)
                    .foregroundStyle(Theme.warning)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isConnected { focused.wrappedValue = bank }
        }
        .listRowBackground(Theme.grouped)
        .listRowSeparatorTint(Theme.separator)
    }

    private var status: String {
        if link != nil {
            guard let info else { return "Sin saldo todavía" }
            return connectedBalanceRowStatus(
                estimated: info.estimated,
                origin: info.origin,
                setAt: info.setAt,
                now: now,
                calendar: DateText.madridCalendar
            )
        }
        guard let info else { return "Sin saldo todavía" }
        let calendar = Calendar.current
        let isToday = calendar.isDateInToday(info.setAt)
        let whenExact = isToday ? "de las \(DateText.time(info.setAt))" : "del \(DateText.day(info.setAt))"
        let whenFrom = isToday ? "de hoy" : "del \(DateText.day(info.setAt))"
        let whenCorrected = isToday ? "hoy" : "el \(DateText.day(info.setAt))"
        switch info.origin {
        case .bank:
            return !info.estimated ? "Exacto · del banco \(whenExact)" : "Estimado · desde el banco \(whenFrom)"
        case .statement:
            return !info.estimated ? "Exacto · del extracto \(whenExact)" : "Estimado · desde el extracto \(whenFrom)"
        case .notice:
            return !info.estimated ? "Exacto · del aviso \(whenExact)" : "Estimado · desde el aviso \(whenFrom)"
        case .manual:
            if info.fromBank {
                return !info.estimated ? "Exacto · del aviso \(whenExact)" : "Estimado · desde el aviso \(whenFrom)"
            }
            return "Estimado · corregido \(whenCorrected)"
        }
    }
}

/// Título y subtítulo de una opción, con su ficha de icono de 30 pt.
struct OptionLabel: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.iconGlyph)
                .frame(width: 30, height: 30)
                .background(Theme.iconTile, in: .rect(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).titan(.option).foregroundStyle(Theme.label)
                Text(detail).titan(.meta).foregroundStyle(Theme.label3)
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 52)
    }
}

struct SettingsHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .titan(.header)
            .foregroundStyle(Theme.label3)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
}

struct SettingsFooter: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .titan(.meta)
            .foregroundStyle(Theme.label3)
    }
}

/// La guía de Atajos y el aviso de prueba, en su propia pantalla.
struct AlertsGuideView: View {
    let model: LedgerModel

    var body: some View {
        Form {
            Section {
                AlertsGuideRows(model: model)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Avisos al instante")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}
