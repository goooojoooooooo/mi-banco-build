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
    @Environment(\.presentationGate) private var gate
    /// La bienvenida ya está a la vista (el bloqueo se ha abierto o el arranque ha dejado ver lo de debajo): entonces
    /// cruzan las bandas y llegan las piezas. Si se jugara al montarse, pasaría entera detrás del bloqueo o del arranque.
    @State private var welcomed = false
    /// La marca propia ya se dibuja (la del arranque o la del bloqueo se ha ido).
    @State private var markShown = false

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

                // La marca propia no se dibuja mientras la del arranque (o la del bloqueo) sigue en pantalla volando:
                // nunca dos marcas a la vez (ojo de diseño 18.1). Aparece con un fundido corto cuando la otra se ha ido.
                AppMark(size: 58, drawn: drawn)
                    .opacity(markShown ? 1 : 0)
                    .animation(motion.reduce ? motion.fade : .easeOut(duration: motion.seconds(0.12)), value: markShown)
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
            // Sin bloqueo delante, lo que tapa la bienvenida al abrir la app es el arranque: se espera a que empiece a
            // dejar ver lo de debajo (el mismo instante en que Inicio empezaría a montarse). Con el bloqueo delante, la
            // bienvenida empieza al abrirse (ver `onChange`).
            let launch = LaunchTimeline(motion)
            let stretch = max(motion.timeMultiplier, 0.01)
            let wait = launch.assembleAt * stretch
            try? await Task.sleep(for: .seconds(max(0.05, wait)))
            if gate?.isLocked == true {
                // Con el bloqueo delante la bienvenida empieza al abrirse (`onChange`). Respaldo (menor m-13): si ese
                // aviso no llegara, se mira cada medio segundo (como mucho 10 min) el bloqueo DE VERDAD (la puerta es
                // un objeto vivo; el `scenePhase` copiado en esta tarea no lo sería) y empieza en cuanto se abre; nunca
                // se queda sin jugar ni con la marca escondida.
                for _ in 0..<1_200 {
                    try? await Task.sleep(for: .seconds(0.5))
                    if Task.isCancelled || welcomed { return }
                    if gate?.isLocked != true { break }
                }
                guard !welcomed, gate?.isLocked != true else { return }
                welcomed = true
                markShown = true
                return
            }
            welcomed = true
            // La marca propia, cuando la del arranque ya ha terminado su vuelo y se ha ido.
            try? await Task.sleep(for: .seconds(max(0, launch.duration - launch.assembleAt) * stretch))
            if gate?.isLocked != true { markShown = true }
        }
        .onChange(of: gate?.isLocked) { old, locked in
            guard old == true, locked != true, !welcomed else { return }
            welcomed = true
            // Al abrirse el bloqueo, su marca vuela a su sitio: la propia aparece cuando ese vuelo ha terminado.
            let launch = LaunchTimeline(motion)
            let flight = max(0, launch.duration - (launch.flightAt ?? launch.duration)) * max(motion.timeMultiplier, 0.01)
            Task {
                try? await Task.sleep(for: .seconds(flight))
                markShown = true
            }
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
