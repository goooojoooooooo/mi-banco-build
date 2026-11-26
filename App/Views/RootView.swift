import SwiftUI
import UniformTypeIdentifiers
import MiBancoCore

/// Barra de pestañas del sistema: en iOS 26+ es Liquid Glass (y se encoge al bajar la lista); en iOS 18–25,
/// la barra estándar. Nunca se le pone un fondo propio.
struct RootView: View {
    let model: LedgerModel
    let portfolio: PortfolioModel
    let accountBook: AccountBookModel
    let briefing: BriefingModel
    let speaker: BriefingSpeaker
    /// Con el bloqueo delante, Inicio no suena ni habla aunque llegue un movimiento.
    var isLocked = false
    /// Sube al arrancar y al desbloquear: Inicio se monta por capas y la barra llega la última.
    var revealToken = 0
    /// C6: el aviso dentro de la app que deja enseñar la carcasa ahora (`ShellState.shownBanner`; nil con el bloqueo,
    /// fundiéndose o fuera de primer plano), y cómo pedirlo y darlo por ido.
    var bannerID: Int? = nil
    var requestBanner: () -> Void = {}
    var dismissBanner: (Int) -> Void = { _ in }
    @State private var tab: AppTab = .home
    @State private var settingsFocus: BankID?
    @State private var settingsScroll: String?
    @State private var openAccountsRequest = false
    @State private var openBankRequest: BankID?
    @State private var openBudgetsRequest = false
    @State private var selectHomeCard: AccountCard?
    /// La única hoja de la app: un movimiento, una posición, mover dinero, el resumen/asistente, compartir o restaurar.
    @State private var sheet: RootSheet?
    /// Único selector de archivos de la app (copia de seguridad o extracto de Trade Republic); se cierra al bloquear.
    @State private var importing = false
    @State private var importKind: ImportKind = .backup
    @State private var importNotice: String?
    /// Sube al restaurar: Inicio se vuelve a montar con lo restaurado.
    @State private var restoreToken = 0
    /// Sube al terminar la bienvenida: Inicio se monta por capas (Tarea 12).
    @State private var onboardingRevealToken = 0
    /// Bloqueo y primer plano en vivo, para los cierres que llevan una copia de esta vista (ver `PresentationGate`).
    @State private var gate = PresentationGate()
    @State private var noticeTask: Task<Void, Never>?
    /// La espera de 250 ms antes de abrir el detalle de un aviso tocado: se cancela al cerrar todo.
    @State private var routeTask: Task<Void, Never>?
    /// Temporizador del resumen diario al arrancar o activar la app: se cancela al bloquear o salir.
    @State private var briefingTask: Task<Void, Never>?
    /// Transición diferida (350 ms) desde una acción del resumen hacia otra hoja (`moveMoney` / `movement`).
    @State private var briefingActionTask: Task<Void, Never>?
    /// Si se entró tocando un aviso de movimiento o de Avisos, el aviso gana y el resumen espera a la siguiente activación.
    @State private var suppressBriefingForActivation = false
    /// U80 (U37): el dueño tocó el aviso de la mañana y el resumen aún no se ha podido abrir (arranque en frío, bloqueo,
    /// una conexión a medias…). La siguiente comprobación del resumen lo abre; una comprobación posterior no lo pierde.
    @State private var briefingRouteWaiting = false
    /// Hoja de un movimiento abierta desde Avisos o desde un aviso tocado.
    private var detail: DetailRoute? {
        get { if case .movement(let route) = sheet { route } else { nil } }
        nonmutating set {
            // Toda hoja nueva pasa por el estado VIVO (`gate`): esta copia de la vista puede ser de antes.
            if let newValue { if gate.canPresent { sheet = .movement(newValue) } } else if case .movement = sheet { sheet = nil }
        }
    }
    @State private var pendingDelete: UUID?
    @State private var seen = SeenInsights()
    /// Borrar un movimiento falló: aviso breve arriba (sin modal) y háptica de error.
    @State private var deleteFailed = false
    @State private var deleteErrorTick = 0
    @Namespace private var zoom
    /// Costuras de movimiento (F1): marcos que apuntan las vistas para el vuelo de tarjeta y el detalle
    /// (`LaunchAnchor` lo crea `AppShellView`, por encima del bloqueo y del telón).
    @State private var cardFlight = CardFlight()
    /// C8 / 9.5: el banco abierto desde el abanico de Inicio, encima de Inicio (sin cambiar de pestaña).
    @State private var bankOverHome: BankID?
    @State private var tabEntrance = TabEntrance()
    @State private var detailAmountFrames = DetailAmountFrames()
    /// T1: la pestaña de antes del último cambio, cuántos cambios ha habido y hacia dónde fue el último.
    @State private var lastTab: AppTab = .home
    @State private var tabChanges = 0
    @State private var tabDirection = 1
    /// C6: la llegada que enseña el aviso dentro de la app, y el número de aviso que le dio la carcasa.
    @State private var bannerArrival: Arrival?
    @State private var bannerFor: Int?
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.motion) private var motion
    private var router: AlertRouter { AlertRouter.shared }

    var body: some View {
        let warnings = model.snapshot.warningInsightIDs
        let activeRevealToken = revealToken + onboardingRevealToken
        tabsOrWelcome(activeRevealToken: activeRevealToken, warnings: warnings)
        // Para las pantallas: la hoja única abierta y el estado de la carcasa (bloqueo, montaje por capas).
        .environment(\.singleSheetOpen, sheet != nil)
        .environment(\.shellReveal, ShellReveal(locked: isLocked, token: activeRevealToken))
        .tint(Theme.label)
        // C6: el aviso dentro de la app, arriba, por encima de las pestañas y por debajo de la hoja única (que es una
        // presentación aparte) y del bloqueo (otra capa de la carcasa, más alta). Solo si la carcasa lo deja.
        .overlay(alignment: .top) {
            if let id = bannerID, let arrival = bannerArrival, bannerFor == id {
                InAppBanner(
                    arrival: arrival,
                    left: model.snapshot.balanceAfter[arrival.id],
                    onOpen: {
                        dismissBanner(id)
                        openDetail(arrival.id)
                    },
                    onNotMine: { markNotMine(arrival.id, banner: id) },
                    onFinished: { dismissBanner(id) })
                    .id(id)
                    .transition(.identity)
            }
        }
        .environment(\.presentationGate, gate)
        // La única hoja de la app. Se cierra al bloquear y en cuanto la app deja de estar activa (selector de apps,
        // segundo plano): nunca queda encima del bloqueo ni en la captura del selector, y no se vuelve a abrir sola.
        .sheet(item: $sheet, onDismiss: deletePending) { item in sheetContent(item) }
        // Único selector de archivos de la app: se cierra como la hoja (nunca queda encima del bloqueo).
        .fileImporter(isPresented: $importing, allowedContentTypes: allowedImportTypes) { result in
            handleImport(result)
        }
        .overlay(alignment: .top) {
            if let importNotice {
                Text(importNotice)
                    .titan(.meta)
                    .foregroundStyle(Theme.warning)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.raised, in: Capsule())
                    .padding(.top, 8)
                    .transition(.opacity)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .task { BackupService.sweep() }
        .onAppear {
            gate.isLocked = isLocked
            gate.isActive = isForeground
        }
        .onChange(of: scenePhase) { _, phase in
            gate.isActive = phase == .active || demoKeepsSheet
            if !(phase == .active || demoKeepsSheet) {
                closeEverything()
            } else if phase == .active && !isLocked {
                scheduleBriefingCheck(delay: .milliseconds(600))
            }
        }
        .onChange(of: revealToken) { _, _ in
            guard !isLocked else { return }
            scheduleBriefingCheck(delay: reduceMotion ? .milliseconds(300) : .milliseconds(1_300))
        }
        .onChange(of: BankConnector.shared.isActive) { old, active in
            if old && !active && !isLocked && scenePhase == .active {
                scheduleBriefingCheck(delay: .milliseconds(600))
            }
        }
        // Red de seguridad: si por cualquier camino sube una hoja (o el selector) con el bloqueo puesto o fuera de
        // primer plano, se cierra al instante y se borra el fichero temporal.
        .onChange(of: sheet?.id) { _, id in
            if id != nil && (isLocked || !isForeground || !gate.canPresent) { closeEverything() }
        }
        .onChange(of: importing) { _, on in
            if on && (isLocked || scenePhase != .active || !gate.canPresent) { importing = false }
        }
        .overlay(alignment: .top) {
            if deleteFailed {
                Text("No se pudo borrar el movimiento. Inténtalo de nuevo.")
                    .titan(.meta)
                    .foregroundStyle(Theme.warning)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.raised, in: Capsule())
                    .padding(.top, 8)
                    .transition(.opacity)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .sensoryFeedback(.error, trigger: deleteErrorTick)
        // Entrar en Avisos (o ver avisos nuevos estando en ella) los da por vistos: la insignia se va.
        .onChange(of: tab) { old, new in
            if new == .alerts && !isLocked { seen.markSeen(warnings) }
            // T1: la entrada de la pestaña ya empezó en el mismo instante del cambio (`entrance(for:)`); aquí solo se
            // fija, sin cambiar su valor, para el siguiente cambio.
            tabDirection = Self.direction(from: old, to: new)
            tabChanges += 1
            lastTab = new
        }
        .onChange(of: warnings) { _, new in
            if tab == .alerts && !isLocked { seen.markSeen(new) }
        }
        // Un aviso tocado: se aplica en cuanto no hay bloqueo delante (nunca se abre una hoja encima del bloqueo).
        .onChange(of: router.pending) { _, _ in applyRoute() }
        // C6: un movimiento que llega con la app delante y en OTRA pestaña (en Inicio ya lo cuenta Inicio), sin la hoja
        // abierta: se pide el aviso. La carcasa decide si se puede enseñar (nunca con el bloqueo ni fuera de primer plano).
        .onChange(of: model.arrival) { _, arrival in
            #if DEBUG
            // Para las pruebas: cuántos pagos han llegado y cuántos con el bloqueo delante.
            if arrival != nil {
                LaunchProbe.shared.arrivals += 1
                if isLocked { LaunchProbe.shared.arrivalsUnderLock += 1 }
            }
            #endif
            guard let arrival, tab != .home, sheet == nil, !isLocked, scenePhase == .active else { return }
            bannerArrival = arrival
            requestBanner()
        }
        .onChange(of: bannerID) { old, new in
            // El número del aviso que acaba de pedirse es el de esta llegada.
            if let new, new != old, bannerArrival != nil { bannerFor = new }
        }
        .onChange(of: isLocked) { _, locked in
            gate.isLocked = locked
            if locked {
                closeEverything()
            } else {
                applyRoute()
                if tab == .alerts { seen.markSeen(warnings) }
            }
        }
        .onAppear(perform: applyRoute)
        #if DEBUG
        .onAppear(perform: applyDemoTab)
        .modifier(DemoRootTasks(tab: $tab, sheet: $sheet))
        #endif
        // Costuras de movimiento (F1): por fuera de todo, para que también las vean la hoja única y las capas.
        .environment(\.cardFlight, cardFlight)
        .environment(\.tabEntrance, tabEntrance)
        .environment(\.detailAmountFrames, detailAmountFrames)
    }

    /// El contenido de la hoja única. Aparte de `body` para que el compilador pueda con él.
    @ViewBuilder private func sheetContent(_ item: RootSheet) -> some View {
        switch item {
        case .movement(let route):
            MovementDetailSheet(model: model, id: route.id, amountOrigin: route.amountOrigin) { id in
                pendingDelete = id
                detail = nil
            }
            .modifier(ZoomFromRow(route: route, namespace: zoom))
        case .position(let instrument):
            PositionDetailSheet(portfolio: portfolio, instrument: instrument)
        case .moveMoney(let request):
            MoveMoneySheet(model: model, accountBook: accountBook, request: request)
        case .briefing:
            BriefingSheet(
                model: model,
                portfolio: portfolio,
                accountBook: accountBook,
                briefingModel: briefing,
                speaker: speaker,
                onAction: handleBriefingAction
            )
        case .share(let share):
            ShareSheet(item: share, onFinish: { sheet = nil })
                .ignoresSafeArea()
                .presentationDetents([.medium, .large])
                .onDisappear { if let url = share.fileURL { BackupService.remove(url) } }
        case .restore(let preview):
            RestoreConfirmView(preview: preview, restore: { try restoreBackup(preview.file) }, finished: finishRestore)
        case .confirmDisconnect(let bank):
            BankConfirmSheet(
                title: "Desconectar \(bank.displayName)",
                message: "Se dejan de leer sus movimientos. Lo que ya tienes se queda.",
                confirmTitle: "Desconectar",
                onConfirm: {
                    sheet = nil
                    Task { await BankConnector.shared.disconnect(bank) }
                },
                onCancel: { sheet = nil }
            )
        case .confirmForget:
            BankConfirmSheet(
                title: "Olvidar clave y conexiones",
                message: "Se borran la clave de Enable Banking y las sesiones de este iPhone. Tus movimientos se quedan.",
                confirmTitle: "Olvidar clave y conexiones",
                onConfirm: {
                    sheet = nil
                    Task {
                        await BankingCredentials.forgetEverything()
                        model.reload()
                    }
                },
                onCancel: { sheet = nil }
            )
        }
    }

    /// La bienvenida (primera vez) o las pestañas. Aparte de `body` para que el compilador pueda con él.
    @ViewBuilder private func tabsOrWelcome(activeRevealToken: Int, warnings: [String]) -> some View {
        ZStack {
            if model.needsOnboarding {
                OnboardingView(model: model, onFinish: completeOnboarding)
                    .transition(.opacity)
            } else {
                TabView(selection: $tab) {
                    Tab("Inicio", systemImage: "house", value: AppTab.home) {
                        HomeView(model: model, portfolio: portfolio, accountBook: accountBook,
                                 isVisible: tab == .home && !isLocked,
                                 revealToken: activeRevealToken, zoom: zoom,
                                 detailOpen: sheet != nil,
                                 openDetail: { openDetail($0, zooms: true) },
                                 openPosition: openPosition,
                                 openMoveMoney: openMoveMoney,
                                 openBriefing: openManualBriefing,
                                 shareText: shareText,
                                 openSettings: openSettings,
                                 openBankSettings: openBankSettings,
                                 openInvestmentsSettings: openInvestmentsSettings,
                                 openAccounts: openAccounts,
                                 selectCardRequest: $selectHomeCard)
                            .id(restoreToken)
                            .tabContentEntrance()
                            .environment(\.tabEntrance, entrance(for: .home))
                    }
                    Tab("Gasto", systemImage: "chart.bar", value: AppTab.spending) {
                        SpendingView(model: model, accountBook: accountBook, isVisible: tab == .spending && !isLocked,
                                     openDetail: { openDetail($0) }, openMoveMoney: openMoveMoney,
                                     openBudgetsRequest: $openBudgetsRequest)
                            .modifier(FadedTabContent(entrance: entrance(for: .spending)))
                    }
                    Tab("Avisos", systemImage: "bell", value: AppTab.alerts) {
                        AlertsView(model: model, isVisible: tab == .alerts && !isLocked, onOpen: { openDetail($0) },
                                   onMorningRuleChanged: rescheduleMorningReminder)
                            .modifier(FadedTabContent(entrance: entrance(for: .alerts)))
                    }
                    .badge(tab == .alerts ? 0 : seen.unseenCount(of: warnings))
                    Tab("Ajustes", systemImage: "gearshape", value: AppTab.settings) {
                        SettingsScrollHost(scrollRequest: $settingsScroll) {
                            SettingsView(model: model, portfolio: portfolio, accountBook: accountBook, briefing: briefing,
                                         focusRequest: $settingsFocus, openAccountsRequest: $openAccountsRequest,
                                         openBankRequest: $openBankRequest,
                                         present: present,
                                         requestImport: startImport,
                                         importBackup: { startImport(.backup) },
                                         importTradeRepublic: { startImport(.tradeRepublic) })
                        }
                        .modifier(FadedTabContent(entrance: entrance(for: .settings)))
                    }
                }
                .modifier(MinimizesTabBarOnScroll())
                .overlay(alignment: .bottom) {
                    TabBarCurtain(token: activeRevealToken)
                }
                // C8 / 9.5: el banco abierto desde el abanico va ENCIMA de Inicio (la pestaña marcada no cambia) y la
                // tarjeta vuela hasta su cabecera.
                .overlay { bankOverHomeLayer }
                .overlay { CardFlightLayer(flight: cardFlight, blocked: flightBlocked) }
                .transition(.opacity)
            }
        }
    }

    /// T1: la entrada de cada pestaña. La elegida lleva un `token` nuevo DESDE el instante en que se elige (se calcula
    /// aquí, en `body`, con la pestaña de antes: no espera al `onChange`, así que no hay ni un fotograma de la pestaña
    /// quieta antes de entrar), y su valor no cambia cuando el `onChange` lo apunta. Las demás no se mueven. Al abrir
    /// la app, `token` 0: nada entra. Mientras vuela una tarjeta (`tabEntrance.suppressed`), tampoco.
    private func entrance(for candidate: AppTab) -> TabEntrance {
        let changing = tab != lastTab
        guard candidate == tab else { return TabEntrance(token: 0, direction: 1, suppressed: true) }
        return TabEntrance(
            token: tabChanges + (changing ? 1 : 0),
            direction: changing ? Self.direction(from: lastTab, to: tab) : tabDirection,
            suppressed: tabEntrance.suppressed || isLocked)
    }

    /// 1 si la pestaña nueva está a la derecha de la anterior en la barra; −1 si a la izquierda.
    private static func direction(from old: AppTab, to new: AppTab) -> Int {
        let order: [AppTab] = [.home, .spending, .alerts, .settings]
        return (order.firstIndex(of: new) ?? 0) >= (order.firstIndex(of: old) ?? 0) ? 1 : -1
    }

    /// Primer plano a efectos de la hoja de un movimiento. En Release es exactamente `scenePhase == .active`.
    private var isForeground: Bool { scenePhase == .active || demoKeepsSheet }

    /// Solo DEBUG, demo de capturas con la hoja abierta por argumento: en el simulador de CI la fase de escena parpadea
    /// y cerraría la hoja. El bloqueo sigue mandando (`gate.isLocked`). En Release es siempre `false`.
    private var demoKeepsSheet: Bool {
        #if DEBUG
        DemoMode.isActive && (DemoMode.opensDetail || DemoMode.opensPosition || DemoMode.demoMoveStep != nil || DemoMode.briefingMode != nil)
        #else
        false
        #endif
    }

    private var allowedImportTypes: [UTType] {
        switch importKind {
        case .backup: [.json]
        case .tradeRepublic: [.commaSeparatedText, .plainText]
        case .statement: [.commaSeparatedText, .plainText, .data]
        case .bankKey: [UTType(filenameExtension: "pem") ?? .data, .data]
        }
    }

    /// Hoja y selector de archivos fuera: al bloquear y al salir de primer plano.
    private func closeEverything() {
        if case .share(let share) = sheet, let url = share.fileURL { BackupService.remove(url) }
        gate.generation += 1
        routeTask?.cancel()
        routeTask = nil
        briefingTask?.cancel()
        briefingTask = nil
        briefingActionTask?.cancel()
        briefingActionTask = nil
        suppressBriefingForActivation = false
        speaker.stop()
        sheet = nil
        bankOverHome = nil
        importing = false
        importKind = .backup
    }

    /// Las hojas nuevas (compartir, restaurar) nunca suben con el bloqueo delante ni fuera de primer plano.
    /// El selector de archivos, también con el estado vivo.
    private func startImport(_ kind: ImportKind) {
        guard gate.canPresent, !isLocked, scenePhase == .active, !importing else { return }
        importKind = kind
        importing = true
    }

    private func present(_ item: RootSheet) {
        // `gate` es vivo; `isLocked` y `scenePhase` de esta copia de la vista pueden ser de antes del toque.
        guard gate.canPresent, !isLocked, scenePhase == .active else {
            if case .share(let share) = item, let url = share.fileURL { BackupService.remove(url) }
            return
        }
        sheet = item
    }

    private func handleImport(_ result: Result<URL, Error>) {
        let kind = importKind
        importKind = .backup
        guard gate.canPresent, !isLocked, scenePhase == .active, case .success(let url) = result else { return }
        switch kind {
        case .backup:
            do {
                sheet = .restore(try BackupService.preview(url, current: model.state))
            } catch BackupError.notABackup {
                showImportNotice("Ese fichero no es una copia de \(AppIdentity.displayName).")
            } catch BackupError.newerVersion {
                showImportNotice("Esa copia es de una versión más nueva de \(AppIdentity.displayName).")
            } catch {
                showImportNotice("No se pudo leer ese fichero.")
            }
        case .tradeRepublic:
            let generation = gate.generation
            Task {
                do {
                    let rows = try await Task.detached(priority: .userInitiated) {
                        try PortfolioModel.readTradeRepublicRows(from: url)
                    }.value
                    guard gate.generation == generation, gate.canPresent else { return }
                    _ = try portfolio.mergeRows(rows)
                    if preferences.pricesEnabled {
                        await portfolio.refreshPrices(force: true)
                    }
                } catch let error as PortfolioImportError {
                    guard gate.generation == generation, gate.canPresent else { return }
                    portfolio.recordImportError(portfolioImportMessage(error.failure))
                } catch {
                    guard gate.generation == generation, gate.canPresent else { return }
                    portfolio.recordImportError(portfolioImportMessage(.notTradeRepublic))
                }
            }
        case .statement(_, let onPick):
            onPick(.success(url))
        case .bankKey(let onPick):
            onPick(.success(url))
        }
    }

    private func restoreBackup(_ file: BackupFile) throws {
        // Guardamos la copia temporal de la cartera y solo la promocionamos tras restaurar bien el libro (U57).
        var tempSaveError: Error?
        var ledgerError: Error?
        do {
            try restorePortfolioSafetyCopyPlan(
                saveTemp: {
                    do {
                        try portfolio.saveTempSafetyCopy()
                    } catch {
                        tempSaveError = error
                        throw error
                    }
                },
                restoreLedger: {
                    do {
                        try model.restore(file)
                    } catch {
                        ledgerError = error
                        throw error
                    }
                },
                promoteTemp: {
                    try portfolio.promoteTempSafetyCopy()
                },
                removeTemp: {
                    portfolio.removeTempSafetyCopy()
                }
            )
        } catch {
            if tempSaveError != nil {
                throw RestoreError.safetyCopyFailed
            }
            if let ledgerError {
                throw ledgerError
            }
            // El libro ya se escribió en disco: nunca decir al usuario que sus datos no han cambiado.
            throw RestoreError.reloadFailed
        }
        let nextPortfolio = portfolioAfterRestore(current: portfolio.portfolio, backup: file)
        if nextPortfolio != portfolio.portfolio {
            do {
                try portfolio.replace(with: nextPortfolio)
            } catch {
                // El libro ya se escribió en disco: nunca decir al usuario que sus datos no han cambiado.
                throw RestoreError.reloadFailed
            }
        }
    }

    private func showImportNotice(_ text: String) {
        deleteErrorTick += 1
        withAnimation(reduceMotion ? nil : Theme.Motion.quick) { importNotice = text }
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { importNotice = nil }
        }
    }

    /// Tras restaurar: la hoja se cierra y Inicio se vuelve a montar con lo restaurado.
    private func finishRestore() {
        sheet = nil
        restoreToken += 1
        rescheduleMorningReminder()
    }

    private func openSettings(_ bank: BankID?) {
        settingsFocus = bank
        tab = .settings
    }

    /// «No es mío» desde el aviso dentro de la app. Si no se guarda, el aviso se queda (y lo dice): no se va como si se
    /// hubiera hecho.
    private func markNotMine(_ movement: UUID, banner id: Int) -> Bool {
        #if DEBUG
        if DemoMode.notMineFails { return false }
        #endif
        do {
            try model.setFlaggedNotMine(true, for: movement)
        } catch {
            return false
        }
        dismissBanner(id)
        return true
    }

    private func openBankSettings(_ bank: BankID) {
        // 9.5: si se llega volando desde el abanico (hay un vuelo pedido hacia este banco), la pantalla del banco se
        // abre encima de Inicio y la pestaña marcada no cambia. Desde cualquier otro sitio, en Ajustes como siempre.
        if tab == .home, cardFlight.request?.bank == bank {
            withAnimation(motion.reduce ? motion.fade : nil) { bankOverHome = bank }
            return
        }
        openBankRequest = bank
        tab = .settings
    }

    /// No se puede volar: bloqueo, fuera de primer plano o la hoja única abierta (la tarjeta se queda como aterrizada).
    private var flightBlocked: Bool { isLocked || scenePhase != .active || sheet != nil }

    /// La pantalla del banco encima de Inicio, con su propia pila de navegación y «Inicio» para volver.
    @ViewBuilder private var bankOverHomeLayer: some View {
        if let bank = bankOverHome {
            NavigationStack {
                BankLinkView(model: model, portfolio: portfolio, bank: bank, present: present, requestImport: startImport)
                    .navigationBarBackButtonHidden()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                withAnimation(motion.fade) { bankOverHome = nil }
                            } label: {
                                Label("Inicio", systemImage: "chevron.left")
                            }
                            .accessibilityIdentifier("bank-over-home-back")
                        }
                    }
            }
            .background(Theme.canvas.ignoresSafeArea())
            .transition(.opacity)
        }
    }

    private func openInvestmentsSettings() {
        settingsScroll = InvestmentsSection.scrollID
        tab = .settings
    }

    private func openAccounts() {
        openAccountsRequest = true
        tab = .settings
    }

    /// Nunca con el bloqueo delante ni con la app fuera de primer plano.
    private func openDetail(_ id: UUID, zooms: Bool = false) {
        guard gate.canPresent, !isLocked, isForeground, model.movement(id) != nil else { return }
        // D1: el marco del importe de la fila tocada se lee AQUI, en el toque (nunca en un `body`). Solo desde las
        // filas de Inicio (las que lo apuntan y las que abren con zoom).
        detail = DetailRoute(id: id, zooms: zooms, amountOrigin: zooms ? detailAmountFrames.frame(for: id) : nil)
    }

    private func openPosition(_ instrument: String) {
        guard gate.canPresent, !isLocked, isForeground, portfolio.positionValue(for: instrument) != nil else { return }
        sheet = .position(instrument)
    }

    private func openMoveMoney(_ request: MoveRequest) {
        guard gate.canPresent, !isLocked, isForeground else { return }
        sheet = .moveMoney(request)
    }

    private func shareText(_ text: String) {
        present(.share(ShareItem(text: text)))
    }

    private func applyRoute() {
        guard !isLocked, let route = router.pending else { return }
        router.pending = nil
        switch route.destination {
        case .home:
            briefingRouteWaiting = false
            suppressBriefingForActivation = true
            briefingTask?.cancel()
            briefingTask = nil
            tab = .home
        case .alerts:
            briefingRouteWaiting = false
            suppressBriefingForActivation = true
            briefingTask?.cancel()
            briefingTask = nil
            tab = .alerts
        case .briefing:
            suppressBriefingForActivation = false
            briefingRouteWaiting = true
            tab = .home
            scheduleBriefingRouteOpen()
        case .bank(let bank):
            briefingRouteWaiting = false
            suppressBriefingForActivation = true
            briefingTask?.cancel()
            briefingTask = nil
            openBankSettings(bank)
        }
        if let id = route.movementID {
            // Tras el cambio de pestaña, para que la hoja suba sobre la pantalla buena.
            routeTask?.cancel()
            routeTask = Task {
                defer { routeTask = nil }
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                openDetail(id)
            }
        }
    }

    // MARK: - Resumen diario y asistente Onyx

    private func scheduleBriefingCheck(delay: Duration) {
        guard !suppressBriefingForActivation, routeTask == nil, router.pending == nil else { return }
        briefingTask?.cancel()
        let gen = gate.generation
        briefingTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, gate.generation == gen else { return }
            considerBriefing()
            if briefingRouteWaiting && sheet == nil {
                openManualBriefing()
            }
        }
    }

    private func completeOnboarding(openBanksSettings: Bool) {
        briefing.markOnboardingCompleted()
        if openBanksSettings {
            tab = .settings
        }
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.unlock) {
            model.finishOnboarding()
            onboardingRevealToken += 1
        }
        rescheduleMorningReminder()
    }

    /// Al tocar el aviso de la mañana, abre el resumen incluso si hoy ya se vio (U37).
    private func scheduleBriefingRouteOpen() {
        briefingTask?.cancel()
        let gen = gate.generation
        briefingTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, gate.generation == gen else { return }
            considerBriefing()
            if sheet == nil {
                openManualBriefing()
            }
        }
    }

    private func considerBriefing() {
        guard gate.canPresent, !isLocked, isForeground, !model.needsOnboarding, sheet == nil, !importing,
              !BankConnector.shared.isActive,
              router.pending == nil, routeTask == nil, !suppressBriefingForActivation else { return }
        let now = AppClock.now
        guard let due = briefing.dueRecord(now: now) else { return }
        let isFirst = briefing.record == nil
        briefing.prepare(
            record: due,
            isFirst: isFirst,
            state: model.state,
            portfolio: portfolio.portfolioForBackup,
            book: accountBook.book,
            privateMode: preferences.privateMode,
            now: now
        )
        // Se guarda ANTES de presentar la hoja (tarea 9, Review Focus 2).
        briefing.markShown(due)
        // U82: si el dueño entró por el aviso de la mañana, este resumen ya lo atiende; que no vuelva a salir al volver a la app.
        briefingRouteWaiting = false
        sheet = .briefing(due)
        rescheduleMorningReminder()
    }

    private func openManualBriefing() {
        // U76 (B-M1): la misma guarda que `considerBriefing` (U58): nunca encima de la bienvenida ni de una conexión a medias,
        // tampoco cuando se entra por el aviso de la mañana.
        guard gate.canPresent, !isLocked, isForeground, !importing, sheet == nil, !model.needsOnboarding,
              !BankConnector.shared.isActive else { return }
        let now = AppClock.now
        let rec = briefing.manualRecord(now: now)
        let isFirst = briefing.record == nil
        briefing.prepare(
            record: rec,
            isFirst: isFirst,
            state: model.state,
            portfolio: portfolio.portfolioForBackup,
            book: accountBook.book,
            privateMode: preferences.privateMode,
            now: now
        )
        briefing.markShown(rec)
        briefingRouteWaiting = false
        sheet = .briefing(rec)
        rescheduleMorningReminder()
    }

    private func handleBriefingAction(_ action: BriefingAction) {
        speaker.stop()
        let gen = gate.generation
        sheet = nil
        switch action {
        case let .moveMoney(from, to, cents):
            briefingActionTask?.cancel()
            briefingActionTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled, gate.generation == gen, gate.canPresent, !isLocked, isForeground else { return }
                openMoveMoney(MoveRequest(from: from, target: .own(to), amountCents: cents))
            }
        case .openBankSettings(let bank):
            openBankSettings(bank)
        case .openBudgets:
            openBudgetsRequest = true
            tab = .spending
        case .openInvestments:
            selectHomeCard = .investments
            tab = .home
        case .openMovement(let id):
            briefingActionTask?.cancel()
            briefingActionTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled, gate.generation == gen, gate.canPresent, !isLocked, isForeground else { return }
                openDetail(id)
            }
        }
    }

    private func rescheduleMorningReminder() {
        let settings = model.state.alertSettings
        let shownToday = briefing.shownToday
        Task {
            await MorningBriefingNotifier.reschedule(settings: settings, shownToday: shownToday)
        }
    }

    /// Se borra al cerrarse la hoja, para que la fila se vaya a la vista.
    private func deletePending() {
        guard let id = pendingDelete else { return }
        pendingDelete = nil
        do {
            try withAnimation(reduceMotion ? nil : Theme.Motion.rowSettle) {
                try model.deleteMovement(id)
            }
        } catch {
            deleteErrorTick += 1
            withAnimation(reduceMotion ? nil : Theme.Motion.quick) { deleteFailed = true }
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation(.easeOut(duration: 0.3)) { deleteFailed = false }
            }
        }
    }

    #if DEBUG
    private func applyDemoTab() {
        guard DemoMode.isActive else { return }
        switch DemoMode.screen {
        case .home: tab = .home
        case .spending: tab = .spending
        case .alerts: tab = .alerts
        case .settings: tab = .settings
        }
        if DemoMode.opensRestorePreview {
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                if gate.canPresent { sheet = .restore(DemoMode.demoRestorePreview(currentCount: model.state.movements.count)) }
            }
        } else if let moveStep = DemoMode.demoMoveStep {
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                if gate.canPresent {
                    sheet = .moveMoney(MoveRequest(demoStep: moveStep))
                }
            }
        } else if DemoMode.demoRoute == "briefing" {
            // Simula entrar por el aviso de la mañana con el resumen de hoy ya visto (U37); con `-MiBancoDemoRouteUnseen`,
            // sin verlo, que es el caso normal del aviso de las 08:30 (U82).
            if !DemoMode.demoRouteUnseen {
                let now = AppClock.now
                briefing.markShown(BriefingRecord(shownAt: now, since: now))
            }
            if let delay = DemoMode.demoRouteDelaySeconds {
                // U76: el toque del aviso llega N segundos después (con una confirmación o una conexión ya abiertas).
                Task {
                    try? await Task.sleep(for: .seconds(delay))
                    router.pending = AlertRoute(destination: .briefing, movementID: nil)
                }
            } else {
                router.pending = AlertRoute(destination: .briefing, movementID: nil)
                applyRoute()
            }
        }
    }
    #endif
}

