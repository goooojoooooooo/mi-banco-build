import SwiftUI
import MiBancoCore

/// Lo que una llegada enseña sobre la cifra grande de una tarjeta. `token` sube en cada llegada; `card` es la tarjeta
/// que lo enseña (la del banco si está delante; si no, «Todo»). Lo pone Inicio cuando el modelo ya ha publicado el
/// movimiento: la cifra rueda y esto aparece a la vez.
struct ArrivalPulse: Equatable {
    var token = 0
    var card: AccountCard = .all
    var amountCents = 0

    var isIncome: Bool { amountCents > 0 }
}

extension EnvironmentValues {
    @Entry var arrivalPulse = ArrivalPulse()
}

/// La respuesta de la cifra grande a una llegada (maqueta aprobada, `heroFeedback`):
/// - Pago: arriba a la derecha, un ✓ neutro en un aro de titanio con el importe («−4,80 €»). Entra desde 10 pt más
///   abajo y al 60 % con un muelle con rebote, el ✓ se traza, y a los 1,7 s se va subiendo 6 pt.
/// - Ingreso: lo mismo en verde, la cifra en verde 1,3 s y un halo verde detrás durante 1,5 s (sin halo en Bajo consumo).
/// - Con el ojo cerrado no hay insignia ni importe: la cifra (su máscara) late una vez al 105 %.
/// - Con Reducir movimiento la insignia se funde en su sitio, sin recorrido ni escala; los colores y el ✓ siguen.
/// Todo sale de `\.motion` (intensidad y cámara lenta) y solo cambian opacidad, escala y desplazamiento.
struct ArrivalHeroEffect: ViewModifier {
    let card: AccountCard
    /// La cifra en verde mientras dura el ingreso.
    @Binding var glowing: Bool

    @Environment(\.arrivalPulse) private var pulse
    @Environment(\.motion) private var motion
    @Environment(AppPreferences.self) private var preferences
    @State private var displayed: ArrivalPulse?
    @State private var beat = 0
    @State private var halo = 0

    func body(content: Content) -> some View {
        let hidden = preferences.privateMode
        content
            .background(alignment: .leading) {
                ArrivalHalo(trigger: halo)
            }
            .modifier(HeroBeat(trigger: beat))
            .overlay(alignment: .topTrailing) {
                if let displayed, !hidden {
                    ArrivalBadge(pulse: displayed)
                        .id(displayed.token)
                        .offset(y: -14)
                }
            }
            .onChange(of: pulse.token) { _, _ in react(hidden: hidden) }
            .onChange(of: hidden) { _, nowHidden in
                // Cerrar el ojo a media llegada: el importe de la insignia desaparece en el acto.
                if nowHidden {
                    displayed = nil
                    glowing = false
                }
            }
    }

    private func react(hidden: Bool) {
        let current = pulse
        guard current.card == card else { return }
        if hidden {
            // Con el ojo cerrado, solo un latido de la cifra (que es una máscara): ni importe ni signo.
            if !motion.reduce { beat += 1 }
            #if DEBUG
            HomeProbe.shared.arrivalPulses += 1
            #endif
            return
        }
        displayed = current
        #if DEBUG
        HomeProbe.shared.arrivalBadges += 1
        #endif
        if current.isIncome {
            if motion.richEffects { halo += 1 }
            glowing = true
        }
        let token = current.token
        let greenFor = motion.seconds(1.3)
        let badgeFor = motion.seconds(motion.reduce ? 2.2 : 2.1)
        Task {
            try? await Task.sleep(for: .seconds(greenFor))
            // El verde vuelve a blanco con un fundido de 0,3 s, nunca de golpe.
            if displayed?.token == token {
                withAnimation(.easeInOut(duration: motion.seconds(0.3))) { glowing = false }
            }
            try? await Task.sleep(for: .seconds(max(0.01, badgeFor - greenFor)))
            // La insignia ya es invisible: se desmonta (no queda un importe suelto en la pantalla).
            if displayed?.token == token { displayed = nil }
        }
    }
}

/// El latido de la cifra con el ojo cerrado: 105 % y vuelta.
private struct HeroBeat: ViewModifier {
    let trigger: Int
    @Environment(\.motion) private var motion

    func body(content: Content) -> some View {
        let up = motion.seconds(0.14)
        let spec = MotionMath.scaled(SpringToken.release.base, level: motion.level, timeMultiplier: motion.timeMultiplier)
        let spring = Spring(response: spec.response, dampingRatio: spec.dampingFraction)
        let back = spec.response * 2.2
        content.keyframeAnimator(initialValue: 1.0, trigger: trigger) { view, scale in
            view.scaleEffect(scale, anchor: .leading)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(1.05, duration: up)
                SpringKeyframe(1.0, duration: back, spring: spring)
            }
        }
    }
}

