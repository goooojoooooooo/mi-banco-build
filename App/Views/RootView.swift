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

    var body: some View {
        TabView(selection: $tab) {
            Tab("Inicio", systemImage: "house", value: AppTab.home) {
                HomeView(model: model, isVisible: tab == .home && !isLocked, revealToken: revealToken, openSettings: openSettings)
            }
            Tab("Avisos", systemImage: "bell", value: AppTab.alerts) {
                AlertsView(model: model, isVisible: tab == .alerts && !isLocked)
            }
            Tab("Ajustes", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView(model: model, focusRequest: $settingsFocus)
            }
        }
        .tint(Theme.label)
        .modifier(MinimizesTabBarOnScroll())
        .overlay(alignment: .bottom) {
            TabBarCurtain(token: revealToken)
        }
        #if DEBUG
        .onAppear(perform: applyDemoTab)
        #endif
    }

    private func openSettings(_ bank: BankID?) {
        settingsFocus = bank
        tab = .settings
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
