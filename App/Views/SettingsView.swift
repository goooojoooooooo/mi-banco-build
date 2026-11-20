import SwiftUI
import MiBancoCore

/// Ajustes en Titanio: grupos #141416 sobre negro, filas de 60 pt con su ficha de icono, interruptores en blanco y negro.
/// Los saldos se editan en su fila; solo se guarda un campo que el usuario ha tocado (`dirty`).
struct SettingsView: View {
    let model: LedgerModel
    /// Pedido desde la tarjeta de Inicio ("Editar saldo"): enfoca ese banco y se vacía.
    @Binding var focusRequest: BankID?

    @AppStorage("lockEnabled") private var lockEnabled = true
    @AppStorage(MerchantLogos.downloadsKey) private var logoDownloads = true
    @Environment(MerchantLogos.self) private var logos
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// Bancos recién guardados: un ✓ que se traza junto al campo.
    @State private var savedFlash: Set<BankID> = []
    @State private var saveCount = 0
    @State private var errorCount = 0
    @State private var texts: [BankID: String] = [:]
    @State private var errors: [BankID: String] = [:]
    /// Solo los campos que el usuario ha editado se guardan; el resto sigue al modelo.
    @State private var dirty: Set<BankID> = []
    @FocusState private var focused: BankID?
    #if DEBUG
    /// Demo (`-MiBancoDemoAlertsGuide`): abre la guía de avisos nada más aparecer Ajustes.
    @State private var demoOpensGuide = false
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(BankID.allCases, id: \.self) { bank in
                        BalanceRow(bank: bank, info: model.snapshot.balances[bank], text: binding(bank),
                                   error: errors[bank], saved: savedFlash.contains(bank), focused: $focused,
                                   onSubmit: { commit(bank) })
                    }
                } header: {
                    SettingsHeader("Saldos")
                } footer: {
                    SettingsFooter("Toca un saldo para corregirlo. imagin y Trade Republic no envían el saldo en sus avisos, así que lo estimamos.")
                }

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
            .navigationTitle("Ajustes")
            #if DEBUG
            .navigationDestination(isPresented: $demoOpensGuide) { AlertsGuideView(model: model) }
            .task { if DemoMode.guideStart != nil { demoOpensGuide = true } }
            #endif
        }
        .onAppear {
            refreshUntouched()
            applyFocusRequest()
        }
        .onChange(of: focusRequest) { _, _ in applyFocusRequest() }
        // Un intent puede cambiar un saldo con Ajustes abierto: los campos sin tocar lo reflejan.
        .onChange(of: model.snapshot.balances) { _, _ in refreshUntouched() }
        .onChange(of: focused) { old, _ in
            if let old { commit(old) }
        }
        // Al salir de la app se suelta el foco: guarda lo editado y quita el teclado de encima del bloqueo.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { focused = nil }
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

    /// "Diagnóstico: datos en grupo compartido · Versión 0.3.0 (3)"
    private var diagnostics: String {
        let place = SharedStore.location == .appGroup ? "grupo compartido" : "carpeta de la app"
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Diagnóstico: datos en \(place) · Versión \(version) (\(build))"
    }

    private func applyFocusRequest() {
        guard let bank = focusRequest else { return }
        focusRequest = nil
        Task {
            try? await Task.sleep(for: .milliseconds(350))
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

/// Fila de saldo: logo, nombre, "Exacto · del aviso de las 18:47" / "Estimado · corregido el 10 nov", y el campo.
/// Para VoiceOver, el campo es "Saldo de Revolut".
private struct BalanceRow: View {
    let bank: BankID
    let info: BalanceInfo?
    @Binding var text: String
    let error: String?
    let saved: Bool
    var focused: FocusState<BankID?>.Binding
    let onSubmit: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
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
                        .background(Color(hex: "#2A2A2D").opacity(focused.wrappedValue == bank ? 1 : 0), in: .rect(cornerRadius: Theme.Radius.field))
                        .animation(Theme.Motion.quick, value: focused.wrappedValue == bank)
                        .privateField(editing: focused.wrappedValue == bank)
                        .accessibilityLabel("Saldo de \(bank.displayName)")
                }
            }
            if let error {
                Text(error)
                    .titan(.meta)
                    .foregroundStyle(Theme.warning)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .onTapGesture { focused.wrappedValue = bank }
        .listRowBackground(Theme.grouped)
        .listRowSeparatorTint(Theme.separator)
    }

    private var status: String {
        guard let info else { return "Sin saldo todavía" }
        let calendar = Calendar.current
        if !info.estimated {
            let when = calendar.isDateInToday(info.setAt) ? "de las \(DateText.time(info.setAt))" : "del \(DateText.day(info.setAt))"
            return "Exacto · del aviso \(when)"
        }
        let when = calendar.isDateInToday(info.setAt) ? "hoy" : "el \(DateText.day(info.setAt))"
        return info.fromBank ? "Estimado · desde el aviso de \(when)" : "Estimado · corregido \(when)"
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
                .foregroundStyle(Color(hex: "#D1D1D6"))
                .frame(width: 30, height: 30)
                .background(Color(hex: "#232325"), in: .rect(cornerRadius: 8, style: .continuous))
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
        .navigationDestination(for: GuideTrack.self) { track in
            GuideStepView(track: track, model: model)
        }
        #if DEBUG
        .navigationDestination(item: $demoStart) { start in
            GuideStepView(track: start.track, model: model, start: start.step)
        }
        .task {
            if let start = DemoMode.guideStart, let track = start.track {
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
}
#endif
