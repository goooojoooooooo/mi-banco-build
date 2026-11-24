import MiBancoCore
import SwiftUI

/// Pantalla de un banco dentro de Ajustes › Bancos (Plan 2, tareas 11 y 12; R20, R41, R42, R43, U43, U50, U55).
/// Permite conectar o renovar con Enable Banking, actualizar ahora, importar extractos CSV o desconectar.
/// Confirmaciones y selector de archivos pasan por `RootView` (regla de una sola hoja).
///
/// Forma (fase B, S8): una cabecera oscura (banco, saldo, estado y acciones) y, encima, una hoja que sube al desplazar
/// con los últimos movimientos de ESE banco y, debajo, su historial y la desconexión (`BankHeaderSheet`).
/// Conectar (S9) enseña los pasos Verificar › Conectar › Importar con un porcentaje que sigue la fase REAL del conector
/// (`StepPercent`), y al acabar bien, «Banco, conectado». Mientras la lista se llena por primera vez tras conectar, un
/// esqueleto con brillo (S11).
/// Si se llega volando desde Inicio (`CardFlight.request` de este banco), la cabecera espera a que la tarjeta aterrice;
/// si no aterriza a tiempo, aparece igual. Desde cualquier otro sitio la cabecera está desde el principio.
struct BankLinkView: View {
    let model: LedgerModel
    var portfolio: PortfolioModel? = nil
    let bank: BankID
    var present: (RootSheet) -> Void = { _ in }
    var requestImport: (ImportKind) -> Void = { _ in }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.presentationGate) private var gate
    @Environment(\.motion) private var motion
    @Environment(\.cardFlight) private var flight
    @Environment(AppPreferences.self) private var preferences

    @State private var importPreview: ImportPreview?
    @State private var importError: String?
    @State private var errorTick = 0
    /// Lo que la hoja ha subido sobre la cabecera.
    @State private var scroll = BankHeaderScroll()
    /// El porcentaje del trámite visto en esta pantalla (`nil` = ninguno).
    @State private var progress: StepPercent?
    /// Cuándo empezó el paso en curso.
    @State private var stepStarted = Date()
    /// «Banco, conectado» a la vista.
    @State private var success = false
    /// Se ha conectado desde esta pantalla: la lista puede estar llenándose por primera vez.
    @State private var connectedHere = false
    /// Se abrió con una tarjeta volando hacia aquí.
    @State private var awaitsFlight = false
    /// El plazo de la tarjeta ha pasado: la cabecera se ve aunque no haya aterrizado.
    @State private var flightTimedOut = false
    @Namespace private var zoom
    #if DEBUG
    @State private var didShowDemoImport = false
    /// Guion de demo (`-MiBancoDemoConnectScript`): hace de banco; `nil` = manda el conector.
    @State private var demoStage: BankConnectStage?
    @State private var demoFirstFill = false
    #endif

    private static let maxStatementBytes = 10 * 1024 * 1024
    /// Cuántos movimientos enseña la hoja (los últimos).
    private static let latestCount = 8

    private var connector: BankConnector { BankConnector.shared }
    private var syncStatus: BankSyncStatus { BankSyncStatus.shared }

    private var link: BankLinkInfo? {
        model.state.links[bank]
    }

    private var canConnect: Bool {
        connector.canConnect(bank)
    }

    private func statusLines(now: Date) -> BankStatusLines {
        let computed = bankStatusLines(
            bank: bank,
            link: link,
            estimated: model.snapshot.balances[bank]?.estimated,
            canConnect: canConnect,
            now: now,
            calendar: DateText.madridCalendar
        )
        if syncStatus.running.contains(bank) {
            return BankStatusLines(
                primary: "Conectado · actualizando…",
                secondary: computed.secondary,
                action: nil
            )
        }
        return computed
    }

    private var canCancelWaiting: Bool {
        switch connector.phase {
        case .opening(let b), .waitingForBank(let b):
            b == bank
        default:
            false
        }
    }

    private var showsForgetEverything: Bool {
        BankingCredentials.isReady || !model.state.links.isEmpty
    }

    private var needsResumeForThisBank: Bool {
        if case .needsResume(let b) = connector.phase { return b == bank }
        return false
    }

    private var failedMessageForThisBank: String? {
        if case let .failed(b, msg) = connector.phase, b == bank { return msg }
        return nil
    }

    private var aspspChoicesForThisBank: [EBASPSP]? {
        if case let .chooseASPSP(b, list) = connector.phase, b == bank { return list }
        return nil
    }

    // MARK: El trámite de conexión, paso a paso

    /// La fase REAL del conector para este banco. La primera carga de movimientos tras conectar cuenta dentro del tercer
    /// paso (solo si el trámite se ha visto en esta pantalla): el 100 llega cuando el banco está conectado y esa carga
    /// no está en marcha.
    private var stage: BankConnectStage {
        #if DEBUG
        if let demoStage { return demoStage }
        #endif
        switch connector.phase {
        case .opening(let b) where b == bank: return .step(0)
        case .waitingForBank(let b) where b == bank: return .step(1)
        case .finishing(let b) where b == bank: return .step(2)
        case .connected(let b) where b == bank:
            return progress?.isRunning == true && syncStatus.running.contains(bank) ? .step(2) : .connected
        case .failed(let b, _) where b == bank: return .failed
        default: return .none
        }
    }

    /// El porcentaje que se dibuja: el de esta pantalla o, en el primer instante de un paso (antes de apuntarlo), uno
    /// recién empezado en ese paso.
    private var shownProgress: StepPercent? {
        if let progress { return progress }
        if case .step(let index) = stage {
            var fresh = StepPercent()
            fresh.enter(step: index)
            return fresh
        }
        return nil
    }

    private var stepCaption: String? {
        switch stage {
        case .step(let index): index >= 2 ? "Terminando con \(bank.displayName)…" : "Esperando a \(bank.displayName)…"
        case .none, .connected, .failed: nil
        }
    }

    private func stageChanged(to new: BankConnectStage) {
        switch new {
        case .step(let index):
            if let current = progress, current.isRunning, index >= current.step {
                guard index > current.step else { return }
                progress?.enter(step: index)
            } else {
                // Un trámite nuevo (o uno que vuelve a empezar): el porcentaje arranca de cero en su paso.
                var fresh = StepPercent()
                fresh.enter(step: index)
                progress = fresh
                success = false
            }
            stepStarted = Date()
        case .connected:
            guard progress?.isRunning == true else { return }
            progress?.succeed()
            success = true
            connectedHere = true
        case .failed:
            guard let current = progress, current.isRunning else { return }
            let stretch = max(0.05, motion.level.timeScale * motion.timeMultiplier)
            progress?.fail(shown: current.value(elapsed: Date().timeIntervalSince(stepStarted) / stretch))
        case .none:
            // Cancelado, «Dejarlo» o vuelta a reposo: no queda trámite que enseñar (el éxito sí se queda hasta «Listo»).
            if progress?.outcome != .succeeded { progress = nil }
        }
    }

    private func startConnect() {
        #if DEBUG
        if DemoMode.scriptsConnect {
            runDemoConnectScript()
            return
        }
        #endif
        Task { await connector.connect(bank) }
    }

    private func dismissSuccess() {
        success = false
        progress = nil
    }

    #if DEBUG
    /// Hace de banco en la demo: cada paso dura lo que diga `-MiBancoDemoConnectStep`, luego conectado y la lista
    /// llenándose por primera vez. La pantalla (pasos, porcentaje, éxito, esqueleto) es la de verdad.
    private func runDemoConnectScript() {
        guard demoStage == nil || demoStage == .connected else { return }
        Task {
            let wait = DemoMode.connectScriptStepSeconds
            for index in 0..<3 {
                demoStage = .step(index)
                try? await Task.sleep(for: .seconds(wait))
            }
            demoFirstFill = true
            demoStage = .connected
            try? await Task.sleep(for: .seconds(DemoMode.connectScriptFillSeconds))
            demoFirstFill = false
        }
    }
    #endif

    // MARK: Lo que se enseña

    /// La cabecera se ve salvo mientras una tarjeta viene volando hacia aquí y aún no ha aterrizado ni vencido su plazo.
    private var headerShown: Bool {
        !awaitsFlight || flight?.landed == true || flightTimedOut
    }

    /// Los últimos movimientos de este banco, con las cabeceras de sus días (sin avisos sin leer: aquí no se borran).
    private var latestEntries: [ListEntry] {
        let all = model.snapshot.entries[AccountCard(bank: bank)] ?? []
        var out: [ListEntry] = []
        var pendingHeader: ListEntry?
        var rows = 0
        for entry in all {
            switch entry.kind {
            case .header:
                pendingHeader = entry
            case .row(let row, _):
                guard case .movement = row.item else { continue }
                if let header = pendingHeader {
                    out.append(header)
                    pendingHeader = nil
                }
                out.append(entry)
                rows += 1
            }
            if rows >= Self.latestCount { break }
        }
        return out
    }

    /// La lista se está llenando por primera vez tras conectar desde aquí: esqueleto en vez de filas.
    private func isFirstFill(_ entries: [ListEntry]) -> Bool {
        #if DEBUG
        if demoFirstFill { return true }
        #endif
        return connectedHere && entries.isEmpty && syncStatus.running.contains(bank)
    }

    var body: some View {
        // Hora de verdad al dibujar; `TimelineView` solo marca el redibujo de cada minuto (U80).
        TimelineView(.everyMinute) { _ in
            let lines = statusLines(now: AppClock.now)
            let balance = model.snapshot.balances[bank]
            BankHeaderSheet(scroll: scroll, title: bank.displayName, balanceCents: balance?.cents,
                            hidden: preferences.privateMode, headerShown: headerShown) {
                header(lines: lines, balance: balance)
            } sheet: {
                sheetContent
            }
        }
        .navigationTitle(bank.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $importPreview) { preview in
            ImportStatementView(model: model, portfolio: portfolio, bank: bank, preview: preview) {
                importPreview = nil
            }
        }
        .onDisappear {
            if failedMessageForThisBank != nil {
                connector.resetTransientPhase()
            }
        }
        .onChange(of: stage) { _, new in stageChanged(to: new) }
        .sensoryFeedback(Haptics.error, trigger: errorTick)
        .onAppear {
            #if DEBUG
            if DemoMode.requestsFlightOnOpen, flight?.request == nil {
                flight?.request = CardFlight.Request(bank: bank, card: AccountCard(bank: bank), source: .zero)
            }
            if DemoMode.isActive && DemoMode.opensStatementImport && !didShowDemoImport && importPreview == nil {
                didShowDemoImport = true
                importPreview = try? model.previewImport(DemoMode.sampleRevolutStatementData(), bank: .rev)
            }
            #endif
            // Solo espera a la tarjeta si de verdad se pidió un vuelo hacia ESTE banco y aún no ha aterrizado. El plazo
            // (0,9 s del kit) garantiza que la cabecera nunca se queda escondida si el vuelo no llega.
            if let request = flight?.request, request.bank == bank, flight?.landed != true, !flightTimedOut {
                awaitsFlight = true
                let deadline = motion.seconds(0.9)
                Task {
                    try? await Task.sleep(for: .seconds(deadline))
                    withAnimation(motion.fade) { flightTimedOut = true }
                }
            }
            // La pantalla se abre con el trámite ya en marcha (se volvió a ella a mitad): se apunta su paso.
            if case .step = stage, progress == nil { stageChanged(to: stage) }
        }
    }

    // MARK: Cabecera

    private func header(lines: BankStatusLines, balance: BalanceInfo?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    BankLogo(bank: bank, size: 28)
                    Text(bank.displayName)
                        .titan(.cardTitle)
                        .foregroundStyle(Theme.label)
                }
                .motionEntrance(0)

                if success {
                    BankConnectedFlash(bank: bank, status: lines.primary, balanceCents: balance?.cents,
                                       onShowMovements: {
                                           dismissSuccess()
                                           scroll.dockRequests += 1
                                       }, onDone: dismissSuccess)
                        .padding(.top, 18)
                        .transition(.opacity)
                } else {
                    if let balance {
                        RollingAmount(cents: balance.cents, style: .hero(euros: 46, cents: 24, centsColor: Theme.label2))
                            .foregroundStyle(Theme.label)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Saldo de \(bank.displayName): \(spokenAmount(balance.cents, hidden: preferences.privateMode))")
                            .accessibilityIdentifier("bank-header-balance")
                            .padding(.top, 10)
                            .motionEntrance(1)
                    }

                    Text(lines.primary)
                        .titan(balance == nil ? .sheetTitle : .option)
                        .foregroundStyle(Theme.label)
                        .contentTransition(.numericText())
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, balance == nil ? 12 : 6)
                        .motionEntrance(2)

                    if let secondary = lines.secondary {
                        Text(secondary)
                            .titan(.subtitle)
                            .foregroundStyle(Theme.label2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                            .motionEntrance(3)
                    }

                    if bank == .tr && !canConnect {
                        Text("Trade Republic no se puede conectar gratis. Exporta su extracto en su app (Perfil › Extractos › Exportar transacciones) e impórtalo aquí.")
                            .titan(.subtitle)
                            .foregroundStyle(Theme.label2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                            .motionEntrance(3)
                    }
                }
            }
            // Donde aterriza la tarjeta que vuela desde Inicio.
            .cardFlightDestination()

            if !success {
                VStack(alignment: .leading, spacing: 10) {
                    phaseRows
                    actionRows(lines: lines)
                    if let importError {
                        Text(importError)
                            .titan(.meta)
                            .foregroundStyle(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 18)
                .motionEntrance(4)
                .fadesWithBankHeader()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 26)
        .animation(motion.calmAnimation(.enter), value: success)
        .assemblesOnFirstAppear()
    }

    @ViewBuilder
    private var phaseRows: some View {
        if let shown = shownProgress, !needsResumeForThisBank {
            VStack(alignment: .leading, spacing: 14) {
                StepperProgress(steps: BankConnectStage.steps, current: shown.step, finished: false,
                                caption: stepCaption, percent: shown, since: stepStarted, spins: true, identifier: "bank-steps")
                    // Los títulos de los extremos sobresalen de su nodo.
                    .padding(.horizontal, 30)
                    .padding(.top, 4)

                if let failed = failedMessageForThisBank {
                    failedRows(failed)
                } else if canCancelWaiting {
                    Button {
                        connector.cancelWebSession()
                    } label: {
                        Text("Cancelar")
                            .titan(.option)
                            .foregroundStyle(Theme.label2)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Theme.raised, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityIdentifier("bank-cancel-wait")
                }
            }
            .accessibilityIdentifier("bank-steps-block")
        } else if needsResumeForThisBank {
            VStack(alignment: .leading, spacing: 12) {
                Text("¿Ya lo has aprobado en la app de \(bank.displayName)?")
                    .titan(.option)
                    .foregroundStyle(Theme.label)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        Task { await connector.resume() }
                    } label: {
                        Text("Seguir")
                            .titan(.option)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.canvas)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Theme.label, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)

                    Button {
                        startConnect()
                    } label: {
                        Text("Empezar de nuevo")
                            .titan(.option)
                            .foregroundStyle(Theme.label)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Theme.raised, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                }

                Button {
                    connector.resetTransientPhase()
                } label: {
                    Text("Dejarlo")
                        .titan(.subtitle)
                        .foregroundStyle(Theme.label2)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } else if let failed = failedMessageForThisBank {
            failedRows(failed)
        } else if let list = aspspChoicesForThisBank {
            NavigationLink {
                ASPSPPickerView(bank: bank, list: list) { chosen in
                    Task { await connector.connect(bank, aspsp: chosen) }
                }
            } label: {
                HStack(spacing: Theme.Space.row) {
                    Text("Elegir \(bank.displayName) en la lista")
                        .titan(.option)
                        .foregroundStyle(Theme.label)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.passive)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .background(Theme.grouped, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
        }
    }

    /// El trámite falló: el mensaje del conector, «Empezar de nuevo» y «Dejarlo» (el porcentaje, si lo había, congelado).
    private func failedRows(_ failed: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(failed)
                .titan(.subtitle)
                .foregroundStyle(Theme.warning)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                startConnect()
            } label: {
                Text("Empezar de nuevo")
                    .titan(.option)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.canvas)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.label, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.pressable)

            Button {
                connector.resetTransientPhase()
            } label: {
                Text("Dejarlo")
                    .titan(.subtitle)
                    .foregroundStyle(Theme.label2)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func actionRows(lines: BankStatusLines) -> some View {
        if shownProgress == nil && !needsResumeForThisBank && failedMessageForThisBank == nil && aspspChoicesForThisBank == nil {
            switch lines.action {
            case .connect:
                Button {
                    startConnect()
                } label: {
                    actionCapsule("Conectar \(bank.displayName)", prominent: true)
                }
                .buttonStyle(.pressable)
                .disabled(connector.isForgetting)

            case .renew:
                Button {
                    startConnect()
                } label: {
                    actionCapsule("Renovar conexión", prominent: true)
                }
                .buttonStyle(.pressable)
                .disabled(connector.isForgetting)

            case .refresh:
                Button {
                    Task { _ = await BankSync.shared.refresh(trigger: .manual, only: bank) }
                } label: {
                    actionCapsule("Actualizar ahora", prominent: true)
                }
                .buttonStyle(.pressable)
                .disabled(syncStatus.running.contains(bank) || connector.isForgetting)

            case .importStatement, .editBalance, nil:
                EmptyView()
            }
        }

        Button {
            guard gate?.canPresent == true, scenePhase == .active else { return }
            importError = nil
            requestImport(.statement(bank) { result in
                handleStatementFile(result)
            })
        } label: {
            actionCapsule("Importar extracto", prominent: lines.action == .importStatement)
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("bank-import-statement")
    }

    // MARK: Hoja: movimientos de este banco, historial y desconexión

    private var sheetContent: some View {
        let entries = latestEntries
        let firstFill = isFirstFill(entries)
        return VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(.white.opacity(0.22))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .accessibilityHidden(true)

            if firstFill || !entries.isEmpty {
                Text("Movimientos")
                    .titan(.sheetTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.label)
                    .padding(.horizontal, Theme.Space.gutter)
                    .padding(.top, 10)
                    .padding(.bottom, 2)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("bank-movements-title")

                if firstFill {
                    SkeletonRows(count: 5)
                        .padding(.top, 14)
                        .transition(.opacity)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            ListEntryView(entry: entry, logoDomain: logoDomain(entry), isFresh: false, zoom: zoom,
                                          onOpen: openMovement, onDeleteUnread: { _ in })
                                .motionEntrance(index)
                        }
                    }
                    .accessibilityIdentifier("bank-movements")
                    // Cada vez que llegan las filas (también tras el esqueleto) entran una tras otra.
                    .assemblesOnFirstAppear()
                    .transition(.opacity)
                }
            }

            if canConnect || link != nil {
                SettingsHeader("Historial")
                    .padding(.horizontal, 36)
                    .padding(.top, Theme.Space.section)
                    .padding(.bottom, 8)
                Text("Primera actualización: últimos 12 meses (lo que dé el banco)")
                    .titan(.subtitle)
                    .foregroundStyle(Theme.label2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
                    .padding(.horizontal, 16)
            }

            if link != nil || showsForgetEverything || connector.isForgetting {
                VStack(spacing: 0) {
                    if connector.isForgetting {
                        HStack(spacing: 10) {
                            ProgressView()
                                .tint(Theme.label)
                            Text("Borrando…")
                                .titan(.option)
                                .foregroundStyle(Theme.label2)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 48)
                        .padding(.horizontal, 16)
                    }

                    if link != nil {
                        if connector.isForgetting { rowDivider }
                        Button(role: .destructive) {
                            guard gate?.canPresent == true, scenePhase == .active, !connector.isForgetting else { return }
                            present(.confirmDisconnect(bank))
                        } label: {
                            Text("Desconectar")
                                .titan(.option)
                                .foregroundStyle(connector.isForgetting ? Theme.label3 : Theme.warning)
                                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                .padding(.horizontal, 16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(connector.isForgetting)
                    }

                    if showsForgetEverything {
                        if link != nil || connector.isForgetting { rowDivider }
                        Button(role: .destructive) {
                            guard gate?.canPresent == true, scenePhase == .active, !connector.isForgetting else { return }
                            present(.confirmForget)
                        } label: {
                            Text("Olvidar clave y conexiones")
                                .titan(.option)
                                .foregroundStyle(connector.isForgetting ? Theme.label3 : Theme.warning)
                                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                .padding(.horizontal, 16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(connector.isForgetting)
                    }
                }
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, Theme.Space.section)
            }
        }
        .padding(.bottom, Theme.Space.section)
        .animation(motion.calmAnimation(.row), value: firstFill)
    }

    private var rowDivider: some View {
        Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 16)
    }

    private func logoDomain(_ entry: ListEntry) -> String? {
        if case let .row(row, _) = entry.kind { return model.snapshot.logoDomains[row.id] }
        return nil
    }

    /// Abre el detalle del movimiento en la hoja única de `RootView`.
    private func openMovement(_ id: UUID) {
        guard gate?.canPresent == true, scenePhase == .active else { return }
        present(.movement(DetailRoute(id: id)))
    }

    private func actionCapsule(_ title: String, prominent: Bool) -> some View {
        Text(title)
            .titan(.option)
            .fontWeight(prominent ? .semibold : .medium)
            .foregroundStyle(prominent ? Theme.onTileSelected : Theme.label)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(prominent ? Theme.tileSelected : Theme.raised, in: Capsule())
            .contentShape(Capsule())
            .padding(.vertical, 2)
    }

    private func handleStatementFile(_ result: Result<URL, Error>) {
        guard gate?.canPresent == true, scenePhase == .active, case .success(let url) = result else { return }
        let targetBank = bank
        let generation = gate?.generation ?? 0
        Task {
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try Self.readStatementData(from: url)
                }.value
                guard (gate?.generation ?? 0) == generation, gate?.canPresent == true, scenePhase == .active else { return }
                let preview = try model.previewImport(data, bank: targetBank)
                importError = nil
                importPreview = preview
            } catch let error as StatementFileError {
                guard (gate?.generation ?? 0) == generation else { return }
                importError = error.message
                errorTick += 1
            } catch let error as StatementError {
                guard (gate?.generation ?? 0) == generation else { return }
                importError = Self.errorMessage(for: error, bank: targetBank)
                errorTick += 1
            } catch {
                guard (gate?.generation ?? 0) == generation else { return }
                importError = Self.errorMessage(for: .unreadable, bank: targetBank)
                errorTick += 1
            }
        }
    }

    private enum StatementFileError: Error {
        case tooLarge
        case unreadable

        var message: String {
            switch self {
            case .tooLarge:
                "Este archivo es demasiado grande (máx. 10 MB)."
            case .unreadable:
                "No reconozco este archivo. Usa el CSV que exporta tu banco."
            }
        }
    }

    nonisolated private static func readStatementData(from url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            throw StatementFileError.unreadable
        }
        guard size <= maxStatementBytes else {
            throw StatementFileError.tooLarge
        }
        guard let data = try? Data(contentsOf: url) else { throw StatementFileError.unreadable }
        guard data.count <= maxStatementBytes else { throw StatementFileError.tooLarge }
        return data
    }

    static func errorMessage(for error: StatementError, bank: BankID) -> String {
        switch error {
        case .missingColumns(let cols):
            let first = cols.first ?? ""
            let cap = first.prefix(1).uppercased() + first.dropFirst()
            return "Este archivo no parece un extracto de \(bank.displayName). Falta la columna «\(cap)»."
        case .wrongBank(let detected):
            return "Este extracto es de \(detected.displayName). Impórtalo desde su banco."
        case .unknownFormat, .empty, .unreadable:
            return "No reconozco este archivo. Usa el CSV que exporta tu banco."
        }
    }
}
