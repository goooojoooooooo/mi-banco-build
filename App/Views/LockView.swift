import SwiftUI
import LocalAuthentication
import MiBancoCore

/// Bloqueo: negro, la marca, una línea y el botón de Face ID.
///
/// En el arranque en frío (`playsLaunch`) la marca se monta aquí mismo con el arranque «logo en piezas»: las dos
/// mitades de la ola llegan entre líneas de velocidad y encajan, se dibuja la loseta, aparece el nombre y cruza un
/// brillo. Es solo dibujo: Face ID se pide a la vez y no espera a nada, el botón está desde el primer fotograma y un
/// toque en la pantalla deja la marca terminada (no desbloquea nada). En un re-bloqueo (volver de segundo plano) la
/// marca aparece quieta y entera, sin animación.
struct LockView: View {
    @Binding var locked: Bool
    /// Arranque en frío: las piezas se montan sobre la marca. Si no, la marca está quieta desde el principio.
    var playsLaunch = false
    /// Se pregunta en el instante de desbloquear: cómo se va este bloqueo (fundiéndose, soltando o no su marca; o de
    /// golpe, porque la tapa lo releva). Lo decide la carcasa con `ShellState`.
    var leaveOnUnlock: () -> LockLeave = { .fades(handsMark: false) }
    /// Aviso a la carcasa, justo después de desbloquear: cuánto dura el fundido con el que se va este bloqueo (0 si se
    /// quita de golpe). Hasta entonces Inicio no recibe toques.
    /// El fundido empieza: cuánto dura y si este bloqueo se funde con su marca dibujada (nada la recoge para volar).
    var fadeStarted: (_ seconds: Double, _ keepsItsMark: Bool) -> Void = { _, _ in }
    /// SEC-08: desactivar el bloqueo a conciencia cuando el iPhone no tiene código ni Face ID.
    var disableLock: () -> Void = {}
    /// SEC-08: lo que contesta el sistema a «¿puedo autenticar al dueño?». Se inyecta para que lo único que cambia entre
    /// la app real, la demo sin código y las pruebas sea ESTE valor: la guardia de `authenticate()` es siempre la misma.
    var deviceAuth: () -> DeviceAuthAvailability = LockView.systemDeviceAuth
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.motion) private var motion
    @State private var authenticating = false
    /// SEC-08 (m-3): desactivar el bloqueo pide confirmación; Onyx se abrirá sin protección.
    @State private var confirmingDisable = false
    /// Un intento automático por bloqueo (esta vista solo existe mientras está bloqueado).
    @State private var autoAttempted = false
    @State private var failures = 0
    /// SEC-08: estado del bloqueo según si el iPhone tiene código/biometría o no.
    @State private var screenMode: LockScreenMode = .authenticate
    /// Solo dibujo: cuándo empezó a montarse la marca, si ya ha terminado (o se saltó con un toque) y dónde está.
    @State private var launchStart = LaunchClock.startDate()
    @State private var launchFinished = false
    @State private var markFrame: CGRect = .zero
    @State private var clicks = 0
    /// La marca ya la lleva la que vuela (solo dibujo; se pone al desbloquear).
    @State private var markHandedOff = false
    /// Se desbloqueó antes de que la marca terminara de montarse: el nombre y el lema, que aún no habían salido, ya no
    /// salen (no aparecen de golpe para fundirse enseguida).
    @State private var textsDropped = false
    /// Ya desbloqueado y fundiéndose: no recibe toques, VoiceOver ya no lo ve (su botón no se puede activar ni con
    /// doble toque) y `unlock()` no hace nada, así que no vuelve a pedir Face ID. Los toques tampoco llegan a Inicio:
    /// la carcasa no se los da hasta que este fundido termina (`ShellState.homeTakesTouches`).
    @State private var leaving = false
    /// Retoque 1: el nombre, el lema y el botón ya se han apagado (0,12 s) al desbloquear.
    @State private var textsAway = false

    /// Lo que recibe `accessibilityHidden`: VoiceOver deja de ver el bloqueo (y su «Desbloquear») en cuanto se va.
    private var hiddenFromVoiceOver: Bool { leaving }

    #if DEBUG
    private func noteVoiceOverForTests() {
        LaunchProbe.shared.lockVoiceOver = hiddenFromVoiceOver ? "oculto" : "visible"
    }
    #endif

    private static let markSize: CGFloat = 76
    /// Lo que tardan en apagarse el nombre, el lema y el botón al desbloquear (s a nivel Equilibrado; retoque 1).
    static let textsAwaySeconds = 0.12

    /// Esos 0,12 s con la intensidad y la cámara lenta (con Reducir, solo la cámara lenta): lo que dura la animación de
    /// los textos y lo que espera el fundido del bloqueo.
    private var textsAwayDuration: Double {
        motion.reduce ? motion.pause(Self.textsAwaySeconds) : motion.seconds(Self.textsAwaySeconds)
    }

    /// La marca ya no se mueve: no es un arranque en frío, o ya se montó.
    private var markSettled: Bool { !playsLaunch || launchFinished }

    var body: some View {
        let timeline = LaunchTimeline(motion)
        let center = CGPoint(x: markFrame.midX, y: markFrame.midY)
        LaunchStage(
            timeline: timeline, act: .lock, start: launchStart, finished: markSettled,
            timeMultiplier: motion.timeMultiplier
        ) { frame in
            LockFace(
                nameOpacity: textsDropped ? 0 : frame.name, nameSpread: CGFloat(1 - frame.name),
                taglineOpacity: textsDropped ? 0 : frame.name,
                textsAway: textsAway,
                awayAnimation: .easeOut(duration: textsAwayDuration),
                awayDrop: motion.distance(8)
            ) {
                LaunchMark(frame: frame, size: Self.markSize)
                    .opacity(markHandedOff ? 0 : frame.mark)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { markFrame = $0 }
            } action: {
                if screenMode == .noPasscode {
                    noPasscodeActions
                } else {
                    Button(action: unlock) {
                        UnlockLabel(failures: failures)
                    }
                    .buttonStyle(.pressable)
                    .disabled(authenticating)
                }
            }
            // Las líneas de velocidad van por detrás de todo y las mitades de la ola por delante de la marca; los dos
            // lienzos ocupan la pantalla entera, no reciben toques y solo existen mientras la marca se monta.
            .background {
                if !markSettled, markFrame != .zero {
                    LaunchSkyCanvas(frame: frame, center: center).ignoresSafeArea()
                }
            }
            .overlay {
                if !markSettled, markFrame != .zero, !frame.joined {
                    LaunchHalvesCanvas(
                        frame: frame, center: center, markSize: Self.markSize, distanceScale: motion.level.distanceScale
                    )
                    .ignoresSafeArea()
                }
            }
        }
        // Lo que cambia DENTRO del bloqueo (la marca que queda terminada o se entrega a la que vuela, las piezas y las
        // líneas que desaparecen) cambia de golpe, aunque ocurra en la misma actualización que el fundido de salida. El
        // fundido lo aplica quien quita el bloqueo, por fuera de esta vista: a ese no le afecta.
        .transaction { $0.animation = nil }
        .background(Theme.canvas.ignoresSafeArea())
        // Un toque en cualquier parte deja la marca terminada. Solo cambia el dibujo: no toca `locked`.
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { launchFinished = true })
        .allowsHitTesting(!leaving)
        // Mientras se funde, VoiceOver tampoco lo ve: «Desbloquear» no se puede activar con la app ya desbloqueada.
        // (Un modificador propio: el que esconde a VoiceOver es el mismo que lo apunta para las pruebas al aparecer; si
        // se quitara, la sonda se quedaría sin «visible» y `testLaunchSkippableAndNeverAboveLock` fallaría.)
        .modifier(LockVoiceOverHidden(hidden: hiddenFromVoiceOver))
        .launchProbe("lock-mark", value: launchFinished ? "completa" : (playsLaunch ? "piezas" : "fija"))
        .sensoryFeedback(Haptics.lock, trigger: clicks)
        .task { await assembleMark(timeline) }
        .task {
            #if DEBUG
            if DemoMode.holdsLock, DemoMode.simulatedDeviceAuth == nil {
                // Demo: sin Face ID; tras ~4 s, la misma salida que usa el éxito de la autenticación. (Si una prueba
                // retrasa el arranque para grabarlo, el bloqueo de demo espera lo mismo; la espera es exacta para que
                // las grabaciones sepan cuándo ocurre.)
                var seconds = DemoMode.lockSeconds + DemoMode.launchHoldSeconds
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(seconds), tolerance: .milliseconds(20))
                    if unlockWithFade() { return }
                    // La app estaba en segundo plano y el desbloqueo no se aceptó (como un Face ID tardío). El «vuelve a
                    // pedirlo al volver» de la demo: espera a primer plano y el bloqueo dura otra vez lo suyo, entero.
                    while !Task.isCancelled, case .refused = leaveOnUnlock() {
                        try? await Task.sleep(for: .milliseconds(200))
                    }
                    seconds = DemoMode.lockSeconds
                }
                return
            }
            #endif
            await autoAuthenticate()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await autoAuthenticate() }
            }
        }
    }

    /// SEC-08: aviso claro y botón consciente para desactivar el bloqueo cuando el iPhone no tiene código ni Face ID.
    private var noPasscodeActions: some View {
        VStack(spacing: Theme.Space.gutter) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.trianglebadge.exclamationmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.warning)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                Text(LockAuthPolicy.noPasscodeMessage)
                    .titan(.callout)
                    .foregroundStyle(Theme.label)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("lock-no-passcode-message")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))

            if confirmingDisable {
                disableConfirmation
            } else {
                Button { confirmingDisable = true } label: {
                    Text(LockAuthPolicy.disableLockButtonTitle)
                        .titan(.option)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.label)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.raised, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("lock-disable-button")
            }
        }
    }

    /// SEC-08 (m-3): confirmación en el propio bloqueo (la regla U55 solo permite presentaciones en `RootView`, que queda
    /// por debajo del bloqueo). Explica que Onyx se abrirá sin protección; Cancelar deja el bloqueo puesto.
    private var disableConfirmation: some View {
        VStack(spacing: 12) {
            Text(LockAuthPolicy.disableConfirmationTitle)
                .titan(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.label)
                .multilineTextAlignment(.center)
            Text(LockAuthPolicy.disableConfirmationMessage)
                .titan(.callout)
                .foregroundStyle(Theme.label)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("lock-disable-confirmation-message")
            Button(action: disableLockAndUnlock) {
                Text(LockAuthPolicy.disableConfirmationButtonTitle)
                    .titan(.option)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.warning)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.raised, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("lock-confirm-disable-button")
            Button { confirmingDisable = false } label: {
                Text("Cancelar")
                    .titan(.option)
                    .foregroundStyle(Theme.label)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Capsule())
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("lock-cancel-disable-button")
        }
    }
    /// Solo dibujo: espera a que las piezas encajen (golpe háptico) y a que la marca quede montada, y para el reloj.
    /// Los tiempos salen del guion por el multiplicador de grabación (intensidad, Reducir movimiento, cámara lenta).
    private func assembleMark(_ timeline: LaunchTimeline) async {
        #if DEBUG
        if playsLaunch {
            LaunchProbe.shared.lockPlays += 1
            LaunchProbe.shared.startsAt = launchStart.timeIntervalSince1970
        } else {
            LaunchProbe.shared.lockStatic += 1
        }
        #endif
        guard playsLaunch, !launchFinished else { return }
        let multiplier = max(motion.timeMultiplier, 0.01)
        let began = launchStart
        func wait(until elapsed: Double) async -> Bool {
            let remaining = elapsed * multiplier - Date().timeIntervalSince(began)
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining), tolerance: LaunchClock.tolerance) }
            return !Task.isCancelled && !launchFinished
        }
        if let lockAt = timeline.piecesLockAt {
            guard await wait(until: lockAt) else { return }
            clicks += 1
        }
        guard await wait(until: timeline.lockDuration) else { return }
        launchFinished = true
    }

    private func unlock() {
        // Ya desbloqueado y fundiéndose: no se vuelve a pedir Face ID (ni con un doble toque de VoiceOver).
        guard !leaving else { return }
        Task { await authenticate() }
    }

    /// SEC-08: desactiva el bloqueo de Onyx a conciencia y solo entonces deja pasar limpiamente.
    private func disableLockAndUnlock() {
        guard !leaving else { return }
        disableLock()
        unlockWithFade()
    }

    /// Solo en primer plano y una vez por bloqueo; si se cancela, queda el botón.
    private func autoAuthenticate() async {
        #if DEBUG
        if DemoMode.holdsLock, DemoMode.simulatedDeviceAuth == nil { return }
        #endif
        guard scenePhase == .active, !autoAttempted else { return }
        autoAttempted = true
        await authenticate()
    }

    private func authenticate() async {
        guard !authenticating, !leaving else { return }
        authenticating = true
        defer { authenticating = false }
        // SEC-08: sin código ni Face ID en el iPhone NO se desbloquea en silencio. Esta guardia la recorren la app real, la
        // demo (`-MiBancoDemoNoPasscode`, que solo cambia lo que contesta `currentAvailability()`) y las pruebas.
        guard applyAvailability(currentAvailability()) else { return }
        let context = LAContext()
        let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Para que solo tú veas tu dinero")) ?? false
        if ok { unlockWithFade() } else { failures += 1 }
    }

    /// Lo que contesta el sistema real: solo `LAError.passcodeNotSet` cuenta como «sin código».
    nonisolated static func systemDeviceAuth() -> DeviceAuthAvailability {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) { return .available }
        return lockAvailability(errorDomain: error?.domain, errorCode: error?.code)
    }

    /// Solo en DEBUG, las banderas de demo sustituyen lo que contesta el sistema; el resto del recorrido es el real.
    private func currentAvailability() -> DeviceAuthAvailability {
        #if DEBUG
        if let simulated = DemoMode.simulatedDeviceAuth { return simulated }
        #endif
        return deviceAuth()
    }

    /// Devuelve `true` solo si hay que pedir Face ID/código. Con cualquier otra respuesta nada se desbloquea:
    /// `passcodeNotSet` enseña la pantalla «sin código»; un fallo distinto deja «Desbloquear» para reintentar.
    @discardableResult
    private func applyAvailability(_ availability: DeviceAuthAvailability) -> Bool {
        let decision = LockAuthPolicy.decision(for: availability)
        screenMode = LockAuthPolicy.screenMode(for: decision)
        // Al salir de «sin código» el panel de confirmación vuelve a su primer paso (no queda el consentimiento a medias).
        if screenMode != .noPasscode { confirmingDisable = false }
        if LockAuthPolicy.proceedsToEvaluate(decision) { return true }
        // Al volver de Ajustes del iPhone (o tras un fallo pasajero), permite volver a comprobar.
        autoAttempted = false
        if decision == .retryAuthentication { failures += 1 }
        return false
    }

    /// Solo la salida se anima (un fundido breve); con Reducir movimiento, uno aún más corto. El fundido lee `\.motion`:
    /// obedece la intensidad, Reducir movimiento (también el forzado al grabar) y la cámara lenta.
    ///
    /// Devuelve `false` si la carcasa no acepta el desbloqueo (la app ya está en segundo plano: `ShellState` lo
    /// ignoraría). Entonces este bloqueo no cambia NADA de su dibujo y se queda como estaba, listo para volver a pedir
    /// Face ID al volver a primer plano.
    @discardableResult
    private func unlockWithFade() -> Bool {
        // Antes de irse, el DIBUJO queda como lo va a recoger la salida: la marca terminada (ni mitades en el aire ni
        // líneas de velocidad, aunque Face ID haya sido más rápido que las piezas) y, si la marca echa a volar ahora,
        // este bloqueo deja de dibujar la suya. Esos cambios van sin animación (`.transaction` en `body`); el único que
        // se anima es el fundido del bloqueo entero. Nada de esto toca `locked`.
        let leave = leaveOnUnlock()
        if case .refused = leave {
            // El intento automático vuelve a estar disponible: al volver a `.active` se pide otra vez.
            autoAttempted = false
            #if DEBUG
            LaunchProbe.shared.refusedUnlocks += 1
            #endif
            return false
        }
        #if DEBUG
        // Para las pruebas: cómo estaba la marca en el instante del desbloqueo, ANTES de dejarla terminada.
        LaunchProbe.shared.lockMarkBeforeLeaving = launchFinished ? "completa" : (playsLaunch ? "piezas" : "fija")
        #endif
        var takesTheMark = false
        if case .fades(let handsMark) = leave { takesTheMark = handsMark && LaunchTimeline(motion).exitDuration != nil }
        // Si la marca aún se estaba montando y ahora sale volando, el nombre y el lema ya no llegan a salir.
        if playsLaunch, !launchFinished, takesTheMark { textsDropped = true }
        launchFinished = true
        if takesTheMark { markHandedOff = true }
        leaving = true
        #if DEBUG
        noteVoiceOverForTests()
        // Para las pruebas: cómo DEJA este bloqueo su marca al irse (después de forzarla a terminada: si esa línea
        // faltara, diría «piezas»), y si se queda fundiéndose con su marca dibujada (si entonces echara a volar otra,
        // se verían dos).
        LaunchProbe.shared.lockMarkLeaving = launchFinished ? "completa" : "piezas"
        if case .fades = leave {
            LaunchProbe.shared.lockFadesWithItsMark = !takesTheMark
        } else {
            LaunchProbe.shared.lockFadesWithItsMark = false
        }
        #endif
        switch leave {
        case .refused:
            return false
        case .fades:
            // Retoque 1: nombre, lema y botón se van en 0,12 s, antes que el resto del bloqueo; nunca flotan sobre
            // Inicio ni pisan la barra de pestañas.
            textsAway = true
            // I-1 (ronda 1): los dos fundidos van en orden, a todos los niveles: el bloqueo (lo que destapa Inicio)
            // empieza a irse cuando los textos y el botón ya se han ido. `locked` cambia YA (la carcasa desbloquea en
            // este instante, como siempre); solo el DIBUJO del fundido espera.
            var away = textsAwayDuration
            #if DEBUG
            // Solo para la prueba que demuestra su propio rojo (ronda 2, N-1): el defecto de antes, sin retardo.
            if DemoMode.lockFadeWithoutDelay { away = 0 }
            #endif
            // La misma duración que el fundido: `motion.fade` dura 0,22 s (× cámara lenta). Es una curva con final
            // (no un muelle, que a su duración nominal aún deja el bloqueo a un par de puntos de opacidad): cuando la
            // carcasa devuelve los toques a Inicio, del bloqueo no queda ni un píxel.
            let seconds = motion.reduce ? 0.22 * motion.timeMultiplier : motion.seconds(0.3)
            withAnimation((motion.reduce ? motion.fade : .easeOut(duration: seconds)).delay(away)) { locked = false }
            // (Los textos siguen apagándose en `textsAwayDuration`.)
            fadeStarted(away + seconds, !takesTheMark)
            #if DEBUG
            // Ronda 2 (N-1): las sondas las escribe lo DIBUJADO (`DrawnOpacityProbe` en el nombre y en el fundido del
            // bloqueo), fotograma a fotograma; aquí solo se vacían para este desbloqueo.
            LaunchProbe.shared.lockTextsGoneAt = nil
            LaunchProbe.shared.lockFadeBeganAt = nil
            LaunchProbe.shared.lockFadeArmed = true
            #endif
        case .covered:
            // La escena no está activa (Face ID aún la tiene): la tapa se pone encima en esta misma actualización y este
            // bloqueo se quita de golpe, sin fundido. Si se fundiera debajo, al volver la escena a activa antes de
            // acabar asomaría a medio apagar —marca, lema y botón— junto a la marca que echa a volar.
            var atOnce = Transaction()
            atOnce.disablesAnimations = true
            withTransaction(atOnce) { locked = false }
            fadeStarted(0, !takesTheMark)
        }
        return true
    }
}

