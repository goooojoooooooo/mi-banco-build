import MiBancoCore
import SwiftUI
import UserNotifications

@main
struct MiBancoApp: App {
    init() {
        // Antes de terminar el arranque: así un toque en un aviso que abre la app en frío también llega al router.
        UNUserNotificationCenter.current().delegate = ForegroundPresenter.shared
    }

    var body: some Scene {
        // U62 (hipótesis, sin pila que la demuestre; ver ejecución 44972452792 y U77): `WindowGroup` envuelve su cierre en un
        // `LazyView` interno que SwiftUI podría reevaluar en `com.apple.SwiftUI.AsyncRenderer` al cambiar `@State` del `App`
        // (p. ej. al terminar el arranque) y disparar `_swift_task_checkIsolatedSwift` en Swift 6. Por si acaso,
        // `MiBancoApp` no tiene `@State`; el otro sospechoso, el `Canvas` asíncrono de `CardSurface`, ya dibuja en el principal.
        WindowGroup {
            AppShellView()
        }
        // Actualización de bancos en segundo plano (tarea 10): mejor esfuerzo, la decide el sistema.
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await BackgroundRefresh.run()
        }
    }
}

private struct AppShellView: View {
    @State private var model = LedgerModel()
    @State private var portfolio = PortfolioModel()
    @State private var accountBook = AccountBookModel()
    @State private var briefing = BriefingModel()
    @State private var speaker = BriefingSpeaker()
    @State private var logos = MerchantLogos()
    @State private var preferences = AppPreferences()
    @State private var locked = true
    /// Arranque en frío sin bloqueo delante: la capa del arranque («logo en piezas») está puesta hasta que termina.
    /// Solo vale `true` una vez por vida de la app: al volver de segundo plano no hay arranque.
    @State private var launching = true
    /// Inicio aún no se ha enseñado ni una vez desde que se abrió la app. Decide si el bloqueo monta las piezas
    /// (arranque en frío) o sale con la marca quieta (re-bloqueo).
    @State private var coldStart = true
    /// Sube cuando Inicio debe montarse por capas (a los 0,78 s del arranque y al desbloquear).
    @State private var revealToken = 0
    /// Se acaba de desbloquear y falta enseñarlo: Inicio se monta y la marca vuela en cuanto la app está en primer plano
    /// (Face ID deja la escena inactiva un instante; mientras, lo que se ve es la tapa del selector de apps).
    @State private var unlockReveal: UnlockReveal?
    /// La marca volando del bloqueo a su ranura. Solo dibujo; nunca existe con el bloqueo puesto.
    @State private var launchExit: LaunchExitRun?
    @State private var exitCount = 0
    /// Costura de movimiento (F1): dónde está la ranura de la marca en Inicio. Vive aquí, por encima del bloqueo, el telón
    /// y `RootView`, para que todos vean el mismo objeto.
    @State private var launchAnchor = LaunchAnchor()
    @AppStorage("lockEnabled") private var lockEnabled = true
    @Environment(\.scenePhase) private var scenePhase

    private var showsLock: Bool {
        #if DEBUG
        if DemoMode.isActive { return DemoMode.holdsLock && locked }
        #endif
        return locked && lockEnabled
    }
    /// Tapa opaca para la captura del selector de apps; no toca `locked`. Con el bloqueo ya delante no hace falta (el
    /// bloqueo es opaco y no enseña nada) y taparía la marca montándose mientras Face ID tiene la escena inactiva.
    private var showsPrivacyCover: Bool {
        #if DEBUG
        if DemoMode.isActive { return false }
        #endif
        return lockEnabled && scenePhase != .active && !showsLock
    }
    /// En primer plano. En la demo siempre (la fase de escena parpadea en el simulador de CI), igual que la tapa.
    private var sceneActive: Bool {
        #if DEBUG
        if DemoMode.isActive { return true }
        #endif
        return scenePhase == .active
    }

