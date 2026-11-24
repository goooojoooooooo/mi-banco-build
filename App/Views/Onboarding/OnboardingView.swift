import MiBancoCore
import SwiftUI

/// Bienvenida de primera ejecución en tres pasos (Plan 4b, tarea 12).
/// Se muestra en lugar de la barra de pestañas mientras `model.needsOnboarding` es verdadero; el bloqueo queda por encima.
struct OnboardingView: View {
    let model: LedgerModel
    let onFinish: (_ openBanksSettings: Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step: Int = {
        #if DEBUG
        if DemoMode.isActive, let initial = DemoMode.onboardingStep, (1...3).contains(initial) {
            return initial
        }
        #endif
        return 1
    }()
    @State private var drawn: CGFloat = 0
    @State private var showAlertsGuide = false
    @Namespace private var dotsNamespace

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar

                AppMark(size: 58, drawn: drawn)
                    .padding(.top, 12)
                    .padding(.bottom, 16)

                ZStack {
                    if step == 1 {
                        OnboardingBalancesStep(model: model) {
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
            .background(Theme.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showAlertsGuide) {
                AlertsGuideView(model: model)
            }
        }
        .onAppear {
            if reduceMotion {
                drawn = 1
            } else {
                withAnimation(Theme.Motion.markDraw.delay(0.1)) {
                    drawn = 1
                }
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
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    private func advance(to nextStep: Int) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.cardSettle) {
            step = nextStep
        }
    }
}