/// La etiqueta del botón del bloqueo. La tapa del selector de apps reserva su hueco con una copia oculta de esta misma
/// vista: así la marca queda exactamente en el mismo sitio en las dos, también con el texto en tamaños de
/// accesibilidad, que es cuando el botón crece.
struct UnlockLabel: View {
    var failures = 0

    var body: some View {
        Label("Desbloquear", systemImage: "faceid")
            .titan(.option)
            .fontWeight(.semibold)
            .foregroundStyle(.black)
            .symbolEffect(.bounce, value: failures)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(.white, in: Capsule())
    }
}

/// Cómo deja la pantalla el bloqueo al desbloquear. Lo decide la carcasa (`ShellState.lockExitOnUnlock`).
enum LockLeave {
    /// La escena está activa: el bloqueo se funde sobre Inicio. `handsMark`: la marca echa a volar en ese mismo instante
    /// desde donde está la del bloqueo, que deja de dibujar la suya (nunca se ven dos).
    case fades(handsMark: Bool)
    /// La escena no está activa: la tapa del selector de apps releva al bloqueo y este se quita de golpe.
    case covered
    /// La app ya está en segundo plano: el desbloqueo no se acepta y el bloqueo se queda (`ShellState.acceptsUnlock`).
    case refused
}

/// La cara del bloqueo: la marca, el nombre y el lema, con el botón (o su hueco) abajo. La comparten el bloqueo y la
/// tapa del selector de apps, para que la marca esté exactamente en el mismo sitio en los dos, y apunta ese sitio en
/// `LaunchAnchor.lockMarkFrame` (de ahí sale volando la marca al desbloquear).
struct LockFace<Mark: View, Action: View>: View {
    /// Solo mientras la marca se monta en el arranque: el nombre aparece y su interletraje se cierra.
    var nameOpacity: Double = 1
    /// 1 = letras separadas (0,24 em de más), 0 = como siempre.
    var nameSpread: CGFloat = 0
    /// El lema aparece con el nombre mientras la marca se monta; la tapa del selector de apps no lo enseña (0).
    var taglineOpacity: Double = 1
    /// Retoque 1 (desbloqueo limpio): al desbloquear, el nombre, el lema y el botón se apagan solos (el botón bajando
    /// 8 pt) con `awayAnimation`, antes de que Inicio empiece a verse. La marca no: es de quien vuela o del fundido.
    var textsAway = false
    var awayAnimation: Animation? = nil
    var awayDrop: CGFloat = 0
    @ViewBuilder let mark: Mark
    @ViewBuilder let action: Action
    @Environment(\.launchAnchor) private var anchor

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            mark
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { anchor?.lockMarkFrame = $0 }
            Text(AppIdentity.displayName)
                .modifier(NameSpread(spread: nameSpread))
                .titan(.sheetTitle)
                .foregroundStyle(Theme.label)
                .opacity(nameOpacity)
                .modifier(DrawnOpacityProbe(opacity: textsAway ? 0 : 1, mark: .lockTextsGone))
                .animation(awayAnimation, value: textsAway)
                .padding(.top, Theme.Space.gutter)
                .accessibilityAddTraits(.isHeader)
            Text("Tu dinero, solo para ti.")
                .titan(.callout)
                .foregroundStyle(Theme.label2)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
                .opacity(taglineOpacity)
                .opacity(textsAway ? 0 : 1)
                .animation(awayAnimation, value: textsAway)
            Spacer()
            action
                .opacity(textsAway ? 0 : 1)
                .offset(y: textsAway ? awayDrop : 0)
                .animation(awayAnimation, value: textsAway)
                .padding(.horizontal, Theme.Space.gutter + 8)
                .padding(.bottom, Theme.Space.gutter)
        }
        .frame(maxWidth: .infinity)
    }
}

