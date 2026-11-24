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
    /// Se pregunta en el instante de desbloquear: ¿la marca echa a volar ahora mismo hacia Inicio? Si sí, este bloqueo
    /// deja de dibujar la suya en ese instante (la que vuela sale del mismo sitio): nunca se ven dos.
    var flightTakesTheMark: () -> Bool = { false }
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.motion) private var motion
    @State private var authenticating = false
    /// Un intento automático por bloqueo (esta vista solo existe mientras está bloqueado).
    @State private var autoAttempted = false
    @State private var failures = 0
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

    private static let markSize: CGFloat = 76

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
                taglineOpacity: textsDropped ? 0 : frame.name
            ) {
                LaunchMark(frame: frame, size: Self.markSize)
                    .opacity(markHandedOff ? 0 : frame.mark)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { markFrame = $0 }
            } action: {
                Button(action: unlock) {
                    Label("Desbloquear", systemImage: "faceid")
                        .titan(.option)
                        .fontWeight(.semibold)
                        .foregroundStyle(.black)
                        .symbolEffect(.bounce, value: failures)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(.pressable)
                .disabled(authenticating)
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
        .background(Theme.canvas.ignoresSafeArea())
        // Un toque en cualquier parte deja la marca terminada. Solo cambia el dibujo: no toca `locked`.
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { launchFinished = true })
        .launchProbe("lock-mark", value: launchFinished ? "completa" : (playsLaunch ? "piezas" : "fija"))
        .sensoryFeedback(Haptics.lock, trigger: clicks)
        .task { await assembleMark(timeline) }
        .task {
            #if DEBUG
            if DemoMode.holdsLock {
                // Demo: sin Face ID; tras ~4 s, la misma salida que usa el éxito de la autenticación. (Si una prueba
                // retrasa el arranque para grabarlo, el bloqueo de demo espera lo mismo; la espera es exacta para que
                // las grabaciones sepan cuándo ocurre.)
                try? await Task.sleep(
                    for: .seconds(DemoMode.lockSeconds + DemoMode.launchHoldSeconds), tolerance: .milliseconds(20))
                unlockWithFade()
                return
            }
            #endif
            await autoAuthenticate()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await autoAuthenticate() } }
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
        Task { await authenticate() }
    }

    /// Solo en primer plano y una vez por bloqueo; si se cancela, queda el botón.
    private func autoAuthenticate() async {
        #if DEBUG
        if DemoMode.holdsLock { return }
        #endif
        guard scenePhase == .active, !autoAttempted else { return }
        autoAttempted = true
        await authenticate()
    }

    private func authenticate() async {
        guard !authenticating else { return }
        authenticating = true
        defer { authenticating = false }
        let context = LAContext()
        var error: NSError?
        // Sin código en el iPhone no hay con qué autenticar: se deja pasar en vez de dejarte fuera.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            unlockWithFade()
            return
        }
        let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Para que solo tú veas tu dinero")) ?? false
        if ok { unlockWithFade() } else { failures += 1 }
    }

    /// Solo la salida se anima (un fundido breve); con Reducir movimiento, uno aún más corto. El fundido lee `\.motion`:
    /// obedece la intensidad, Reducir movimiento (también el forzado al grabar) y la cámara lenta.
    private func unlockWithFade() {
        // Antes de fundirse, y sin animación, el DIBUJO queda como lo va a recoger la salida: la marca terminada (ni
        // mitades en el aire ni líneas de velocidad, aunque Face ID haya sido más rápido que las piezas) y, si la marca
        // echa a volar ahora, este bloqueo deja de dibujar la suya. Nada de esto toca `locked`.
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            let takesTheMark = LaunchTimeline(motion).exitDuration != nil && flightTakesTheMark()
            // Si la marca aún se estaba montando y ahora sale volando, el nombre y el lema ya no llegan a salir.
            if playsLaunch, !launchFinished, takesTheMark { textsDropped = true }
            launchFinished = true
            if takesTheMark { markHandedOff = true }
        }
        #if DEBUG
        // Para las pruebas: cómo estaba la marca del bloqueo en el instante de empezar a fundirse.
        LaunchProbe.shared.lockMarkAtUnlock = launchFinished ? "completa" : "piezas"
        #endif
        withAnimation(motion.reduce ? motion.fade : .smooth(duration: motion.seconds(0.3))) { locked = false }
    }
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
                .padding(.top, Theme.Space.gutter)
                .accessibilityAddTraits(.isHeader)
            Text("Tu dinero, solo para ti.")
                .titan(.callout)
                .foregroundStyle(Theme.label2)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
                .opacity(taglineOpacity)
            Spacer()
            action
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
