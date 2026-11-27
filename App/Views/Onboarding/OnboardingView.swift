import MiBancoCore
import SwiftUI

/// Bienvenida de primera ejecución en tres pasos (Plan 4b, tarea 12).
/// Se muestra en lugar de la barra de pestañas mientras `model.needsOnboarding` es verdadero; el bloqueo queda por encima.
/// Cuando queda a la vista (tras el arranque o al abrirse el bloqueo), tres líneas de titanio cruzan la pantalla y se
/// ensanchan en bandas (`WelcomeBands`); la marca va quieta (el arranque ya la ha dibujado) y las piezas del primer paso
/// llegan una tras otra.
struct OnboardingView: View {
    let model: LedgerModel
    let onFinish: (_ openBanksSettings: Bool) -> Void

    @Environment(\.motion) private var motion
    /// El bloqueo y el montaje por capas, tal como los da la carcasa (`RootView`), en vez de deducirlos de la puerta.
    @Environment(\.shellReveal) private var shell
    /// Costura de la carcasa (`AppShellView`): si la marca del primer arranque vuela hasta aquí, la propia espera
    /// escondida por `.launchWelcomeMark()` y aparece en el mismo fotograma del aterrizaje (nunca dos marcas ni parpadeo).
    @Environment(\.launchAnchor) private var launchAnchor
    /// El bloqueo de ahora, copiado en estado: lo que lee la tarea tras sus esperas (un valor del entorno copiado en la
    /// tarea no se actualizaría; el estado sí).
    @State private var lockedNow = false
    /// Cuándo empieza la bienvenida (`welcomed`: cruzan las bandas y llegan las piezas) y cuándo se dibuja su marca
    /// (`markShown`), según lo que la tapa: el arranque o el bloqueo (Core, `WelcomeReveal`). Si se jugara al montarse,
    /// pasaría entera detrás del bloqueo o del arranque.
    @State private var reveal = WelcomeReveal()
    /// La marca del primer arranque ya vuela hacia `.launchWelcomeMark()`: la marca propia queda lista a opacidad 1
    /// (enmascarada por `LaunchWelcomeMark` hasta el aterrizaje exacto) para el relevo sin fundido ni hueco.
    @State private var handedOffFromLaunch = false
    private var welcomed: Bool { reveal.welcomed }
    private var markShown: Bool { reveal.markShown }

    private var usesWelcomeMarkHook: Bool {
        #if DEBUG
        return !DemoMode.skipsWelcomeMarkHook
        #else
        return true
        #endif
    }

    @State private var step: Int = {
        #if DEBUG
        if DemoMode.isActive, let initial = DemoMode.onboardingStep, (1...3).contains(initial) {
            return initial
        }
        #endif
        return 1
    }()
    /// La marca va quieta: ya dibujada desde el primer fotograma.
    private let drawn: CGFloat = 1
    @State private var showAlertsGuide = false
    @Namespace private var dotsNamespace

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar

                // Con piezas, `.launchWelcomeMark()` apunta este marco para que la marca del primer arranque aterrice
                // encima (sin «ONYX») y enmascara esta marca hasta el fotograma exacto del relevo (una sola marca en
                // cada fotograma, sin parpadeo). Con solo fundido o tras el bloqueo, sigue mandando `WelcomeReveal`.
                let markVisible = markShown || handedOffFromLaunch
                Group {
                    if usesWelcomeMarkHook {
                        AppMark(size: 58, drawn: drawn)
                            .launchWelcomeMark()
                    } else {
                        AppMark(size: 58, drawn: drawn)
                    }
                }
                .opacity(markVisible ? 1 : 0)
                .animation(handedOffFromLaunch ? nil : (motion.reduce ? motion.fade : .easeOut(duration: motion.seconds(0.12))),
                           value: markVisible)
                .padding(.top, 12)
                .padding(.bottom, 16)

