import SwiftUI
import MiBancoCore

/// Barra de pestañas del sistema: en iOS 26+ es Liquid Glass (y se encoge al bajar la lista); en iOS 18–25,
/// la barra estándar. Nunca se le pone un fondo propio.
struct RootView: View {
    let model: LedgerModel
    /// Con el bloqueo delante, Inicio no suena ni habla aunque llegue un movimiento.
    var isLocked = false
    /// Sube al arrancar y al desbloquear: Inicio se monta por capas y la barra llega la última.
    var revealToken = 0
    @State private var tab: AppTab = .home
    @State private var settingsFocus: BankID?
    /// La única hoja de la app: un movimiento, la hoja de compartir o la confirmación de restaurar.
    @State private var sheet: RootSheet?
    /// Selector de archivos de "Restaurar una copia…" (se cierra igual que la hoja).
    @State private var importing = false
    @State private var importNotice: String?
    /// Sube al restaurar: Inicio se vuelve a montar con lo restaurado.
    @State private var restoreToken = 0
    /// Bloqueo y primer plano en vivo, para los cierres que llevan una copia de esta vista (ver `PresentationGate`).
    @State private var gate = PresentationGate()
    @State private var noticeTask: Task<Void, Never>?
    /// La espera de 250 ms antes de abrir el detalle de un aviso tocado: se cancela al cerrar todo.
    @State private var routeTask: Task<Void, Never>?
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private var router: AlertRouter { AlertRouter.shared }

    var body: some View {
        let warnings = model.snapshot.warningInsightIDs
        TabView(selection: $tab) {
            Tab("Inicio", systemImage: "house", value: AppTab.home) {
                HomeView(model: model, isVisible: tab == .home && !isLocked, revealToken: revealToken, zoom: zoom,
                         detailOpen: detail != nil, openDetail: { openDetail($0, zooms: true) }, openSettings: openSettings)
                    .id(restoreToken)
            }
            Tab("Gasto", systemImage: "chart.bar", value: AppTab.spending) {
                SpendingView(model: model, isVisible: tab == .spending && !isLocked, openDetail: { openDetail($0) })
            }
            Tab("Avisos", systemImage: "bell", value: AppTab.alerts) {
                AlertsView(model: model, isVisible: tab == .alerts && !isLocked, onOpen: { openDetail($0) })
            }
            .badge(tab == .alerts ? 0 : seen.unseenCount(of: warnings))
            Tab("Ajustes", systemImage: "gearshape", value: AppTab.settings) {
                SettingsScrollHost {
                    SettingsView(model: model, focusRequest: $settingsFocus, present: present, importBackup: startImport)
                }
            }
        }
        .tint(Theme.label)
        .environment(\.presentationGate, gate)
        .modifier(MinimizesTabBarOnScroll())
        .overlay(alignment: .bottom) {
            TabBarCurtain(token: revealToken)
        }
        // La única hoja de la app. Se cierra al bloquear y en cuanto la app deja de estar activa (selector de apps,
        // segundo plano): nunca queda encima del bloqueo ni en la captura del selector, y no se vuelve a abrir sola.
        .sheet(item: $sheet, onDismiss: deletePending) { item in
            switch item {
            case .movement(let route):
                MovementDetailSheet(model: model, id: route.id) { id in
                    pendingDelete = id
                    detail = nil
                }
                .modifier(ZoomFromRow(route: route, namespace: zoom))
            case .share(let share):
                ShareSheet(url: share.url, onFinish: { sheet = nil })
                    .ignoresSafeArea()
                    .presentationDetents([.medium, .large])
                    .onDisappear { BackupService.remove(share.url) }
            case .restore(let preview):
                RestoreConfirmView(preview: preview, restore: { try model.restore(preview.file) }, finished: finishRestore)
            }
        }
        // Selector de archivos para restaurar: se cierra como la hoja (nunca queda encima del bloqueo).
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
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
            gate.isActive = scenePhase == .active
        }
        .onChange(of: scenePhase) { _, phase in
            gate.isActive = phase == .active
            if phase != .active { closeEverything() }
        }
        // Red de seguridad: si por cualquier camino sube una hoja (o el selector) con el bloqueo puesto o fuera de
        // primer plano, se cierra al instante y se borra el fichero temporal.
        .onChange(of: sheet?.id) { _, id in
            if id != nil && (isLocked || scenePhase != .active || !gate.canPresent) { closeEverything() }
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
        .onChange(of: tab) { _, new in
            if new == .alerts && !isLocked { seen.markSeen(warnings) }
        }
        .onChange(of: warnings) { _, new in
            if tab == .alerts && !isLocked { seen.markSeen(new) }
        }
        // Un aviso tocado: se aplica en cuanto no hay bloqueo delante (nunca se abre una hoja encima del bloqueo).
        .onChange(of: router.pending) { _, _ in applyRoute() }
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
        #endif
    }

