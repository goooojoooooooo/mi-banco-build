import MiBancoCore
import SwiftUI
import UserNotifications

@main
struct MiBancoApp: App {
    init() {
        // Antes de terminar el arranque: así un toque en un aviso que abre la app en frío también llega al router.
        UNUserNotificationCenter.current().delegate = ForegroundPresenter.shared
        #if DEBUG
        LaunchProbe.shared.appInitAt = Date().timeIntervalSince1970
        #endif
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
    /// Las decisiones de la carcasa (bloqueo, tapa del selector de apps, arranque, marca que vuela) viven en Core, en
    /// `ShellState`, donde se prueban en todos sus estados. Esta vista solo le cuenta lo que pasa y dibuja lo que dice.
    @State private var shell = AppShellView.initialShell()
    /// El `revealToken` que ve Inicio. Se copia de `shell.revealToken` en un `onChange`, fuera de la transacción animada
    /// del desbloqueo: Inicio se oculta de golpe y luego se monta por capas (si no, se fundiría con el bloqueo).
    @State private var homeRevealToken = 0
    /// De dónde sale la marca que vuela (un marco en pantalla: eso no es cosa de Core).
    @State private var exitGeometry: ExitGeometry?
    #if DEBUG
    /// Solo demo (`-MiBancoDemoUnlockInactive`): la carcasa hace como que la escena está inactiva tras desbloquear.
    @State private var simulatedInactive = false
    #endif
    /// Costura de movimiento (F1): dónde está la ranura de la marca en Inicio. Vive aquí, por encima del bloqueo, el telón
    /// y `RootView`, para que todos vean el mismo objeto.
    @State private var launchAnchor = LaunchAnchor()
    @AppStorage("lockEnabled") private var lockEnabled = true
    @Environment(\.scenePhase) private var scenePhase

    /// El ajuste del bloqueo tal como lo entiende `ShellState`: si el bloqueo se enseña cuando la app está bloqueada y
    /// si la app se bloquea al ir a segundo plano. En la app real, los dos son el ajuste; en la demo, el bloqueo solo se
    /// enseña con su bandera.
    private static func lockSetting(enabled: Bool) -> (applies: Bool, relocks: Bool) {
        #if DEBUG
        if DemoMode.isActive { return (DemoMode.holdsLock, enabled) }
        #endif
        return (enabled, enabled)
    }

    private static func initialShell() -> ShellState {
        // El mismo valor que lee `@AppStorage("lockEnabled")` (activado si nunca se tocó).
        let enabled = UserDefaults.standard.object(forKey: "lockEnabled") as? Bool ?? true
        let setting = lockSetting(enabled: enabled)
        return ShellState(lockApplies: setting.applies, relocksOnBackground: setting.relocks)
    }

    /// La fase de escena con la que se decide la tapa, leída del entorno en este mismo instante (la tapa tiene que estar
    /// puesta en la misma actualización en que cambia la fase). En la demo la fase no cuenta (parpadea en el simulador
    /// de CI): activa siempre, salvo cuando una prueba pide simular «inactiva tras desbloquear».
    private var coverScene: ShellState.Scene {
        #if DEBUG
        if DemoMode.isActive { return simulatedInactive ? .inactive : .active }
        #endif
        switch scenePhase {
        case .active: return .active
        case .background: return .background
        default: return .inactive
        }
    }

    /// Lo que se le cuenta a `ShellState` de un cambio de fase. En la demo, «inactiva» no se cuenta (parpadea en CI) y
    /// «activa» tampoco mientras dura la simulación de una prueba.
    private func shellScene(_ phase: ScenePhase) -> ShellState.Scene? {
        #if DEBUG
        if DemoMode.isActive {
            switch phase {
            case .background: return .background
            case .active: return simulatedInactive ? nil : .active
            default: return nil
            }
        }
        #endif
        switch phase {
        case .active: return .active
        case .background: return .background
        default: return .inactive
        }
    }

    /// Cómo entra y sale una capa: lo dice `ShellState` (solo se anima el bloqueo al quitarse; todo lo demás, de golpe).
    private func transition(of layer: ShellState.Layer) -> AnyTransition {
        .asymmetric(
            insertion: ShellState.animatesInsertion(of: layer) ? .opacity : .identity,
            removal: ShellState.animatesRemoval(of: layer) ? .opacity : .identity)
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

    private var content: some View {
            // Las capas que hay, tal cual las da `ShellState` con la fase de escena de este instante. Esta vista no
            // decide ninguna: pinta cada una si está en la lista, a la altura y con la entrada y la salida que dice él.
            let layers = shell.layers(liveScene: coverScene)
            return ZStack {
                #if DEBUG
                if DemoMode.isActive { LaunchProbeView() }
                #endif
                RootView(model: model, portfolio: portfolio, accountBook: accountBook,
                         briefing: briefing, speaker: speaker,
                         isLocked: shell.showsLock, revealToken: homeRevealToken,
                         // C6: el aviso dentro de la app lo decide `ShellState` (nunca con el bloqueo ni fuera de
                         // primer plano); se calcula con la fase de escena de este instante, como la tapa.
                         bannerID: coverScene == .active ? shell.shownBanner : nil,
                         requestBanner: { shell.apply(.bannerRequested) },
                         dismissBanner: { shell.apply(.bannerDismissed(id: $0)) })
                    // VoiceOver no lee Inicio con el bloqueo delante, ni bajo el negro del arranque, ni bajo la tapa.
                    .accessibilityHidden(shell.hidesHomeFromVoiceOver || layers.contains(.cover))
                    // Ni con el bloqueo delante ni mientras el bloqueo, ya desbloqueado, se funde: un toque tardío sobre
                    // «Desbloquear» caería en la barra de pestañas que hay justo debajo.
                    .allowsHitTesting(shell.homeTakesTouches)
                    // Con solo fundidos, mientras el bloqueo se funde con su marca, la ranura de la barra no dibuja la
                    // suya (nunca dos marcas): lo decide `ShellState.hidesBrandSlot`, en esta misma actualización.
                    .environment(\.brandSlotHiddenByLock, shell.hidesBrandSlot)
                // El estilo de movimiento de ahora (solo fundidos o piezas) se lo cuenta a la carcasa una vista que ya
                // vive dentro de `motionEnvironment()`: lee lo mismo que leen el bloqueo y el arranque.
                MotionStyleReporter { fadesOnly in shell.apply(.motionStyle(fadesOnly: fadesOnly)) }
                // ORDEN (no cambiar sin revisar el bloqueo; es el de `ShellState.layers`): Inicio; el bloqueo o el arranque;
                // la marca que vuela; y, encima de todo, la tapa del selector de apps. Qué capa hay la decide `ShellState`:
                // el arranque y la marca que vuela nunca existen con el bloqueo puesto, y la tapa nunca va encima de él.
                // Solo se anima una cosa: el bloqueo al quitarse (`ShellState.animatesRemoval`); todo lo demás entra y sale
                // de golpe (`transition(of:)`).
                // Cada capa lleva su `zIndex` (`ShellState.zIndex(of:)`): sin él, una vista que se está quitando de un
                // `ZStack` pasa al fondo, y el bloqueo, en vez de fundirse sobre Inicio, desaparecía de golpe detrás de él.
                if layers.contains(.lock) {
                    // Entra sin animación (la captura del selector de apps nunca pilla la app a medias);
                    // al desbloquear en primer plano se desvanece, porque solo ese cambio va en `withAnimation`; si la
                    // escena no está activa se quita de golpe y lo releva la tapa (`ShellState.lockExitOnUnlock`).
                    // En el arranque en frío monta las piezas sobre su propia marca; en un re-bloqueo, la marca está quieta.
                    LockView(locked: unlockBinding, playsLaunch: shell.lockPlaysLaunch,
                             leaveOnUnlock: lockLeave, fadeStarted: lockFadeStarted)
                        .transition(transition(of: .lock))
                        .zIndex(ShellState.zIndex(of: .lock))
                } else if layers.contains(.launch) {
                    // Sin bloqueo: el arranque. Se quita cuando ya es transparente (sin transición).
                    LaunchSequence(onAssemble: { shell.apply(.launchAssembled) }, onFinish: { shell.apply(.launchFinished) })
                        .transition(transition(of: .launch))
                        .zIndex(ShellState.zIndex(of: .launch))
                }
                if layers.contains(.exit), let exit = shell.shownExit, let geometry = exitGeometry, geometry.id == exit.id {
                    // Aparece y se quita de golpe aunque el desbloqueo vaya animado: su primer fotograma es la marca
                    // donde estaba (el bloqueo suelta la suya en ese mismo instante) y el último no pinta nada.
                    // Va por encima del bloqueo SOLO mientras este se está fundiendo (ya desbloqueado).
                    LaunchExit(from: geometry.from, cold: exit.cold) {
                        shell.apply(.exitFinished(id: exit.id))
                    }
                    .id(exit.id)
                    .transition(transition(of: .exit))
                    .zIndex(ShellState.zIndex(of: .exit))
                }
                if layers.contains(.cover) {
                    // De golpe, al ponerse y al quitarse: nunca se funde con el bloqueo ni deja un destello.
                    privacyCover
                        .transition(transition(of: .cover))
                        .zIndex(ShellState.zIndex(of: .cover))
                }
            }
            .environment(\.launchAnchor, launchAnchor)
            // Respaldo del arranque: pase lo que pase con su animación, a los 1,5 s Inicio está a la vista y se puede tocar.
            .task {
                try? await Task.sleep(for: .seconds(launchSafetySeconds))
                shell.apply(.safetyFired)
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
                // El bloqueo al ir a segundo plano, el corte del arranque fuera de primer plano y el vuelo de la marca
                // que esperaba a primer plano: lo decide `ShellState`.
                if let scene = shellScene(phase) { shell.apply(.scene(scene)) }
                #if DEBUG
                switch phase {
                case .active: LaunchProbe.shared.scene = "activa"
                case .background:
                    LaunchProbe.shared.scene = "fondo"
                    LaunchProbe.shared.backgrounds += 1
                default: LaunchProbe.shared.scene = "inactiva"
                }
                #endif
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
                case .background:
                    speaker.stop()
                    BackgroundRefresh.schedule() // tarea 10
                    Task { await MorningBriefingNotifier.reschedule(settings: model.state.alertSettings, shownToday: briefing.shownToday) }
                default:
                    speaker.stop()
                }
            }
            .onChange(of: lockEnabled) { _, enabled in
                // Cambiar el ajuste solo es posible con la app ya desbloqueada: no volver a pedir Face ID.
                let setting = Self.lockSetting(enabled: enabled)
                withAnimation(Theme.Motion.unlock) {
                    shell.apply(.lockSettingChanged(lockApplies: setting.applies, relocksOnBackground: setting.relocks))
                }
            }
            .onChange(of: shell.showsLock) { _, isLocked in
                if isLocked { speaker.stop() }
            }
            // La marca de la barra de Inicio se esconde mientras vuela la del arranque (`LaunchAnchor.flying`, que ponen
            // y quitan las propias capas que vuelan). Respaldo: sin ninguna de esas capas, nunca se queda escondida.
            .onChange(of: layers.contains(.launch) || layers.contains(.exit)) { _, flying in
                if !flying { launchAnchor.flying = nil }
            }
            #if DEBUG
            .onChange(of: launchAnchor.flying) { _, flying in
                switch flying {
                case nil: LaunchProbe.shared.brandFlying = "-"
                case .mark: LaunchProbe.shared.brandFlying = "marca"
                case .markAndName: LaunchProbe.shared.brandFlying = "marcaYNombre"
                }
            }
            #endif
            // Inicio se monta por capas cuando sube el contador. El salto por `onChange` lo saca de la transacción animada
            // del desbloqueo (como siempre fue): las piezas de Inicio se ocultan de golpe y luego entran.
            .onChange(of: shell.revealToken) { _, token in
                homeRevealToken = token
                #if DEBUG
                LaunchProbe.shared.reveals = token
                #endif
            }
            // La marca echa a volar: de dónde sale y si hay a dónde ir son marcos en pantalla, que se leen aquí, en la
            // acción, nunca en `body`. Si no hay de dónde o a dónde, no vuela.
            .onChange(of: shell.exit) { _, exit in
                guard let exit else {
                    exitGeometry = nil
                    return
                }
                guard let from = flightOrigin(cold: exit.cold) else {
                    shell.apply(.exitFinished(id: exit.id))
                    return
                }
                exitGeometry = ExitGeometry(id: exit.id, from: from)
            }
        }

    /// El bloqueo solo escribe `false` aquí (la autenticación ha salido bien), dentro de su animación de salida. Bloquear
    /// lo decide `ShellState` al ir a segundo plano. En esa misma transacción se da por terminado el arranque: su capa
    /// nunca asoma entre el bloqueo e Inicio.
    private var unlockBinding: Binding<Bool> {
        Binding(get: { shell.locked }, set: { value in
            guard !value else { return }
            #if DEBUG
            simulateInactiveUnlockIfAsked()
            #endif
            shell.apply(.unlockSucceeded)
        })
    }

    /// De dónde saldría volando la marca: el sitio de la marca del bloqueo, si se conoce y hay a dónde ir (en frío, a
    /// donde estará la ranura de Inicio; después, solo si Inicio la tiene a la vista).
    private func flightOrigin(cold: Bool) -> CGRect? {
        guard let from = launchAnchor.lockMarkFrame, from.width > 0, cold || launchAnchor.brandFrame != nil else { return nil }
        return from
    }

    /// Lo pregunta el bloqueo en el instante de desbloquear: cómo se va. Lo decide `ShellState.lockExitOnUnlock`: en
    /// primer plano se funde y, si la marca echa a volar en ese instante, suelta la suya (para que no se vean dos);
    /// fuera de primer plano se quita de golpe, porque la tapa lo releva.
    private func lockLeave() -> LockLeave {
        // En segundo plano no se desbloquea (`ShellState` lo ignoraría): el bloqueo se queda como está.
        guard shell.acceptsUnlock else { return .refused }
        #if DEBUG
        // La prueba que simula «inactiva tras desbloquear»: para la carcasa la escena ya está inactiva en el desbloqueo
        // (`simulateInactiveUnlockIfAsked` se lo cuenta a `ShellState` justo antes de desbloquear).
        if DemoMode.isActive, DemoMode.unlockInactiveSeconds != nil, !simulatedInactive, shell.coldStart { return .covered }
        #endif
        switch shell.lockExitOnUnlock {
        case .covered:
            return .covered
        case .fades, nil:
            return .fades(handsMark: flightOrigin(cold: shell.coldStart) != nil)
        }
    }

    /// Lo avisa el bloqueo justo después de desbloquear: su fundido dura `seconds` (0 si se quitó de golpe). Cuando
    /// acaba, `ShellState` devuelve los toques a Inicio. El aviso de fin va SIEMPRE, se funda o no, para que Inicio no
    /// pueda quedarse sin toques.
    private func lockFadeStarted(_ seconds: Double) {
        #if DEBUG
        LaunchProbe.shared.lockFading = shell.lockFading
        // Para las pruebas: el bloqueo se funde dibujando su marca, nada la esconde en la ranura de Inicio (ni la marca
        // que vuela ni `hidesBrandSlot`) y la ranura está a la vista: dos marcas a medias durante el fundido.
        if shell.lockFading, LaunchProbe.shared.lockFadesWithItsMark, launchAnchor.flying == nil, !shell.hidesBrandSlot,
           launchAnchor.brandFrame != nil {
            LaunchProbe.shared.doubleMarks += 1
        }
        LaunchProbe.shared.slotHiddenByLock = shell.hidesBrandSlot
        #endif
        // El número de ESTE fundido: si entre medias hay un re-bloqueo y otro desbloqueo, este aviso ya no acaba el
        // fundido nuevo (lo acabará el suyo, que también se manda siempre).
        let fade = shell.fadeCount
        Task { @MainActor in
            if seconds > 0 { try? await Task.sleep(for: .seconds(seconds), tolerance: .milliseconds(20)) }
            shell.apply(.lockFadeFinished(id: fade))
            #if DEBUG
            LaunchProbe.shared.lockFading = shell.lockFading
            LaunchProbe.shared.slotHiddenByLock = shell.hidesBrandSlot
            if !shell.lockFading { LaunchProbe.shared.lockFadesWithItsMark = false }
            #endif
        }
    }

    #if DEBUG
    /// Solo demo: reproduce el orden de Face ID en el iPhone — la escena está inactiva al desbloquear y vuelve a activa
    /// un rato después — para grabarlo y probarlo (`-MiBancoDemoUnlockInactive <s>`). Solo en el desbloqueo en frío.
    private func simulateInactiveUnlockIfAsked() {
        guard DemoMode.isActive, let seconds = DemoMode.unlockInactiveSeconds, !simulatedInactive,
              shell.coldStart else { return }
        simulatedInactive = true
        shell.apply(.scene(.inactive))
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds), tolerance: .milliseconds(20))
            simulatedInactive = false
            shell.apply(.scene(.active))
        }
    }
    #endif

    /// El respaldo del arranque: 1,5 s. Solo al grabar (DEBUG) se estira igual que el arranque (cámara lenta y espera).
    private var launchSafetySeconds: Double {
        #if DEBUG
        return 1.5 * DemoMode.motionScale + DemoMode.launchHoldSeconds
        #else
        return 1.5
        #endif
    }

    /// La misma cara que el bloqueo (la marca en el mismo sitio y el nombre debajo), sin lema ni botón: al quitarse, la
    /// marca que vuela sale exactamente de donde estaba. Siempre es opaca. Mientras el arranque sin bloqueo sigue puesto
    /// debajo (solo puede pasar en los primeros instantes de abrir la app, si la escena aún no ha llegado a activa), es
    /// solo negro, como el propio arranque: así no asoma una marca quieta antes de las piezas.
    private var privacyCover: some View {
        let plain = shell.showsLaunch
        return LockFace(nameOpacity: plain ? 0 : 1, taglineOpacity: 0) {
            AppMark(size: 76).opacity(plain ? 0 : 1)
        } action: {
            // El hueco del botón del bloqueo, con su alto de verdad (crece con el tamaño del texto).
            UnlockLabel().hidden()
        }
        .background(Theme.canvas.ignoresSafeArea())
        .accessibilityHidden(true)
        .launchProbe("privacy-cover", value: "tapa")
    }
}

/// De dónde sale la marca que vuela en la salida `id` de `ShellState`.
private struct ExitGeometry {
    let id: Int
    let from: CGRect
}

/// No dibuja nada: cuenta a la carcasa si el movimiento de ahora es solo de fundidos (Sutil o Reducir movimiento, el
/// mismo `LaunchTimeline` que usan el bloqueo y el arranque), al aparecer y cada vez que cambia.
private struct MotionStyleReporter: View {
    let report: (Bool) -> Void
    @Environment(\.motion) private var motion

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: LaunchTimeline(motion).style == .fade, initial: true) { _, fadesOnly in report(fadesOnly) }
    }
}
