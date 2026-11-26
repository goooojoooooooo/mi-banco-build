import MiBancoCore
import SwiftUI

/// Guía en 4 pasos para dar de alta Enable Banking y traer la clave `.pem` (Plan 2, tarea 11; U55, U59).
struct ConnectionGuideView: View {
    let model: LedgerModel
    var requestImport: (ImportKind) -> Void = { _ in }

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.presentationGate) private var gate
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step = 1
    @State private var movingForward = true
    @State private var urlCopied = false
    @State private var pickedDER: Data?
    @State private var appIDText = ""
    @State private var errorText: String?
    @State private var keySaved = BankingCredentials.isReady
    @State private var saveTick = 0
    @State private var errorTick = 0
    @FocusState private var idFocused: Bool

    private var connector: BankConnector { BankConnector.shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                stepperHeader

                Group {
                    switch step {
                    case 1:
                        stepOneCard
                    case 2:
                        stepTwoCard
                    case 3:
                        stepThreeCard
                    default:
                        stepFourCard
                    }
                }
                .id(step)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .move(edge: movingForward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: movingForward ? .leading : .trailing).combined(with: .opacity)
                ))

                if step > 1 {
                    Button {
                        go(to: step - 1)
                    } label: {
                        Text("Paso anterior")
                            .titan(.subtitle)
                            .foregroundStyle(Theme.label2)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Preparar conexión")
        .navigationBarTitleDisplayMode(.inline)
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
        #if DEBUG
        .onAppear {
            if DemoMode.isActive && DemoMode.demoGuideKey && pickedDER == nil && !keySaved {
                pickedDER = Data([0x01])
                appIDText = "11111111-1111-4111-8111-111111111111"
            }
        }
        #endif
        .sensoryFeedback(Haptics.success, trigger: saveTick)
        .sensoryFeedback(Haptics.error, trigger: errorTick)
    }

    private var stepperHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Paso \(step) de 4")
                .titan(.meta)
                .foregroundStyle(Theme.label2)
                .contentTransition(.numericText())
                .accessibilityIdentifier("connection-guide-progress")

            HStack(spacing: 6) {
                ForEach(1...4, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Theme.label : Theme.raised)
                        .frame(height: 4)
                }
            }
            .accessibilityHidden(true)
        }
    }

    // MARK: - Paso 1

    private var stepOneCard: some View {
        guideCard(
            title: "Crea tu cuenta gratis",
            bodyText: "En Enable Banking, solo con tu correo."
        ) {
            Button {
                if let url = URL(string: "https://enablebanking.com/cp/") {
                    openURL(url)
                }
            } label: {
                primaryButtonLabel("Abrir Enable Banking")
            }
            .buttonStyle(.pressable)

            Button {
                go(to: 2)
            } label: {
                secondaryButtonLabel("Ya está")
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("guide-next")
        }
    }

    // MARK: - Paso 2

    private var stepTwoCard: some View {
        guideCard(
            title: "Registra la app",
            bodyText: "En «API applications», elige Production, ponle de nombre \(AppIdentity.displayName) y pega esta dirección en «Redirect URLs». Luego, Register: se descargará un archivo .pem."
        ) {
            Text(BankingConstants.redirectURL.absoluteString)
                .titan(.meta)
                .foregroundStyle(Theme.label2)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.fieldFill, in: RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous))

            Button {
                Pasteboard.copy(BankingConstants.redirectURL.absoluteString)
                withAnimation(reduceMotion ? nil : Theme.Motion.quick) {
                    urlCopied = true
                }
                saveTick += 1
            } label: {
                HStack(spacing: 8) {
                    if urlCopied {
                        DrawnCheck(lineWidth: 2.2, color: Theme.canvas)
                            .frame(width: 16, height: 16)
                    }
                    Text(urlCopied ? "Copiada" : "Copiar dirección")
                        .titan(.option)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(Theme.canvas)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Theme.label, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("guide-copy-redirect")

            Button {
                go(to: 3)
            } label: {
                secondaryButtonLabel("Ya está")
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("guide-next")
        }
    }

    // MARK: - Paso 3

    private var stepThreeCard: some View {
        guideCard(
            title: "Vincula tus bancos",
            bodyText: "En la misma web, «Activate by linking accounts»: aprueba Revolut y después imagin en sus apps."
        ) {
            Button {
                go(to: 4)
            } label: {
                primaryButtonLabel("Ya está")
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("guide-next")
        }
    }

    // MARK: - Paso 4

    private var stepFourCard: some View {
        guideCard(
            title: "Trae tu clave",
            bodyText: "Elige el archivo .pem que se descargó."
        ) {
            Button {
                guard gate?.canPresent == true, scenePhase == .active else { return }
                errorText = nil
                requestImport(.bankKey { result in
                    handleKeyImport(result)
                })
            } label: {
                if keySaved {
                    secondaryButtonLabel("Elegir otra clave")
                } else {
                    primaryButtonLabel("Elegir clave")
                }
            }
            .buttonStyle(.pressable)

            Text("Si sales de la app antes de guardar, tendrás que elegir la clave otra vez: no la guardo hasta que toques «Guardar».")
                .titan(.meta)
                .foregroundStyle(Theme.label3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if pickedDER != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ID de la app")
                        .titan(.meta)
                        .foregroundStyle(Theme.label2)
                    TextField("00000000-0000-4000-8000-000000000000", text: $appIDText)
                        .titan(.meta)
                        .foregroundStyle(Theme.label)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($idFocused)
                        .submitLabel(.done)
                        .onSubmit(saveKey)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(Theme.fieldFill, in: RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous))
                        .privacySensitive()
                        .accessibilityLabel("ID de la app")

                    Button(action: saveKey) {
                        primaryButtonLabel("Guardar")
                    }
                    .buttonStyle(.pressable)
                }
                .padding(.top, 4)
            }

            if let errorText {
                Text(errorText)
                    .titan(.meta)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if keySaved {
                stepFourConnectSection
            }
        }
    }

    @ViewBuilder
    private var stepFourConnectSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch connector.phase {
            case .opening(let bank), .waitingForBank(let bank):
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Theme.label)
                    Text("Esperando a \(bank.displayName)…")
                        .titan(.option)
                        .foregroundStyle(Theme.label)
                }
                Button {
                    connector.cancelWebSession()
                } label: {
                    secondaryButtonLabel("Cancelar")
                }
                .buttonStyle(.pressable)

            case .finishing(let bank):
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Theme.label)
                    Text("Terminando con \(bank.displayName)…")
                        .titan(.option)
                        .foregroundStyle(Theme.label)
                }

            case .needsResume(let bank):
                Text("¿Ya lo has aprobado en la app de \(bank.displayName)?")
                    .titan(.option)
                    .foregroundStyle(Theme.label)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await connector.resume() }
                } label: {
                    primaryButtonLabel("Seguir")
                }
                .buttonStyle(.pressable)
                Button {
                    Task { await connector.connect(bank) }
                } label: {
                    secondaryButtonLabel("Empezar de nuevo")
                }
                .buttonStyle(.pressable)

            case let .failed(bank, message):
                Text(message)
                    .titan(.subtitle)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await connector.connect(bank) }
                } label: {
                    primaryButtonLabel("Empezar de nuevo")
                }
                .buttonStyle(.pressable)

            case let .chooseASPSP(bank, list):
                NavigationLink {
                    ASPSPPickerView(bank: bank, list: list) { chosen in
                        Task { await connector.connect(bank, aspsp: chosen) }
                    }
                } label: {
                    primaryButtonLabel("Elegir \(bank.displayName) en la lista")
                }
                .buttonStyle(.pressable)

            case .connected(let connectedBank):
                HStack(spacing: 8) {
                    DrawnCheck(lineWidth: 2.2, color: Theme.income)
                        .frame(width: 16, height: 16)
                    Text("\(connectedBank.displayName) conectado")
                        .titan(.subtitle)
                        .foregroundStyle(Theme.income)
                }
                Button {
                    Task { await connector.connect(.rev) }
                } label: {
                    primaryButtonLabel("Conectar Revolut")
                }
                .buttonStyle(.pressable)

                Button {
                    Task { await connector.connect(.ima) }
                } label: {
                    secondaryButtonLabel("Conectar imagin")
                }
                .buttonStyle(.pressable)

            case .idle:
                Button {
                    Task { await connector.connect(.rev) }
                } label: {
                    primaryButtonLabel("Conectar Revolut")
                }
                .buttonStyle(.pressable)

                Button {
                    Task { await connector.connect(.ima) }
                } label: {
                    secondaryButtonLabel("Conectar imagin")
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Componentes y acciones

    private func guideCard<Actions: View>(
        title: String,
        bodyText: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .titan(.cardTitle)
                .foregroundStyle(Theme.label)
                .fixedSize(horizontal: false, vertical: true)
            Text(bodyText)
                .titan(.body)
                .foregroundStyle(Theme.label2)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                actions()
            }
            .padding(.top, 4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
    }

    private func primaryButtonLabel(_ title: String) -> some View {
        Text(title)
            .titan(.option)
            .fontWeight(.semibold)
            .foregroundStyle(Theme.canvas)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.label, in: Capsule())
            .contentShape(Capsule())
    }

    private func secondaryButtonLabel(_ title: String) -> some View {
        Text(title)
            .titan(.option)
            .fontWeight(.medium)
            .foregroundStyle(Theme.label)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Theme.raised, in: Capsule())
            .contentShape(Capsule())
    }

    private func go(to target: Int) {
        let clamped = min(max(target, 1), 4)
        idFocused = false
        movingForward = clamped >= step
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.cardSettle) {
            step = clamped
        }
    }

    private func clearSensitiveState() {
        idFocused = false
        pickedDER = nil
        appIDText = ""
    }

    private func handleKeyImport(_ result: Result<URL, Error>) {
        guard gate?.canPresent == true, scenePhase == .active, case .success(let url) = result else { return }
        let generation = gate?.generation ?? 0
        Task {
            do {
                let parsed = try await Task.detached(priority: .userInitiated) {
                    try BankingCredentials.readKeyFile(url)
                }.value
                guard (gate?.generation ?? 0) == generation, gate?.canPresent == true, scenePhase == .active else { return }
                pickedDER = parsed.pkcs1DER
                appIDText = parsed.suggestedAppID ?? ""
                errorText = nil
            } catch let error as BankingCredentialsError {
                guard (gate?.generation ?? 0) == generation else { return }
                errorText = error.message
                errorTick += 1
            } catch {
                guard (gate?.generation ?? 0) == generation else { return }
                errorText = BankingCredentialsError.invalidKey.message
                errorTick += 1
            }
        }
    }

    private func saveKey() {
        idFocused = false
        guard let der = pickedDER else { return }
        let trimmed = appIDText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidApplicationID(trimmed) else {
            errorText = "Ese ID no parece correcto. Suele ser el nombre del archivo .pem, sin «.pem»."
            errorTick += 1
            return
        }
        #if DEBUG
        if DemoMode.isActive && DemoMode.demoGuideKey {
            pickedDER = nil
            appIDText = ""
            errorText = nil
            keySaved = true
            saveTick += 1
            return
        }
        #endif
        do {
            try BankingCredentials.save(appID: trimmed, pkcs1DER: der)
            pickedDER = nil
            appIDText = ""
            errorText = nil
            keySaved = true
            saveTick += 1
        } catch let error as BankingCredentialsError {
            errorText = error.message
            errorTick += 1
        } catch {
            errorText = BankingCredentialsError.invalidKey.message
            errorTick += 1
        }
    }
}