/// Qué fichero está eligiendo el selector único de archivos de `RootView` (U55).
enum ImportKind {
    case backup
    case tradeRepublic
    case statement(BankID, onPick: (Result<URL, Error>) -> Void)
    case bankKey(onPick: (Result<URL, Error>) -> Void)
}

/// Lo que puede enseñar la única hoja de la app. `RootView` es su único dueño (U55).
enum RootSheet: Identifiable {
    case movement(DetailRoute)
    case position(String)
    case moveMoney(MoveRequest)
    case briefing(BriefingRecord)
    case share(ShareItem)
    case restore(RestorePreview)
    case confirmDisconnect(BankID)
    case confirmForget

    var id: String {
        switch self {
        case .movement(let route): "movement-\(route.id)"
        case .position(let instrument): "position-\(instrument)"
        case .moveMoney(let request): "move-\(request.id)"
        case .briefing(let record): "briefing-\(record.shownAt.timeIntervalSince1970)"
        case .share(let item): "share-\(item.id)"
        case .restore(let preview): "restore-\(preview.id)"
        case .confirmDisconnect(let bank): "confirm-disconnect-\(bank.rawValue)"
        case .confirmForget: "confirm-forget"
        }
    }
}

/// Confirmación en hoja media de `RootView` para desconectar un banco u olvidar clave y conexiones (U55).
/// Vive en la única hoja de la app: se cierra al bloquear o salir y ningún resumen puede subir encima.
private struct BankConfirmSheet: View {
    let title: String
    let message: String
    let confirmTitle: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .titan(.sheetTitle)
                    .foregroundStyle(Theme.label)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .titan(.callout)
                    .foregroundStyle(Theme.label2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 12)

