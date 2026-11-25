import SwiftUI
import MiBancoCore

/// C6 (IB): el aviso dentro de la app cuando llega un movimiento estando en otra pestaña (prototipo `bannerDrop`).
///
/// Cae desde 160 pt por encima con el muelle `release`; a los 0,95 s se despliega hacia abajo (se destapa, recortado
/// desde arriba: no cambia el tamaño de nada) y enseña «Te quedan», que rueda, y dos acciones; a los 3,4 s se recoge y
/// a los 3,65 s sube y se va. Con Reducir movimiento: aparece con un fundido, se despliega a los 0,9 s sin moverse y
/// se funde a los 3,2 s. Los tiempos son pausas de la interfaz (`motion.pause`: siguen la cámara lenta de las
/// grabaciones) y se encadenan con el final de animaciones propias, sin `Task.sleep`.
///
/// NUNCA es una hoja: va dentro de `RootView`, que está debajo del bloqueo y de la tapa; existe solo mientras
/// `ShellState.shownBanner` lo dice (se quita al bloquear y al salir de primer plano). Con el ojo cerrado, sus
/// importes son máscaras (`RollingAmount` lee el ojo). Tocarlo abre la misma hoja que la fila del movimiento.
struct InAppBanner: View {
    let arrival: Arrival
    /// «Te quedan»: el saldo de esa cuenta tras el movimiento (nil si no se conoce: entonces no se despliega esa línea).
    let left: Int?
    let onOpen: () -> Void
    let onNotMine: () -> Void
    let onFinished: () -> Void

    @Environment(\.motion) private var motion
    @State private var dropped = false
    @State private var open: CGFloat = 0
    @State private var leftRevealed = false
    @State private var clock: Double = 0
    @State private var headHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    private let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            head
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headHeight = $0 }
            if let left {
                details(left: left)
                    .opacity(Double(min(1, open * 1.4)))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: shape)
        .overlay(shape.strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
        // Se destapa de arriba abajo: la máscara (con las esquinas del aviso) se desplaza; el aviso no cambia de tamaño.
        .mask(alignment: .top) {
            shape.offset(y: -hiddenBottom)
        }
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        .padding(.horizontal, 10)
        .offset(y: dropped || motion.reduce ? 0 : -160)
        .opacity(motion.reduce ? (dropped ? 1 : 0) : 1)
        .animationClock(clock)
        .onAppear(perform: run)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("in-app-banner")
    }

    /// Lo que queda tapado por abajo: todo lo que no es la cabecera, menos lo ya desplegado.
    private var hiddenBottom: CGFloat {
        guard fullHeight > 0 else { return 0 }
        let extra = max(0, fullHeight - headHeight - 28)
        return extra * (1 - min(max(open, 0), 1))
    }

    private var head: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                BankLogo(bank: arrival.bank, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(arrival.title)
                        .titan(.option)
                        .foregroundStyle(Theme.label)
                        .lineLimit(1)
                    Text("\(arrival.bank.displayName) · ahora")
                        .titan(.meta)
                        .foregroundStyle(Theme.label2)
                }
                Spacer(minLength: 8)
                RollingAmount(cents: arrival.amountCents, style: .plain(sign: true))
                    .titan(.option)
                    .foregroundStyle(arrival.isIncome ? Theme.income : Theme.label)
            }
            .contentShape(Rectangle())
            .frame(minHeight: 44)
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("in-app-banner-open")
    }

    private func details(left: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Te quedan").foregroundStyle(Theme.label2)
                Spacer(minLength: 8)
                RollingAmount(cents: left, revealed: leftRevealed)
                    .foregroundStyle(Theme.label)
            }
            .titan(.option)
            HStack(spacing: 8) {
                bannerAction("Añadir nota", action: onOpen)
                bannerAction("No es mío", tint: Theme.warning, action: onNotMine)
            }
        }
    }

    private func bannerAction(_ title: String, tint: Color = Theme.label, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .titan(.captionStrong)
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(.white.opacity(0.08), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
    }

    // MARK: El guion

    /// Cae; a los 0,95 s se despliega y «Te quedan» rueda; a los 3,4 s se recoge; a los 3,65 s sube y se va.
    private func run() {
        if motion.reduce {
            withAnimation(motion.fade) { dropped = true }
            after(0.9) {
                leftRevealed = true
                open = 1
                after(2.3) {
                    withAnimation(motion.fade, completionCriteria: .logicallyComplete) { dropped = false } completion: {
                        onFinished()
                    }
                }
            }
            return
        }
        withAnimation(motion.animation(.release)) { dropped = true }
        after(0.95) {
            leftRevealed = true
            withAnimation(motion.animation(.snap)) { open = 1 }
            after(2.45) {
                withAnimation(.easeIn(duration: motion.pause(0.32))) { open = 0 }
                after(0.25) {
                    withAnimation(.easeIn(duration: motion.pause(0.4)), completionCriteria: .logicallyComplete) {
                        dropped = false
                    } completion: {
                        onFinished()
                    }
                }
            }
        }
    }

    /// Espera `seconds` (pausa de la interfaz, a la cámara lenta de las grabaciones) y sigue: el final de una animación
    /// propia de una vista vacía, no `Task.sleep`.
    private func after(_ seconds: Double, _ next: @escaping () -> Void) {
        withAnimation(.linear(duration: motion.pause(seconds)), completionCriteria: .removed) {
            clock = clock < 0.5 ? 1 : 0
        } completion: {
            next()
        }
    }
}
