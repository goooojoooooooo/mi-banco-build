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
    /// Hoja de un movimiento abierta desde Avisos o desde un aviso tocado.
    @State private var detail: DetailRoute?
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
            }
            Tab("Avisos", systemImage: "bell", value: AppTab.alerts) {
                AlertsView(model: model, isVisible: tab == .alerts && !isLocked, onOpen: { openDetail($0) })
            }
            .badge(tab == .alerts ? 0 : seen.unseenCount(of: warnings))
            Tab("Ajustes", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView(model: model, focusRequest: $settingsFocus)
            }
        }
        .tint(Theme.label)
        .modifier(MinimizesTabBarOnScroll())
        .overlay(alignment: .bottom) {
            TabBarCurtain(token: revealToken)
        }
        // La única hoja de la app. Se cierra al bloquear y en cuanto la app deja de estar activa (selector de apps,
        // segundo plano): nunca queda encima del bloqueo ni en la captura del selector, y no se vuelve a abrir sola.
        .sheet(item: $detail, onDismiss: deletePending) { route in
            MovementDetailSheet(model: model, id: route.id) { id in
                pendingDelete = id
                detail = nil
            }
            .modifier(ZoomFromRow(route: route, namespace: zoom))
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { detail = nil }
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
            if locked {
                detail = nil
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

    private func openSettings(_ bank: BankID?) {
        settingsFocus = bank
        tab = .settings
    }

    /// Nunca con el bloqueo delante ni con la app fuera de primer plano.
    private func openDetail(_ id: UUID, zooms: Bool = false) {
        guard !isLocked, scenePhase == .active, model.movement(id) != nil else { return }
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
            Task {
                try? await Task.sleep(for: .milliseconds(250))
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
        case .alerts: tab = .alerts
        case .settings: tab = .settings
        }
    }
    #endif
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
