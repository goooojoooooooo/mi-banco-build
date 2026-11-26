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
    /// El movimiento tal como lo ve el kit: la fila «Animaciones» dice el nivel que de verdad está en uso.
    @Environment(\.motion) private var motion
    /// El cambio de pestaña que anuncia RootView (cuando lo haga): repite la entrada de las filas de Bancos.
    @Environment(\.tabEntrance) private var tabEntrance
    /// Al entrar en Ajustes, las filas de Bancos llegan una tras otra.
    @State private var entrance = Entrance()
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
    #if DEBUG
    /// Demo (`-MiBancoDemoAlertsGuide`): abre la guía de avisos nada más aparecer Ajustes.
    @State private var demoOpensGuide = false
    #endif

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
                let now = AppClock.now
                Form {
                    // Avisos va primero: los avisos al instante son lo primero que pidió el dueño, y la guía se encuentra
                    // sin deslizar.
                    Section {
                        NavigationLink {
                            AlertsGuideView(model: model)
                        } label: {
                            OptionLabel(title: "Avisos al instante", detail: "Guía de 2 minutos y aviso de prueba", systemImage: "bolt")
                        }
                        .accessibilityIdentifier("settings-alerts-guide")
                        .listRowBackground(Theme.grouped)
                    } header: {
                        SettingsHeader("Avisos")
                    }

                    Section {
                        ForEach(Array(BankID.allCases.enumerated()), id: \.element) { index, bank in
                            Button {
                                pushedBank = bank
                            } label: {
                                HStack(spacing: 14) {
                                    BankLogo(bank: bank, size: 30)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(bank.displayName)
                                            .titan(.option)
                                            .foregroundStyle(Theme.label)
                                        // El estado cambia con un fundido cruzado (conectando, actualizando, al día).
                                        Text(bankPrimaryStatus(for: bank, now: now))
                                            .titan(.meta)
                                            .foregroundStyle(Theme.label3)
                                            .contentTransition(.opacity)
                                            .animation(motion.calmAnimation(.row), value: bankPrimaryStatus(for: bank, now: now))
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
                                .motionEntrance(index)
                                .environment(\.entrance, entrance)
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
                                .motionEntrance(BankID.allCases.count)
                                .environment(\.entrance, entrance)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("settings-prepare-connection")
                            .listRowBackground(Theme.grouped)
                            .listRowSeparatorTint(Theme.separator)
                        }
                    } header: {
                        SettingsHeader("Bancos")
                    } footer: {
                        SettingsFooter("\(AppIdentity.displayName) habla con tu banco a través de Enable Banking, desde este iPhone. Tu clave no sale de aquí.")
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
                    Toggle(isOn: $lockEnabled) {
                        OptionLabel(title: "Face ID", detail: "Pedirlo al volver a la app", systemImage: "faceid")
                    }
                    .toggleStyle(TitanToggleStyle())
                    .listRowBackground(Theme.grouped)
                    Toggle(isOn: privacyBinding) {
                        OptionLabel(title: "Modo privado", detail: "Oculta los importes en toda la app", systemImage: "eye.slash")
                    }
                    .toggleStyle(TitanToggleStyle())
                    .accessibilityIdentifier("settings-private-mode")
                    .listRowBackground(Theme.grouped)
                } header: {
                    SettingsHeader("Privacidad")
                } footer: {
                    SettingsFooter("Al volver a la app te pedirá Face ID o tu código. El ojo de Inicio es el mismo modo privado.")
                }

                // Intensidad del movimiento: el segmentado del kit, a todo el ancho de su grupo. Cambia al instante en
                // toda la app (`MotionEnvironment` lee esta preferencia) y se recuerda.
                Section {
                    TitanSegmented(selection: motionLevelBinding, options: Self.motionLevels)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Animaciones")
                        .accessibilityValue(Self.motionTitle(motion.level))
                        .accessibilityIdentifier("settings-motion-level")
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                        .listRowBackground(Theme.grouped)
                } header: {
                    SettingsHeader("Animaciones")
                } footer: {
                    SettingsFooter("Con Reducir movimiento activado en el iPhone, la app usa fundidos tranquilos.")
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
                        SettingsFooter("\(AppIdentity.displayName) busca en internet el logo de las tiendas donde pagas y que no conoce. El servicio de logos ve la web de la tienda, nunca tus importes ni a quién envías dinero.")
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
            #if DEBUG
            .navigationDestination(isPresented: $demoOpensGuide) { AlertsGuideView(model: model) }
            .task { if DemoMode.guideStart != nil || DemoMode.guideSeed != nil { demoOpensGuide = true } }
            #endif
        }
        .onChange(of: tabEntrance.token) { _, _ in
            if !tabEntrance.suppressed { playEntrance() }
        }
        .onAppear {
            playEntrance()
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
        // Al cerrarse el ojo (desde aquí o desde Inicio) un importe en edición suelta el foco en el acto y pasa a máscara, sin
        // animación: nunca queda una cifra a la vista con el ojo cerrado (lote de cierre, ronda 1, I-3). Lo escrito se
        // guarda como al soltar el foco.
        .onChange(of: preferences.privateMode) { _, on in
            if on { releaseAmountFocus() }
        }
        #if DEBUG
        // `-MiBancoDemoCloseEyeAfter <s>`: cierra el ojo solo, por el mismo camino que el interruptor (para grabar desde
        // antes del cierre y para cerrarlo con un saldo en edición, con el teclado tapando el interruptor).
        .task {
            guard let seconds = DemoMode.closesEyeAfterSeconds else { return }
            try? await Task.sleep(for: .seconds(seconds))
            privacyBinding.wrappedValue = true
        }
        #endif
        .onDisappear { for bank in dirty { commit(bank) } }
        .onChange(of: logoDownloads) { _, on in logos.setDownloadsEnabled(on) }
        .sensoryFeedback(.success, trigger: saveCount)
        .sensoryFeedback(.error, trigger: errorCount)
    }

    /// La entrada de Ajustes: las filas de Bancos llegan una tras otra durante 1,2 s del kit. Con Reducir movimiento, nada.
    private func playEntrance() {
        guard !motion.reduce else { return }
        let token = entrance.token + 1
        entrance = Entrance(token: token, active: true, scope: .assembly)
        let window = motion.seconds(MotionEntranceWindow.seconds)
        Task {
            try? await Task.sleep(for: .seconds(window))
            if entrance.token == token { entrance.active = false }
        }
    }

    /// Los tres niveles, del más tranquilo al que aprobó el dueño.
    private static let motionLevels: [(value: MotionLevel, title: String)] = [
        (.subtle, "Sutil"), (.balanced, "Equilibrado"), (.expressive, "Expresivo"),
    ]

    private static func motionTitle(_ level: MotionLevel) -> String {
        switch level {
        case .subtle: "Sutil"
        case .balanced: "Equilibrado"
        case .expressive: "Expresivo"
        }
    }

    /// Suelta el foco de un saldo en edición sin animación (ver `onChange(of: preferences.privateMode)`).
    private func releaseAmountFocus() {
        #if DEBUG
        // Solo para demostrar que la prueba falla con el defecto de antes (`-MiBancoDemoRegressEyeFocus`).
        if DemoMode.isActive, DemoMode.regressesEyeFocus { return }
        #endif
        guard focused != nil else { return }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { focused = nil }
    }

    private var motionLevelBinding: Binding<MotionLevel> {
        Binding(get: { preferences.motionLevel }, set: { preferences.motionLevel = $0 })
    }

    /// El interruptor y el ojo de Inicio son el mismo estado. Cerrar el ojo NO se anima (como en Inicio): las cifras se
    /// cambian por la máscara en el acto, sin ningún fotograma con un dígito apagándose. Abrirlo, un fundido corto.
    private var privacyBinding: Binding<Bool> {
        Binding(get: { preferences.privateMode }, set: { on in
            if on { releaseAmountFocus() }
            withAnimation(on || motion.reduce ? nil : motion.fade) { preferences.privateMode = on }
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
            withAnimation(motion.fade) { errors[bank] = "Escribe un importe como 340,20" }
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
            withAnimation(motion.fade) { errors[bank] = "No se pudo guardar. Inténtalo de nuevo." }
            errorCount += 1
        }
    }

    /// ✓ trazado junto al campo: da un pequeño bote (1 → 1,12 → 1), se queda 1,4 s del kit y se va con un fundido.
    private func flashSaved(_ bank: BankID) {
        withAnimation(motion.fade) { _ = savedFlash.insert(bank) }
        saveCount += 1
        let hold = motion.seconds(1.4)
        Task {
            try? await Task.sleep(for: .seconds(hold))
            withAnimation(motion.fade) { _ = savedFlash.remove(bank) }
        }
    }
}

/// Fila de saldo: logo, nombre, estado según origen real (banco conectado, extracto, aviso o a mano; R25) y el campo
/// (solo lectura si el banco está conectado). Para VoiceOver, el campo editable es "Saldo de Revolut".
private struct BalanceRow: View {
    @Environment(\.motion) private var motion
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
                    // Con el ojo cerrado, la máscara del kit: ninguna cifra montada.
                    Text(hidden ? (info.map { maskedEUR($0.cents, sign: false) } ?? "—") : formatted)
                        .titan(.option)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.label)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 40)
                        .contentTransition(.identity)
                        .privacySensitive()
                        .accessibilityLabel("Saldo de \(bank.displayName): \(spoken)")
                } else {
                    let isEditing = focused.wrappedValue == bank
                    // Con el ojo cerrado (y sin editar) el saldo no se dibuja: en su sitio va la máscara del kit.
                    let masked = hidden && !isEditing && !text.isEmpty
                    HStack(spacing: 8) {
                        if saved {
                            SavedCheck()
                                .transition(.opacity)
                        }
                        MaskedAmountTextField(placeholder: "0,00 €", text: $text, masked: masked)
                            .titan(.option)
                            .fontWeight(.semibold)
                            .multilineTextAlignment(stacked ? .leading : .trailing)
                            .keyboardType(.numbersAndPunctuation)
                            .submitLabel(.done)
                            .focused(focused, equals: bank)
                            .onSubmit(onSubmit)
                            .padding(.horizontal, 10)
                            .frame(minWidth: 96, maxWidth: stacked ? .infinity : 128, minHeight: 40)
                            .background(Theme.fieldFill.opacity(isEditing ? 1 : 0), in: .rect(cornerRadius: Theme.Radius.field))
                            .animation(motion.fade, value: isEditing)
                            .accessibilityLabel("Saldo de \(bank.displayName)")
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

/// El ✓ de «guardado» junto a un campo: se traza y da un pequeño bote (1 → 1,12 → 1) con los tiempos del kit. Con
/// Reducir movimiento, sin bote.
struct SavedCheck: View {
    @Environment(\.motion) private var motion
    @State private var landed = 0

    var body: some View {
        DrawnCheck(lineWidth: 2, color: Theme.label)
            .frame(width: 16, height: 16)
            .keyframeAnimator(initialValue: 1.0, trigger: motion.reduce ? 0 : landed) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(1.12, duration: motion.seconds(0.16))
                    CubicKeyframe(1.0, duration: motion.seconds(0.22))
                }
            }
            .onAppear { landed += 1 }
            .accessibilityLabel("Guardado")
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

/// Las guías de Atajos y el aviso de prueba, en su propia pantalla. Cada guía se empuja en esta misma navegación.
struct AlertsGuideView: View {
    let model: LedgerModel
    #if DEBUG
    /// Demo (`-MiBancoDemoAlertsGuide`): paso concreto al que se salta nada más abrir.
    @State private var demoStart: DemoGuideStart?
    @Environment(AppPreferences.self) private var preferences
    #endif

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
        #if DEBUG
        .navigationDestination(item: $demoStart) { start in
            GuideStepView(track: start.track, model: model, start: start.resume ? nil : start.step,
                          resume: start.resume ? preferences.guideResume(start.track) : nil)
        }
        .task {
            if let seed = DemoMode.guideSeed {
                demoStart = DemoGuideStart(track: seed.track, step: seed.number - 1, resume: true)
            } else if let start = DemoMode.guideStart, let track = start.track {
                demoStart = DemoGuideStart(track: track, step: start.step)
            }
        }
        #endif
    }
}

#if DEBUG
struct DemoGuideStart: Hashable {
    let track: GuideTrack
    let step: Int
    /// Con `-MiBancoDemoGuideSeed`: se abre retomando el paso guardado.
    var resume = false
}
#endif
