import SwiftUI
import MiBancoCore

/// Preferencia ascendente para ocultar el botón flotante de Nyx en pantallas con botones fijos abajo (p. ej. la guía).
struct NyxButtonHiddenPreferenceKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension EnvironmentValues {
    @Entry var nyxButtonHidden = false
}

extension View {
    /// Oculta el botón flotante de Nyx mientras esta pantalla está en pantalla (sube hasta `RootView`).
    func nyxButtonHidden(_ hidden: Bool = true) -> some View {
        self
            .preference(key: NyxButtonHiddenPreferenceKey.self, value: hidden)
            .environment(\.nyxButtonHidden, hidden)
    }
}

/// Botón flotante de presencia de Nyx (diseño §6.9, §6.12 y §6.13):
/// círculo negro de 52 pt con borde de titanio y la marca de Nyx; punto de novedades con un solo latido (1 → 1,08 → 1)
/// al aumentar `newCount` (con Reducir movimiento, fundido de 0,2 s sin latido).
struct NyxPresenceButton: View {
    let newCount: Int
    let hidden: Bool
    let onTap: () -> Void

    @Environment(\.motion) private var motion
    @State private var pulseTrigger = 0
    @State private var previousCount = 0

    private var accessibilityValueText: String {
        guard newCount > 0 else { return "" }
        if hidden {
            return "cosas nuevas"
        }
        return newCount == 1 ? "1 cosa nueva" : "\(newCount) cosas nuevas"
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(MarkPalette.body)
                    .overlay {
                        Circle()
                            .strokeBorder(MarkPalette.edge, lineWidth: 1)
                    }
                    .overlay {
                        WaveShape()
                            .stroke(
                                MarkPalette.wave,
                                style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round)
                            )
                            .frame(width: 28, height: 28)
                    }
                    .frame(width: 52, height: 52)
                    .shadow(color: .black.opacity(0.45), radius: 10, y: 4)

                if newCount > 0 {
                    Circle()
                        .fill(Theme.label)
                        .frame(width: 11, height: 11)
                        .overlay {
                            Circle()
                                .stroke(Theme.canvas, lineWidth: 2)
                        }
                        .offset(x: -1, y: 1)
                        .keyframeAnimator(initialValue: 1.0, trigger: motion.reduce ? 0 : pulseTrigger) { content, scale in
                            content.scaleEffect(scale)
                        } keyframes: { _ in
                            KeyframeTrack {
                                CubicKeyframe(1.08, duration: motion.seconds(0.14))
                                CubicKeyframe(1.0, duration: motion.seconds(0.20))
                            }
                        }
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 52, height: 52)
            .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .animation(motion.fade, value: newCount > 0)
        .onAppear {
            previousCount = newCount
            if newCount > 0 && !motion.reduce {
                pulseTrigger += 1
            }
        }
        .onChange(of: newCount) { _, current in
            if current > previousCount && !motion.reduce {
                pulseTrigger += 1
            }
            previousCount = current
        }
        .accessibilityIdentifier("nyx-button")
        .accessibilityLabel(assistantName)
        .accessibilityValue(accessibilityValueText)
        .accessibilityHint("Pregúntale o mira lo que ha visto")
        .accessibilityInputLabels([assistantName, "Asistente"])
    }
}