                ZStack {
                    if step == 1 {
                        OnboardingBalancesStep(model: model, arrived: welcomed) {
                            advance(to: 2)
                        }
                        .transition(stepTransition)
                    } else if step == 2 {
                        OnboardingAlertsStep(
                            onStartGuide: { showAlertsGuide = true },
                            onLater: { advance(to: 3) }
                        )
                        .transition(stepTransition)
                    } else {
                        OnboardingBanksStep(
                            onConnectNow: { onFinish(true) },
                            onStart: { onFinish(false) }
                        )
                        .transition(stepTransition)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background {
                ZStack {
                    Theme.canvas
                    WelcomeBands(active: welcomed)
                }
                .ignoresSafeArea()
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showAlertsGuide) {
                AlertsGuideView(model: model)
            }
        }
        .task {
            guard !welcomed else { return }
            // Sin bloqueo delante, lo que tapa la bienvenida al abrir la app es el arranque: empieza cuando el arranque
            // deja ver lo de debajo (el instante en que Inicio empezaría a montarse) y la marca propia cuando el arranque
            // ha terminado. Con el bloqueo delante, todo empieza al abrirse (ver `onChange`).
            let launch = LaunchTimeline(motion)
            let stretch = max(motion.timeMultiplier, 0.01)
            #if DEBUG
            let hold = DemoMode.launchHoldSeconds
            #else
            let hold = 0.0
            #endif
            try? await Task.sleep(for: .seconds(hold + max(0.05, launch.assembleAt * stretch)))
            reveal.handle(.launchRevealsBelow(locked: lockedNow))
            try? await Task.sleep(for: .seconds(max(0, launch.duration - launch.assembleAt) * stretch))
            reveal.handle(.launchFinished(locked: lockedNow))
            // Con el bloqueo delante, lo que sigue lo hace su apertura (`onChange` de `shell.locked`, que da la carcasa:
            // ya no hace falta mirar la puerta cada medio segundo).
        }
        .onChange(of: shell.token) { _, token in
            // Sincroniza el inicio de bandas y piezas con el instante exacto en que `LaunchSequence` llama a `onAssemble`
            // (también tras un toque que salta el arranque o con `-MiBancoDemoLaunchHold`).
            guard token > 0, !welcomed else { return }
            reveal.handle(.launchRevealsBelow(locked: lockedNow))
        }
        .onChange(of: launchAnchor?.flyingToWelcome, initial: true) { _, flying in
            if flying == true {
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { handedOffFromLaunch = true }
            }
        }
        .onChange(of: shell.locked, initial: true) { old, locked in
            lockedNow = locked
            guard old, !locked else { return }
            unlocked()
        }
    }

    /// El bloqueo se ha abierto: la bienvenida empieza (si no lo había hecho) y la marca propia aparece cuando la del
    /// bloqueo termina su vuelo; también si la bienvenida ya había empezado y el bloqueo entró durante la espera del final
    /// del arranque (menor m-3 del lote 3: antes la marca se quedaba escondida para siempre).
    private func unlocked() {
        guard reveal.handle(.unlocked) == .waitForUnlockFlight else { return }
        let launch = LaunchTimeline(motion)
        let flight = max(0, launch.duration - (launch.flightAt ?? launch.duration)) * max(motion.timeMultiplier, 0.01)
        Task {
            try? await Task.sleep(for: .seconds(flight))
            reveal.handle(.unlockFlightLanded)
        }
    }

    private var topBar: some View {
        ZStack {
            HStack(spacing: 8) {
                ForEach(1...3, id: \.self) { index in
                    ZStack {
                        Capsule()
                            .fill(Theme.raised)
                            .frame(width: index == step ? 24 : 8, height: 8)
                        if index == step {
                            Capsule()
                                .fill(Theme.label)
                                .frame(width: 24, height: 8)
                                .matchedGeometryEffect(id: "onboarding-dot", in: dotsNamespace)
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Paso \(step) de 3")

            HStack {
                Spacer()
                Button {
                    onFinish(false)
                } label: {
                    Text("Saltar")
                        .titan(.option)
                        .foregroundStyle(Theme.label2)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding-skip")
            }
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.top, 8)
    }

    private var stepTransition: AnyTransition {
        if motion.reduce {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    private func advance(to nextStep: Int) {
        withAnimation(motion.animation(.snap)) {
            step = nextStep
        }
    }
}