/// El halo verde detrás de la cifra: sube en 0,47 s y se apaga en otros 0,47 s. Es un degradado fijo; solo cambia su
/// opacidad.
private struct ArrivalHalo: View {
    let trigger: Int
    @Environment(\.motion) private var motion

    var body: some View {
        let half = motion.seconds(0.47)
        EllipticalGradient(
            colors: [Theme.income.opacity(0.34), Theme.income.opacity(0)],
            center: UnitPoint(x: 0.4, y: 0.6), startRadiusFraction: 0, endRadiusFraction: 0.68)
            .padding(.leading, -20)
            .padding(.vertical, -10)
            .padding(.trailing, 70)
            .keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, opacity in
                view.opacity(opacity)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(1.0, duration: half)
                    CubicKeyframe(0.0, duration: half)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// La insignia: ✓ en su aro y el importe con signo. Se monta al llegar y corre una sola secuencia de fotogramas clave
/// (aparece, se traza el ✓, espera, se va); empieza y acaba invisible.
private struct ArrivalBadge: View {
    let pulse: ArrivalPulse

    @Environment(\.motion) private var motion
    @State private var run = 0
    /// El ✓ se traza una vez, al poco de aparecer (con Reducir movimiento sale entero).
    @State private var checked = false

    private struct Values {
        var opacity = 0.0
        var scale = 1.0
        var y: CGFloat = 0
    }

    var body: some View {
        let reduce = motion.reduce
        let income = pulse.isIncome
        let tint: Color = income ? Theme.income : Color(hex: "#D6D8DC")
        // Tiempos de la maqueta (Equilibrado), con la intensidad y la cámara lenta aplicadas.
        let fadeIn = motion.seconds(reduce ? 0.2 : 0.14)
        let visibleFor = motion.seconds(reduce ? 1.8 : 1.7)
        let fadeOut = motion.seconds(reduce ? 0.3 : 0.32)
        let spec = MotionMath.scaled(SpringSpec(response: 0.42, dampingFraction: 0.62), level: motion.level,
                                     timeMultiplier: motion.timeMultiplier)
        let spring = Spring(response: spec.response, dampingRatio: spec.dampingFraction)
        let settle = min(spec.response * 2.2, visibleFor * 0.8)
        let rise: CGFloat = motion.distance(10)
        let lift: CGFloat = motion.distance(6)
        let startScale: Double = reduce ? 1 : 0.6
        let checkWait = motion.seconds(0.12)
        let checkDraw = motion.seconds(0.34)

        HStack(spacing: 6) {
            ring(income: income, tint: tint)
                .frame(width: 26, height: 26)
            Text(signedEUR(pulse.amountCents))
                // Un punto más que «3 cuentas»: se lee en el 1,7 s que está a la vista.
                .font(.system(size: 15, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(income ? Theme.income : Theme.card2)
                .lineLimit(1)
                .fixedSize()
                .privacySensitive()
        }
        .keyframeAnimator(initialValue: Values(), trigger: run) { view, value in
            view
                .scaleEffect(value.scale, anchor: .trailing)
                .offset(y: value.y)
                .opacity(value.opacity)
        } keyframes: { _ in
            KeyframeTrack(\.opacity) {
                LinearKeyframe(1.0, duration: fadeIn)
                LinearKeyframe(1.0, duration: max(0.01, visibleFor - fadeIn))
                LinearKeyframe(0.0, duration: fadeOut)
            }
            KeyframeTrack(\.scale) {
                MoveKeyframe(startScale)
                SpringKeyframe(1.0, duration: settle, spring: spring)
            }
            KeyframeTrack(\.y) {
                MoveKeyframe(rise)
                SpringKeyframe(0, duration: settle, spring: spring)
                LinearKeyframe(0, duration: max(0.01, visibleFor - settle))
                CubicKeyframe(-lift, duration: fadeOut)
            }
        }
        .onAppear {
            run += 1
            if reduce {
                checked = true
            } else {
                withAnimation(.easeOut(duration: checkDraw).delay(checkWait)) { checked = true }
            }
        }
        .allowsHitTesting(false)
        // Para VoiceOver el carrusel es un solo elemento (la llegada se anuncia aparte); esto solo lo ven las pruebas.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(income ? "Ingreso" : "Pago")
        .accessibilityIdentifier("arrival-feedback")
    }

    /// El aro (titanio fino en un pago; verde con relleno suave en un ingreso) y el ✓ que se traza.
    private func ring(income: Bool, tint: Color) -> some View {
        ZStack {
            if income {
                Circle().fill(Theme.income.opacity(0.16))
                Circle().strokeBorder(Theme.income.opacity(0.7), lineWidth: 1.2)
            } else {
                Circle().strokeBorder(tint.opacity(0.45), lineWidth: 1.2)
            }
            CheckShape()
                .trim(from: 0, to: checked ? 1 : 0)
                .stroke(tint, style: StrokeStyle(lineWidth: income ? 2.6 : 2.4, lineCap: .round, lineJoin: .round))
                .padding(4)
        }
    }
}
