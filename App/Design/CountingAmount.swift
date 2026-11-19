import SwiftUI
import MiBancoCore

/// Un importe que cuenta: la primera vez que se ve sube desde 0 (1 s, desaceleración fuerte) y en cada cambio
/// rueda desde el valor anterior (1,1 s). Cifras tabulares, así que nada tiembla. Con Reducir movimiento, salta.
/// Lo que se anima es un `Double` que la vista dibuja en cada fotograma: es texto, sin capas ni desenfoques.
struct CountingAmount: View {
    let cents: Int
    /// true = empieza en 0 y cuenta hasta `cents` cuando `revealed` pasa a true.
    var countsUp = true
    /// Para cifras fuera de la vista (la tarjeta aún no visible): cuenta cuando aparece.
    var revealed = true
    var style: Style = .plain(sign: false)

    enum Style: Equatable {
        /// "1.284,55 €" (con signo "−"/"+" si `sign`).
        case plain(sign: Bool)
        /// Euros grandes y ",75 €" pequeños en otro color: la cifra protagonista.
        case hero(euros: CGFloat, cents: CGFloat, centsColor: Color)
    }

    @State private var shown: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Al montar Inicio por capas (arranque, desbloqueo) o abrir la hoja, la cifra vuelve a contar desde 0.
    @Environment(\.entrance) private var entrance

    var body: some View {
        AmountFigure(value: shown ?? (countsUp && !reduceMotion ? 0 : Double(cents)), style: style)
            .onAppear(perform: start)
            .onChange(of: revealed) { _, _ in start() }
            .onChange(of: entrance.token) { _, _ in recount() }
            .onChange(of: cents) { _, new in
                guard shown != nil else { return start() }
                if reduceMotion {
                    shown = Double(new)
                } else {
                    // Rueda desde lo que se ve (interrumpible: si cambia otra vez, sigue desde el valor intermedio).
                    withAnimation(Theme.Motion.roll) { shown = Double(new) }
                }
            }
    }

    /// Dos pasos: primero 0 (sin animación, la capa aún está oculta) y en el siguiente ciclo, la cuenta.
    private func recount() {
        guard entrance.active, entrance.scope == .assembly, countsUp, revealed, !reduceMotion else { return }
        shown = 0
        let target = Double(cents)
        Task {
            try? await Task.sleep(for: .milliseconds(20))
            withAnimation(Theme.Motion.countUp.delay(0.15)) { shown = target }
        }
    }

    private func start() {
        guard shown == nil, revealed else { return }
        guard countsUp, !reduceMotion else {
            shown = Double(cents)
            return
        }
        shown = 0
        withAnimation(Theme.Motion.countUp) { shown = Double(cents) }
    }
}

/// Dibuja el valor animado. `Animatable`: SwiftUI interpola `value` y llama a `body` en cada fotograma.
private struct AmountFigure: View, Animatable {
    var value: Double
    let style: CountingAmount.Style

    nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        let cents = Int(value.rounded())
        switch style {
        case .plain(let sign):
            Text(sign ? signedEUR(cents) : formatEUR(cents).replacingOccurrences(of: "-", with: "−"))
        case let .hero(euros, small, color):
            let parts = splitEUR(cents)
            Text("\(Text(parts.main).font(.system(size: euros, weight: .semibold)))\(Text(parts.small).font(.system(size: small, weight: .semibold)).foregroundStyle(color))")
                .tracking(-euros * 0.03)
        }
    }
}

/// "−12,50 €" / "+1.450,00 €" (signo tipográfico, no guion).
func signedEUR(_ cents: Int) -> String {
    (cents < 0 ? "−" : "+") + formatEUR(abs(cents))
}

/// "3.774,75 €" -> ("3.774", ",75 €"); en negativo, el signo va con los euros.
func splitEUR(_ cents: Int) -> (main: String, small: String) {
    let s = formatEUR(abs(cents))
    let sign = cents < 0 ? "−" : ""
    guard let i = s.lastIndex(of: ",") else { return (sign + s, "") }
    return (sign + String(s[..<i]), String(s[i...]))
}