    var body: some View {
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

    @ViewBuilder
    private var content: some View {
            ZStack {
                #if DEBUG
                if DemoMode.isActive { LaunchProbeView() }
                #endif
                RootView(model: model, portfolio: portfolio, accountBook: accountBook,
                         briefing: briefing, speaker: speaker,
                         isLocked: showsLock, revealToken: revealToken)
                    .accessibilityHidden(showsLock)
                    .allowsHitTesting(!showsLock)
                // ORDEN (no cambiar sin revisar el bloqueo): Inicio; el bloqueo o el arranque; la marca que vuela; y,
                // encima de todo, la tapa del selector de apps. El arranque y la marca que vuela solo se montan con
                // `showsLock` falso: nunca hay nada por encima del bloqueo.
                if showsLock {
                    // Entra sin animación (la captura del selector de apps nunca pilla la app a medias);
                    // al desbloquear se desvanece, porque solo ese cambio va en `withAnimation`.
                    // En el arranque en frío monta las piezas sobre su propia marca; en un re-bloqueo, la marca está quieta.
                    LockView(locked: unlockBinding, playsLaunch: coldStart)
                        .transition(.opacity)
                } else if launching {
                    // Sin bloqueo: el arranque. Se quita cuando ya es transparente (sin transición).
                    LaunchSequence(onAssemble: assembleHome, onFinish: finishLaunch)
                        .transition(.identity)
                }
                if let launchExit, !showsLock {
                    // Aparece y se quita de golpe aunque el desbloqueo vaya animado: su primer fotograma es la marca
                    // donde estaba y el último no pinta nada.
                    LaunchExit(from: launchExit.from, cold: launchExit.cold, coversLockMark: launchExit.coversLockMark) {
                        if self.launchExit?.id == launchExit.id { self.launchExit = nil }
                    }
                    .id(launchExit.id)
                    .transition(.identity)
                }
                if showsPrivacyCover {
                    privacyCover
                }
            }
            .environment(\.launchAnchor, launchAnchor)
            // Respaldo del arranque: pase lo que pase con su animación, a los 1,5 s Inicio está a la vista y se puede tocar.
            .task {
                try? await Task.sleep(for: .seconds(launchSafetySeconds))
                if launching && !showsLock { finishLaunch() }
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
                briefing.prefetchOpeningIfNeeded(
                    state: model.state,
                    portfolio: portfolio.portfolioForBackup,
                    book: accountBook.book,
                    privateMode: preferences.privateMode
                )
                // Con el permiso ya pedido: resumen semanal, recordatorios de suscripciones y aviso matinal al día.
                await AlertScheduler.reschedule(for: model.state)
                await MorningBriefingNotifier.reschedule(settings: model.state.alertSettings, shownToday: briefing.shownToday)
                await portfolio.refreshPrices(force: false)
            }
            .environment(logos)
            // El entorno de movimiento va DENTRO de `.environment(preferences)`: lee las preferencias.
            .motionEnvironment()
            #if DEBUG
            .motionGalleryOverlay()
            #endif
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
                        portfolio: portfolio.portfolioForBackup,
                        book: accountBook.book,
                        privateMode: preferences.privateMode
                    )
                    BankSync.refreshOnOpen() // tarea 10
                    Task { await portfolio.refreshPrices(force: false) }
                    Task { await MorningBriefingNotifier.reschedule(settings: model.state.alertSettings, shownToday: briefing.shownToday) }
                    Task { await LiveActivityController.endStale() }
                    // Si se desbloqueó con la escena aún inactiva (Face ID), ahora sí: Inicio se monta y la marca vuela.
                    revealAfterUnlock()
                case .background:
                    speaker.stop()
                    // Nada del arranque sobrevive a irse a segundo plano.
                    launchExit = nil
                    if launching && !showsLock { finishLaunch() }
                    BackgroundRefresh.schedule() // tarea 10
                    Task { await MorningBriefingNotifier.reschedule(settings: model.state.alertSettings, shownToday: briefing.shownToday) }
                    if lockEnabled { locked = true }
                default:
                    speaker.stop()
                    // Fuera de primer plano no sigue ni la marca volando ni el arranque (en la demo la fase de escena no
                    // cuenta: parpadea en el simulador de CI).
                    if !sceneActive {
                        launchExit = nil
                        if launching && !showsLock { finishLaunch() }
                    }
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
                    // Con el bloqueo puesto no queda nada del arranque: ni la marca volando ni un montaje pendiente.
                    launchExit = nil
                    unlockReveal = nil
                }
                // Al desbloquear, Inicio se monta por capas mientras el bloqueo se desvanece encima, y la marca vuela.
                if wasLocked && !isLocked {
                    launching = false
                    unlockReveal = UnlockReveal(cold: coldStart)
                    coldStart = false
                    revealAfterUnlock(lockIsFading: true)
                }
            }
        }

    /// El bloqueo escribe `locked = false` dentro de su animación de salida: en esa misma transacción se da por
    /// terminado el arranque, así la capa del arranque nunca asoma un instante entre el bloqueo y Inicio.
    private var unlockBinding: Binding<Bool> {
        Binding(get: { locked }, set: { value in
            locked = value
            if !value { launching = false }
        })
    }

    /// A los 0,78 s del arranque (o al saltarlo): Inicio empieza a montarse debajo. Solo la primera vez.
    private func assembleHome() {
        guard coldStart else { return }
        coldStart = false
        revealToken += 1
    }

    /// El arranque ha terminado (o lo corta el respaldo): la capa se quita. Si Inicio aún no se montó, se monta ya.
    private func finishLaunch() {
        assembleHome()
        launching = false
    }

    /// Lo que se ve al desbloquear: Inicio se monta por capas y la marca del bloqueo vuela a su ranura. Solo dibujo, y
    /// solo con la app desbloqueada y en primer plano; si aún no lo está, espera a que lo esté (`scenePhase`).
    /// `lockIsFading`: se llama en el mismo instante del desbloqueo, con el bloqueo fundiéndose debajo.
    private func revealAfterUnlock(lockIsFading: Bool = false) {
        guard let pending = unlockReveal, !showsLock, sceneActive else { return }
        unlockReveal = nil
        revealToken += 1
        // La marca vuela si se sabe de dónde sale y a dónde va: en frío, a donde estará la ranura; después, solo si
        // Inicio la tiene a la vista. (Los marcos se leen aquí, en la acción, nunca en `body`.)
        guard let from = launchAnchor.lockMarkFrame, from.width > 0,
              pending.cold || launchAnchor.brandFrame != nil else { return }
        exitCount += 1
        launchExit = LaunchExitRun(id: exitCount, from: from, cold: pending.cold, coversLockMark: lockIsFading)
    }

    /// El respaldo del arranque: 1,5 s. Solo al grabar (DEBUG) se estira igual que el arranque (cámara lenta y espera).
    private var launchSafetySeconds: Double {
        #if DEBUG
        return 1.5 * DemoMode.motionScale + DemoMode.launchHoldSeconds
        #else
        return 1.5
        #endif
    }

    /// La misma cara que el bloqueo (la marca en el mismo sitio y el nombre debajo), sin lema ni botón: al quitarse, la
    /// marca que vuela sale exactamente de donde estaba.
    private var privacyCover: some View {
        LockFace(showsTagline: false) {
            AppMark(size: 76)
        } action: {
            Color.clear.frame(height: 52)
        }
        .background(Theme.canvas.ignoresSafeArea())
        .accessibilityHidden(true)
    }
}

/// Un desbloqueo que falta enseñar (`cold`: es el del arranque en frío).
private struct UnlockReveal {
    let cold: Bool
}

/// Una salida del bloqueo en curso: de dónde sale la marca y cómo.
private struct LaunchExitRun {
    let id: Int
    let from: CGRect
    let cold: Bool
    let coversLockMark: Bool
}
