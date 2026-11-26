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
    /// El porcentaje del trámite visto en esta pantalla y «Banco, conectado» (lo mueve solo la fase real; Core).
    @State private var progress = BankConnectProgress()
    /// Cuándo empezó el paso en curso (y, acabado bien, cuándo acabó: desde ahí corre el remate).
    @State private var stepStarted = Date()
    /// Cada remate; uno viejo que despierta tras esperar se retira.
    @State private var finishRun = 0
    /// Tras el remate, lo de la cabecera se está apagando antes de «conectado».
    @State private var clearing = false
    /// Alto de la cabecera (sin márgenes) mientras enseña los pasos: lo que reserva «conectado» al relevarlos.
    @State private var contentHeight: CGFloat = 0
    /// Alto mínimo reservado para la cabecera en el relevo a «conectado» (0 = nada reservado).
    @State private var reservedHeight: CGFloat = 0
    /// Se ha conectado desde esta pantalla: la lista puede estar llenándose por primera vez.
    @State private var connectedHere = false
    /// Se abrió con una tarjeta volando hacia aquí.
    @State private var awaitsFlight = false
    /// El plazo de la tarjeta ha pasado: la cabecera se ve aunque no haya aterrizado.
    @State private var flightTimedOut = false
    #if DEBUG
    @State private var didShowDemoImport = false
    /// Guion de demo (`-MiBancoDemoConnectScript`): una máquina `ConnectFlow` a la que el guion manda los eventos de
    /// verdad; su fase sustituye a la del conector (`nil` = manda el conector).
    @State private var demoFlow: ConnectFlow?
    /// Cada vuelta del guion; una vuelta vieja que despierta tras esperar se retira.
    @State private var demoRun = 0
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

    private var showsForgetEverything: Bool {
        BankingCredentials.isReady || !model.state.links.isEmpty
    }

    // MARK: El trámite de conexión, paso a paso

    /// La fase REAL del trámite: la del conector (en la demo con guion, la de la máquina `ConnectFlow` del guion, que
    /// recibe los mismos eventos que la del conector).
    private var phase: ConnectPhase {
        #if DEBUG
        if let demoFlow { return demoFlow.phase }
        #endif
        return connector.phase
    }

    /// La fase traducida para ESTE banco (Core: `BankConnectProgress`). La primera carga de movimientos tras conectar
    /// cuenta dentro del tercer paso solo si el trámite se ha visto en esta pantalla.
    private var stage: BankConnectStage {
        progress.stage(of: phase, bank: bank, syncing: syncStatus.running.contains(bank))
    }

    private var needsResumeForThisBank: Bool { stage == .needsResume }

    private var failedMessageForThisBank: String? {
        if case .failed(let message) = stage { return message }
        return nil
    }

    private var aspspChoicesForThisBank: [EBASPSP]? {
        if case .chooseASPSP(let list) = stage { return list }
        return nil
    }

    /// El porcentaje que se dibuja (Core decide cuál).
    private var shownProgress: StepPercent? { progress.shown(for: stage) }

    private func stageChanged(to new: BankConnectStage) {
        let stretch = max(0.05, motion.level.timeScale * motion.timeMultiplier)
        let effect = progress.apply(new, elapsed: Date().timeIntervalSince(stepStarted) / stretch, reduce: motion.reduce)
        switch effect {
        case .stepStarted:
            stepStarted = Date()
            finishRun += 1
            clearing = false
            reservedHeight = 0
        case .succeeded:
            connectedHere = true
            // El remate empieza ahora: la cifra corre desde la que se veía hasta 100.
            stepStarted = Date()
            playFinish()
        case .failed, .none:
            break
        }
    }

    /// El remate de un éxito REAL (ojo de diseño 14.1 y 14.2): 100, el tercer ✓ y «Todo listo» durante
    /// `finishHold`; después pasos, saldo y estado se apagan del todo (`clearBeforeSuccess`) y solo entonces salta el ✓
    /// de «conectado». No es un paso más: el trabajo ya terminó y solo se enseña. Un trámite nuevo lo retira.
    private func playFinish() {
        finishRun += 1
        let run = finishRun
        let hold = motion.seconds(BankConnectProgress.finishHold)
        let clear = motion.seconds(BankConnectProgress.clearBeforeSuccess)
        Task {
            try? await Task.sleep(for: .seconds(hold))
            guard run == finishRun, progress.finishing else { return }
            withAnimation(.easeOut(duration: clear)) { clearing = true }
            try? await Task.sleep(for: .seconds(clear))
            guard run == finishRun, progress.finishing else { return }
            // El relevo no cambia el alto (lote 3, I-1): «conectado» se monta dentro del hueco que dejaban los pasos y la
            // hoja de debajo no se mueve.
            reservedHeight = contentHeight
            progress.revealSuccess()
            clearing = false
            // Cuando «conectado» ya ha llegado entero (botones incluidos), el hueco sobrante se suelta con el muelle de la
            // hoja. Con Reducir movimiento no hay recorrido: el hueco se queda hasta «Listo» o «Ver movimientos».
            guard !motion.reduce else { return }
            try? await Task.sleep(for: .seconds(motion.seconds(1.0)))
            guard run == finishRun, progress.showsSuccess else { return }
            withAnimation(motion.animation(.sheet)) { reservedHeight = 0 }
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

    /// «Cancelar» la espera.
    private func cancelWaiting() {
        #if DEBUG
        if demoFlow != nil {
            demoRun += 1
            demoFlow?.handle(.cancel)
            return
        }
        #endif
        connector.cancelWebSession()
    }

    /// «Dejarlo» (y al salir de la pantalla con un fallo).
    private func resetTransientPhase() {
        #if DEBUG
        if demoFlow != nil {
            demoFlow?.handle(.reset)
            return
        }
        #endif
        connector.resetTransientPhase()
    }

    /// «Seguir» tras cortar la espera.
    private func resume() {
        #if DEBUG
        if demoFlow != nil {
            runDemoConnectScript()
            return
        }
        #endif
        Task { await connector.resume() }
    }

    private func dismissSuccess() {
        finishRun += 1
        clearing = false
        reservedHeight = 0
        progress.dismissSuccess()
    }

    #if DEBUG
    /// Hace de banco en la demo: manda a una `ConnectFlow` los eventos de verdad con `-MiBancoDemoConnectStep` segundos
    /// entre ellos (abrir, banco abierto, vuelta válida, conectado; o, con `-MiBancoDemoConnectFails`, un fallo mientras
    /// se espera al banco). Su fase entra por el mismo sitio que la del conector; la pantalla (pasos, porcentaje, éxito,
    /// fallo, esqueleto) es la de verdad.
    private func runDemoConnectScript() {
        var flow = demoFlow ?? ConnectFlow()
        guard !flow.phase.isActive else { return }
        flow.handle(.start(bank))
        demoFlow = flow
        demoRun += 1
        let run = demoRun
        let target = bank
        Task {
            let wait = DemoMode.connectScriptStepSeconds
            try? await Task.sleep(for: .seconds(wait))
            guard run == demoRun else { return }
            demoFlow?.handle(.webOpened(target))
            try? await Task.sleep(for: .seconds(wait))
            guard run == demoRun else { return }
            if DemoMode.connectScriptFails {
                demoFlow?.handle(.failed(target, ConnectMessage.tooSlow))
                return
            }
            demoFlow?.handle(.callback(.valid(target)))
            try? await Task.sleep(for: .seconds(wait))
            guard run == demoRun else { return }
            demoFirstFill = true
            demoFlow?.handle(.succeeded(target))
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
    /// Se dibujan con `BankMovementEntry` (mismas filas que Inicio, pero con máscara con el ojo cerrado).
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
                resetTransientPhase()
            }
        }
        .onChange(of: stage) { _, new in stageChanged(to: new) }
        .sensoryFeedback(Haptics.error, trigger: errorTick)
        .onAppear {
            #if DEBUG
            if DemoMode.requestsFlightOnOpen, flight?.request == nil {
                flight?.request = CardFlight.Request(bank: bank, card: AccountCard(bank: bank), source: .zero)
            }
            let demoImport = DemoMode.opensStatementImport || (DemoMode.importsOnBankOpen && bank == .rev)
            if DemoMode.isActive && demoImport && !didShowDemoImport && importPreview == nil {
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
                    // Una petición que nadie aterrizó ni limpió no debe hacer esperar la próxima apertura (menor m-8):
                    // si sigue siendo la misma y sin aterrizar, se retira.
                    if flight?.request == request, flight?.landed != true { flight?.request = nil }
                }
            }
            // La pantalla se abre con el trámite ya en marcha (se volvió a ella a mitad): se apunta su paso.
            if case .step = stage, progress.percent == nil { stageChanged(to: stage) }
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

                if progress.showsSuccess {
                    BankConnectedFlash(bank: bank, status: lines.primary, balanceCents: balance?.cents,
                                       onShowMovements: {
                                           dismissSuccess()
                                           scroll.dockRequests += 1
                                       }, onDone: dismissSuccess)
                        .padding(.top, 18)
                        // Entra sin fundido de conjunto: el ✓, el título y el saldo llegan cada uno con su tiempo (un
                        // fundido de todo dejaba la cabecera vacía un par de fotogramas, lote 3 m-2).
                        .transition(.asymmetric(insertion: .identity, removal: .opacity))
                } else {
                    Group {
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
                    // Tras el remate se apaga del todo antes de que salte el ✓ (nunca el ✓ sobre el saldo a medias).
                    .opacity(clearing ? 0 : 1)
                    .allowsHitTesting(!clearing)
                }
            }
            // Donde aterriza la tarjeta que vuela desde Inicio.
            .cardFlightDestination()

            if !progress.showsSuccess {
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
                .opacity(clearing ? 0 : 1)
                // Mientras se apaga ya no se toca nada (lote 3, m-12).
                .allowsHitTesting(!clearing)
                .motionEntrance(4)
                .fadesWithBankHeader()
            }
        }
        // El alto con los pasos a la vista; «conectado» lo reserva al relevarlos (lote 3, I-1).
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            if !progress.showsSuccess { contentHeight = height }
        }
        .frame(minHeight: reservedHeight, alignment: .top)
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 26)
        .animation(motion.calmAnimation(.enter), value: progress.showsSuccess)
        .assemblesOnFirstAppear()
    }

    @ViewBuilder
    private var phaseRows: some View {
        if let shown = shownProgress, !needsResumeForThisBank {
            VStack(alignment: .leading, spacing: 14) {
                // Durante el remate (solo tras el éxito real) los tres pasos están hechos y la línea dice «Todo listo».
                StepperProgress(steps: BankConnectStage.steps, current: shown.step, finished: progress.finishing,
                                caption: progress.caption(for: stage, bankName: bank.displayName), percent: shown,
                                // El primer instante de un paso, antes de apuntarlo, cuenta desde ahora (menor m-4).
                                since: progress.percent == nil ? Date() : stepStarted,
                                spins: true, identifier: "bank-steps")
                    // Los títulos de los extremos sobresalen de su nodo.
                    .padding(.horizontal, 30)
                    .padding(.top, 4)

                if let failed = failedMessageForThisBank {
                    failedRows(failed)
                } else {
                    // «Cancelar» solo se puede tocar abriendo o esperando al banco. Después se apaga en 0,12 s pero su
                    // hueco se queda hasta el final de los pasos: nada de lo de debajo sube de golpe (ojo de diseño 14.3).
                    let cancellable = stage.canCancel
                    Button {
                        cancelWaiting()
                    } label: {
                        Text("Cancelar")
                            .titan(.option)
                            .foregroundStyle(Theme.label2)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Theme.raised, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                    .disabled(!cancellable)
                    .opacity(cancellable ? 1 : 0)
                    .allowsHitTesting(cancellable)
                    .accessibilityHidden(!cancellable)
                    .accessibilityIdentifier(cancellable ? "bank-cancel-wait" : "")
                    .animation(.easeOut(duration: motion.seconds(0.12)), value: cancellable)
                }
            }
        } else if needsResumeForThisBank {
            VStack(alignment: .leading, spacing: 12) {
                Text("¿Ya lo has aprobado en la app de \(bank.displayName)?")
                    .titan(.option)
                    .foregroundStyle(Theme.label)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        resume()
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
                    resetTransientPhase()
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
                resetTransientPhase()
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
        if progress.showsStartActions(for: stage) {
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
                .fadesNearDock()
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
                        .transition(listSwap)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            BankMovementEntry(entry: entry, logoDomain: logoDomain(entry), onOpen: openMovement)
                                .motionEntrance(index)
                        }
                    }
                    // Cada vez que llegan las filas (también tras el esqueleto) entran una tras otra.
                    .assemblesOnFirstAppear()
                    .transition(listSwap)
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

    /// Filas ↔ esqueleto en dos tiempos (ojo de diseño 14.5): lo que se va se apaga en 0,12 s y solo entonces entra lo
    /// nuevo; nunca texto con fichas grises cruzándolo. (En la app el esqueleto solo sale con la lista VACÍA: primera
    /// conexión. La demo lo fuerza sobre una lista con filas para poder grabarlo.)
    private var listSwap: AnyTransition {
        let out = motion.seconds(0.12)
        return .asymmetric(insertion: .opacity.animation(.easeOut(duration: motion.seconds(0.2)).delay(out)),
                           removal: .opacity.animation(.easeOut(duration: out)))
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
