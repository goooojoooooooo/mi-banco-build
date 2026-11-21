import MiBancoCore
import SwiftUI
import UserNotifications

@main
struct MiBancoApp: App {
    @State private var model = LedgerModel()
    @State private var portfolio = PortfolioModel()
    @State private var accountBook = AccountBookModel()
    @State private var briefing = BriefingModel()
    @State private var speaker = BriefingSpeaker()
    @State private var logos = MerchantLogos()
    @State private var preferences = AppPreferences()
    @State private var locked = true
    /// Arranque en frío: la marca se traza sobre negro y luego Inicio se monta por capas.
    @State private var launching = true
    /// Sube cuando Inicio debe montarse por capas (tras la marca del arranque y al desbloquear).
    @State private var revealToken = 0
    @AppStorage("lockEnabled") private var lockEnabled = true
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Antes de terminar el arranque: así un toque en un aviso que abre la app en frío también llega al router.
        UNUserNotificationCenter.current().delegate = ForegroundPresenter.shared
    }

    private var showsLock: Bool {
        #if DEBUG
        if DemoMode.isActive { return DemoMode.holdsLock && locked }
        #endif
        return locked && lockEnabled
    }
    /// Tapa opaca para la captura del selector de apps; no toca `locked`.
    private var showsPrivacyCover: Bool {
        #if DEBUG
        if DemoMode.isActive { return false }
        #endif
        return lockEnabled && scenePhase != .active
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-MiBancoSelfTest") {
                BankingSelfTestView()
                    .preferredColorScheme(.dark)
            } else {
                content
            }
            #else
            content
            #endif
        }
        // Actualización de bancos en segundo plano (tarea 10): mejor esfuerzo, la decide el sistema.
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await BackgroundRefresh.run()
        }
    }

    @ViewBuilder
    private var content: some View {
            ZStack {
                RootView(model: model, portfolio: portfolio, accountBook: accountBook,
                         briefing: briefing, speaker: speaker,
                         isLocked: showsLock, revealToken: revealToken)
                    .accessibilityHidden(showsLock)
                    .allowsHitTesting(!showsLock)
                if showsLock {
                    // Entra sin animación (la captura del selector de apps nunca pilla la app a medias);
                    // al desbloquear se desvanece, porque solo ese cambio va en `withAnimation`.
                    LockView(locked: unlockBinding)
                        .transition(.opacity)
                } else if launching {
                    LaunchCurtain(onReveal: reveal)
                        .transition(.opacity)
                }
                if showsPrivacyCover {
                    privacyCover
                }
            }
            // Respaldo del telón: pase lo que pase con su animación, a los 1,5 s Inicio está a la vista.
            .task {
                try? await Task.sleep(for: .milliseconds(1_500))
                if launching && !showsLock { reveal() }
            }
            .task {
                // Arranque en frío (tarea 10): puede que no haya cambio de escena que lo dispare.
                await MainActor.run { BankSync.refreshOnOpen() }
                await logos.prewarm(domains: [])
                #if DEBUG
                if DemoMode.isActive {
                    if DemoMode.simulatesArrival {
                        try? await Task.sleep(for: .seconds(4))
                        model.demoSimulateArrival()
                    }
                    return
                }
                #endif
                await AlertPoster.setup()
                // Con el permiso ya pedido: resumen semanal, recordatorios de suscripciones y aviso matinal al día.
                await AlertScheduler.reschedule(for: model.state)
                await MorningBriefingNotifier.reschedule(settings: model.state.alertSettings, shownToday: briefing.shownToday)
                await portfolio.refreshPrices(force: false)
            }
            .environment(logos)
            .environment(preferences)
            .preferredColorScheme(.dark)
            .environment(\.locale, Locale(identifier: "es_ES"))
            // Conexión bancaria (tarea 9): solo `mibanco://cb`; cualquier otra dirección se ignora sin ruido.
            .onOpenURL { url in
                guard isBankCallbackURL(url) else { return }
                Task { await BankConnector.shared.handle(url: url) }
            }
            // Bancos (tarea 10): una conexión cambió (conectar, renovar, desconectar).
            .onReceive(NotificationCenter.default.publisher(for: .bankLinkDidChange)) { note in
                let bank = (note.userInfo?["bank"] as? String).flatMap(BankID.init(rawValue:))
                Task { await BankSync.shared.linkDidChange(bank) }
            }
            .onChange(of: scenePhase) { _, phase in
                // Conexión bancaria (tarea 9): el conector decide con su propio estado; el bloqueo no interviene.
                BankConnector.shared.sceneDidChange(to: phase)
                switch phase {
                case .active:
                    model.reload()
                    portfolio.reload()
                    accountBook.reload()
                    briefing.reloadPreferences()
                    briefing.prefetchOpeningIfNeeded(
                        state: model.state,
                        portfolio: portfolio.hasPositions ? portfolio.portfolio : nil,
                        book: accountBook.book,
                        privateMode: preferences.privateMode
                    )
                    BankSync.refreshOnOpen() // tarea 10
                    Task { await portfolio.refreshPrices(force: false) }
                    Task { await MorningBriefingNotifier.reschedule(settings: model.state.alertSettings, shownToday: briefing.shownToday) }
                    Task { await LiveActivityController.endStale() }
                case .background:
                    speaker.stop()
                    BackgroundRefresh.schedule() // tarea 10
                    Task { await MorningBriefingNotifier.reschedule(settings: model.state.alertSettings, shownToday: briefing.shownToday) }
                    if lockEnabled { locked = true }
                default:
                    speaker.stop()
                    break
                }
            }
            .onChange(of: lockEnabled) { _, _ in
                // Cambiar el ajuste solo es posible con la app ya desbloqueada: no volver a pedir Face ID.
                withAnimation(Theme.Motion.unlock) {
                    locked = false
                    launching = false
                }
            }
            .onChange(of: showsLock) { wasLocked, isLocked in
                if isLocked {
                    speaker.stop()
                }
                // Al desbloquear, Inicio se monta por capas mientras el bloqueo se desvanece encima.
                if wasLocked && !isLocked {
                    launching = false
                    revealToken += 1
                }
            }
        }

    /// El bloqueo escribe `locked = false` dentro de su animación de salida: en esa misma transacción se da por
    /// terminado el arranque, así el telón nunca asoma un instante entre el bloqueo y Inicio.
    private var unlockBinding: Binding<Bool> {
        Binding(get: { locked }, set: { value in
            locked = value
            if !value { launching = false }
        })
    }

    /// La marca ya está trazada: Inicio empieza a montarse debajo y el telón se aparta.
    private func reveal() {
        revealToken += 1
        withAnimation(.easeOut(duration: 0.32)) { launching = false }
    }

    private var privacyCover: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            VStack(spacing: Theme.Space.row) {
                AppMark(size: 64)
                Text("Mi Banco")
                    .titan(.sheetTitle)
                    .foregroundStyle(Theme.label)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Arranque: negro, la marca aparece y su ola se traza (≈ 0,5 s); después se aparta mientras Inicio se monta.
/// No bloquea nada (no recibe toques) y con Reducir movimiento se aparta al instante.
private struct LaunchCurtain: View {
    let onReveal: () -> Void
    @State private var drawn: CGFloat = 0
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            AppMark(size: 72, drawn: drawn)
                .opacity(shown ? 1 : 0)
                .scaleEffect(shown ? 1 : 0.92)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            guard !reduceMotion else {
                onReveal()
                return
            }
            withAnimation(.easeOut(duration: 0.25)) { shown = true }
            withAnimation(Theme.Motion.markDraw.delay(0.05)) { drawn = 1 }
            try? await Task.sleep(for: .milliseconds(560))
            // Si el telón ya se fue (p. ej. desbloqueo), la tarea se cancela: no se vuelve a montar Inicio.
            guard !Task.isCancelled else { return }
            onReveal()
        }
    }
}