/// El interletraje de más del nombre mientras la marca se monta. En reposo (`spread` 0) no toca nada: el nombre es
/// exactamente el de siempre.
private struct NameSpread: ViewModifier {
    let spread: CGFloat

    @ViewBuilder func body(content: Content) -> some View {
        if spread > 0.001 {
            content.tracking(TitanFont.sheetTitle.tracking + 0.24 * spread * TitanFont.sheetTitle.size)
        } else {
            content
        }
    }
}

/// D-9: mientras el bloqueo se funde, VoiceOver no lo ve (ni su «Desbloquear»). En DEBUG, este mismo modificador
/// apunta en la sonda lo que acaba de recibir al aparecer: quitarlo deja la sonda sin «visible», y la prueba lo nota.
private struct LockVoiceOverHidden: ViewModifier {
    let hidden: Bool

    func body(content: Content) -> some View {
        content
            .accessibilityHidden(hidden)
            #if DEBUG
            .onAppear { LaunchProbe.shared.lockVoiceOver = hidden ? "oculto" : "visible" }
            #endif
    }
}

/// Ronda 2 (N-1): una opacidad animable que, en DEBUG, apunta en `LaunchProbe` el primer fotograma DIBUJADO en que cruza
/// su umbral: el nombre del bloqueo ya apagado (≤ 0,02) o el bloqueo empezando a irse (< 0,99). Así la prueba compara lo
/// que se ve, no lo que se programó. En Release solo es una opacidad.
struct DrawnOpacityProbe: ViewModifier, Animatable {
    enum Mark { case lockTextsGone, lockFadeBegan }

    var opacity: Double
    let mark: Mark

    nonisolated var animatableData: Double {
        get { opacity }
        set { opacity = newValue }
    }

    func body(content: Content) -> some View {
        #if DEBUG
        note()
        #endif
        return content.opacity(opacity)
    }

    #if DEBUG
    private func note() {
        let probe = LaunchProbe.shared
        let now = Date().timeIntervalSince1970
        switch mark {
        case .lockTextsGone:
            if opacity <= 0.02, probe.lockTextsGoneAt == nil, probe.lockFadeArmed { probe.lockTextsGoneAt = now }
        case .lockFadeBegan:
            if opacity < 0.99, probe.lockFadeBeganAt == nil, probe.lockFadeArmed { probe.lockFadeBeganAt = now }
        }
    }
    #endif
}