            VStack(spacing: 10) {
                Button(role: .destructive, action: onConfirm) {
                    Text(confirmTitle)
                        .titan(.option)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.canvas)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Theme.warning, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)

                Button(role: .cancel, action: onCancel) {
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
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.canvas.ignoresSafeArea())
        .overlay {
            if scenePhase != .active {
                Theme.canvas.ignoresSafeArea().accessibilityHidden(true)
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

/// Desde una fila de Inicio, la hoja sale con zoom desde el logo; desde Avisos o un aviso tocado, la subida normal.
private struct ZoomFromRow: ViewModifier {
    let route: DetailRoute
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if route.zooms {
            content.navigationTransition(.zoom(sourceID: route.id, in: namespace))
        } else {
            content
        }
    }
}

/// iOS 26+: la barra de cristal se recoge al bajar la lista y vuelve al subir.
private struct MinimizesTabBarOnScroll: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

/// En el montaje de Inicio la barra de pestañas llega la última: un velo negro sobre ella se aparta a los 0,6 s.
/// No intercepta toques; con Reducir movimiento no aparece.
/// La entrada de una pestaña y, debajo de la barra de cristal, el mismo negro con degradado que Inicio (lote final: lo
/// de debajo se funde en negro en vez de cortarse bajo el cristal). Un modificador aparte para que `body` se compile.
private struct FadedTabContent: ViewModifier {
    let entrance: TabEntrance

    func body(content: Content) -> some View {
        content
            .tabContentEntrance()
            .environment(\.tabEntrance, entrance)
            .overlay { UnderTabBarFade() }
    }
}

/// I-3 (ronda 1): el negro con degradado SOLO detrás de la barra de cristal (la zona segura de abajo de la pestaña), no
/// por encima: lo último de Gasto, Avisos y Ajustes, y el pie de sus pantallas empujadas, queda siempre entero por
/// encima de la barra, y el cristal solo tiene negro detrás. Fijo, no se toca y no existe para VoiceOver (en DEBUG
/// publica su marco, `tab-bar-fade`, para las pruebas).
private struct UnderTabBarFade: View {
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                LinearGradient(stops: [.init(color: Theme.canvas.opacity(0), location: 0),
                                       .init(color: Theme.canvas, location: 0.45)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: geo.safeAreaInsets.bottom)
                    #if DEBUG
                    .overlay {
                        Color.clear
                            .accessibilityElement()
                            .accessibilityIdentifier("tab-bar-fade")
                    }
                    #endif
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .allowsHitTesting(false)
    }
}

private struct TabBarCurtain: View {
    let token: Int
    @State private var covered = false
    @State private var mounted = false
    @State private var run = 0
    @Environment(\.motion) private var motion

    /// Cuándo empieza a destaparse la barra tras empezar el montaje (s a nivel Equilibrado): después de la tarjeta, el
    /// selector y las dos primeras filas, y ≥ 0,15 s después de que se haya ido el botón del bloqueo (ojo de diseño
    /// 3.2, 4.4, 5.1). Y lo que tarda en destaparse.
    static let lead = 0.45
    static let reveal = 0.3

    var body: some View {
        // Negro opaco desde 45 pt por encima del borde de la barra HASTA el borde de la pantalla (I-4, ronda 1: antes
        // se quedaba en el borde de la zona segura y asomaba el canto de la barra de cristal).
        // Solo existe mientras tapa o se destapa (`mounted`): una capa a pantalla completa, aun transparente y sin
        // toques, hace que la barra de cristal deje de contar como «tocable» para las pruebas (run 45840643996).
        ZStack {
            if mounted {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LinearGradient(stops: [.init(color: .black.opacity(0), location: 0), .init(color: .black, location: 0.3)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 150)
                    Color.black.frame(height: 80)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .opacity(covered ? 1 : 0)
            }
        }
        // M-10 (ronda 1): NO se puede bloquear así: la barra de cristal recibe los toques por encima de cualquier capa
        // de SwiftUI (run 45836401819: con el velo «tocable», la barra seguía tocándose y, en cambio, el velo a pantalla
        // completa estorbaba a lo de Inicio). El velo no recibe toques.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
            .onChange(of: token) { _, _ in
                // La barra de pestañas cierra el montaje: tapada desde el primer fotograma y destapada la última. Con
                // Reducir movimiento también (es un fundido, sin recorrido), con los tiempos de `\.motion`.
                mounted = true
                covered = true
                run += 1
            }
            .task(id: run) {
                guard run > 0 else { return }
                try? await Task.sleep(for: .seconds(motion.reduce ? motion.fadeDuration : motion.seconds(Self.lead)))
                guard !Task.isCancelled else { return }
                withAnimation(motion.reduce ? motion.fade : .easeOut(duration: motion.seconds(Self.reveal))) {
                    covered = false
                }
                #if DEBUG
                LaunchProbe.shared.tabBarUncoveredAt = Date().timeIntervalSince1970
                #endif
                try? await Task.sleep(for: .seconds(motion.reduce ? motion.fadeDuration : motion.seconds(Self.reveal)))
                guard !Task.isCancelled, !covered else { return }
                mounted = false
            }
            #if DEBUG
            .onChange(of: covered) { _, now in if now { LaunchProbe.shared.tabBarCoveredAt = Date().timeIntervalSince1970 } }
            #endif
    }
}

#if DEBUG
/// Solo demo de grabación: (1) cambia sola a Gasto (`-MiBancoDemoTabSwitch`) para grabar la entrada de la pestaña desde
/// antes del cambio; (2) m-4 (lote final): la hoja del movimiento se cierra sola a los `s` segundos de abrirse
/// (`-MiBancoDemoAutoCloseDetail`), para grabar el cierre desde ANTES (un toque de la prueba espera a que la app quede
/// quieta y la ráfaga empezaba con la hoja ya cerrada).
private struct DemoRootTasks: ViewModifier {
    @Binding var tab: AppTab
    @Binding var sheet: RootSheet?
    @Environment(AppPreferences.self) private var preferences

    func body(content: Content) -> some View {
        content
            .task {
                // Ronda 1 (kit m-4), solo grabación: el ojo se cierra solo a los `s` s (`-MiBancoDemoCloseEyeAfter`),
                // para grabar el cierre del ojo sobre una cifra que rueda desde ANTES del cambio.
                guard let seconds = DemoMode.closeEyeAfterSeconds else { return }
                LaunchProbe.shared.eyeClosesAt = Date().timeIntervalSince1970 + seconds
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                withAnimation { preferences.privateMode = true }
            }
            .task {
                guard let seconds = DemoMode.tabSwitchSeconds else { return }
                LaunchProbe.shared.tabSwitchAt = Date().timeIntervalSince1970 + seconds
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                tab = .spending
            }
            .task(id: sheet?.id) {
                guard let seconds = DemoMode.autoCloseDetailSeconds, let current = sheet?.id,
                      current.hasPrefix("movement-") else { return }
                // I-4 (ronda 1): cuándo se cerrará, para que la ráfaga empiece justo antes.
                LaunchProbe.shared.detailCloseAt = Date().timeIntervalSince1970 + seconds
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, sheet?.id == current else { return }
                sheet = nil
            }
    }
}
#endif