    /// Hoja y selector de archivos fuera: al bloquear y al salir de primer plano.
    private func closeEverything() {
        if case .share(let share) = sheet { BackupService.remove(share.url) }
        gate.generation += 1
        routeTask?.cancel()
        routeTask = nil
        sheet = nil
        importing = false
    }

    /// Las hojas nuevas (compartir, restaurar) nunca suben con el bloqueo delante ni fuera de primer plano.
    /// El selector de archivos, también con el estado vivo.
    private func startImport() {
        guard gate.canPresent, !isLocked, scenePhase == .active else { return }
        importing = true
    }

    private func present(_ item: RootSheet) {
        // `gate` es vivo; `isLocked` y `scenePhase` de esta copia de la vista pueden ser de antes del toque.
        guard gate.canPresent, !isLocked, scenePhase == .active else {
            if case .share(let share) = item { BackupService.remove(share.url) }
            return
        }
        sheet = item
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard gate.canPresent, !isLocked, scenePhase == .active, case .success(let url) = result else { return }
        do {
            sheet = .restore(try BackupService.preview(url, current: model.state))
        } catch BackupError.notABackup {
            showImportNotice("Ese fichero no es una copia de Mi Banco.")
        } catch BackupError.newerVersion {
            showImportNotice("Esa copia es de una versión más nueva de Mi Banco.")
        } catch {
            showImportNotice("No se pudo leer ese fichero.")
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
    }

    private func openSettings(_ bank: BankID?) {
        settingsFocus = bank
        tab = .settings
    }

    /// Nunca con el bloqueo delante ni con la app fuera de primer plano.
    private func openDetail(_ id: UUID, zooms: Bool = false) {
        guard gate.canPresent, !isLocked, scenePhase == .active, model.movement(id) != nil else { return }
        detail = DetailRoute(id: id, zooms: zooms)
    }

    private func applyRoute() {
        guard !isLocked, let route = router.pending else { return }
        router.pending = nil
        switch route.destination {
        case .home: tab = .home
        case .alerts: tab = .alerts
        }
        if let id = route.movementID {
            // Tras el cambio de pestaña, para que la hoja suba sobre la pantalla buena.
            routeTask?.cancel()
            routeTask = Task {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                openDetail(id)
            }
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
        }
    }
    #endif
}

/// Lo que puede enseñar la única hoja de la app. `RootView` es su único dueño.
enum RootSheet: Identifiable {
    case movement(DetailRoute)
    case share(ShareItem)
    case restore(RestorePreview)

    var id: String {
        switch self {
        case .movement(let route): "movement-\(route.id)"
        case .share(let item): "share-\(item.id)"
        case .restore(let preview): "restore-\(preview.id)"
        }
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
private struct TabBarCurtain: View {
    let token: Int
    @State private var covered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LinearGradient(stops: [.init(color: .black.opacity(0), location: 0), .init(color: .black, location: 0.3)],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: 120)
            .ignoresSafeArea(edges: .bottom)
            .opacity(covered ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: token) { _, _ in
                guard !reduceMotion else { return }
                covered = true
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    withAnimation(.easeOut(duration: 0.35)) { covered = false }
                }
            }
    }
}
