import SwiftUI
import MiBancoCore

/// El selector de mes: «‹ Noviembre ›». Dos botones de 44 pt (con su forma como zona de toque) y el nombre del mes,
/// que se funde al cambiar. Los extremos (el mes más antiguo y el actual) quedan desactivados.
struct MonthSelector: View {
    let title: String
    let canGoBack: Bool
    let canGoForward: Bool
    let step: (Int) -> Void

    var body: some View {
        // Flechas en los extremos (la izquierda alineada con el título grande) y el mes centrado entre ambas.
        HStack(spacing: 0) {
            arrow("chevron.left", label: "Mes anterior", id: "gasto.mesAnterior", enabled: canGoBack) { step(-1) }
            Spacer(minLength: 0)
            ZStack {
                Text(title)
                    .titan(.cardTitle)
                    .foregroundStyle(Theme.label)
                    .id(title)
                    .transition(.opacity)
            }
            .frame(minHeight: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Mes: \(title)")
            .accessibilityIdentifier("gasto.mes")
            Spacer(minLength: 0)
            arrow("chevron.right", label: "Mes siguiente", id: "gasto.mesSiguiente", enabled: canGoForward) { step(1) }
        }
    }

    private func arrow(_ symbol: String, label: String, id: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(enabled ? Theme.label : Theme.passive)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.9))
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

/// Total del mes: la cifra protagonista del kit (`RollingAmount`). Rueda desde 0 al entrar en la pestaña y del valor
/// anterior al nuevo al cambiar de mes; con el ojo cerrado, «•••,•• €» y nunca una cifra.
struct SpendingTotal: View {
    let cents: Int
    let monthName: String

    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        RollingAmount(cents: cents, style: .hero(euros: 50, cents: 26, centsColor: Theme.label2))
            .foregroundStyle(Theme.label)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Gastado en \(monthName.lowercased()): \(spokenAmount(cents, hidden: preferences.privateMode))")
            .accessibilityIdentifier("gasto.total")
    }
}

/// Las frases bajo el total («78,40 € menos que en octubre a estas alturas»). Con el modo privado, los importes se tapan:
/// la frase con cifras se quita de golpe (nunca se funde encima de la tapada) y la tapada no monta ninguna cifra.
/// La previsión («…en unos 1.290 €») cuenta su cifra desde 0 al entrar.
struct SpendingSentences: View {
    let comparison: String?
    let forecast: String?

    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let comparison { line(comparison, id: "gasto.comparacion", counts: false) }
            if let forecast { line(forecast, id: "gasto.prevision", counts: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func line(_ text: String, id: String, counts: Bool) -> some View {
        let hidden = preferences.privateMode
        return ZStack(alignment: .topLeading) {
            if hidden {
                Text(maskingAmounts(text))
                    .transition(.identity)
            } else if counts {
                CountingWholeEuros(text: text)
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
            } else {
                Text(text)
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
            }
        }
        .titan(.callout)
        .foregroundStyle(Theme.label2)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hidden ? maskingAmounts(text, with: "importe oculto") : text)
        .accessibilityIdentifier(id)
    }
}

/// Una frase con un importe en euros enteros («A este ritmo terminarás el mes en unos 1.290 €»): la cifra cuenta desde 0
/// la primera vez que se ve y cada vez que se entra en la pestaña (1 s de desaceleración, tras 0,16 s), con los tiempos
/// del kit (`\.motion`: intensidad, cámara lenta, Reducir movimiento). El resto de la frase no se mueve y las cifras son
/// tabulares. `RollingAmount` escribe siempre los céntimos y esta cifra no los lleva: por eso cuenta como texto.
/// Solo se monta con el ojo abierto (quien la usa enseña la frase tapada si no).
private struct CountingWholeEuros: View {
    let text: String

    @Environment(\.motion) private var motion
    @Environment(\.entrance) private var entrance
    /// La entrada por capas en la que la cifra ya ha arrancado; nil = aún no ha contado nunca.
    @State private var landed: Int?

    var body: some View {
        let split = WholeEuroSplit(text)
        Group {
            if let split {
                WholeEuroFigure(euros: drawn(split.euros), split: split)
                    .animation(motion.reduce ? nil : count, value: split.euros)
            } else {
                Text(text)
            }
        }
        .onAppear { start() }
        // Entrada nueva: la cifra, que ya está en 0 (`drawn`), cuenta otra vez.
        .onChange(of: entrance.token) { _, _ in start() }
    }

    private var count: Animation {
        .timingCurve(0.16, 1, 0.3, 1, duration: motion.seconds(1.0)).delay(motion.seconds(0.16))
    }

    private var replays: Bool { entrance.active && entrance.scope == .assembly }

    /// 0 hasta que arranca (y desde que empieza una entrada nueva hasta que arranca en ella); después, la cifra.
    private func drawn(_ euros: Int) -> Double {
        guard !motion.reduce else { return Double(euros) }
        guard let landed else { return 0 }
        return replays && landed != entrance.token ? 0 : Double(euros)
    }

    private func start() {
        guard !motion.reduce else { return }
        let token = entrance.token
        withAnimation(count) { landed = token }
    }
}

/// Dibuja la frase con la cifra animada en su sitio. `Animatable`: SwiftUI interpola `euros` y dibuja cada fotograma.
private struct WholeEuroFigure: View, Animatable {
    var euros: Double
    let split: WholeEuroSplit

    nonisolated var animatableData: Double {
        get { euros }
        set { euros = newValue }
    }

    var body: some View {
        Text(split.prefix + formatEURWhole(Int(euros.rounded()) * 100) + split.suffix)
    }
}

/// El último importe en euros enteros de una frase («1.290 €», sin decimales), separado del texto de antes y de después.
struct WholeEuroSplit: Equatable {
    let prefix: String
    let euros: Int
    let suffix: String

    init?(_ text: String) {
        let chars = Array(text)
        guard let euro = chars.lastIndex(of: "€"), euro >= 2,
              chars[euro - 1] == "\u{00A0}" || chars[euro - 1] == " " else { return nil }
        let end = euro - 1
        var start = end
        while start > 0, chars[start - 1].isASCII, chars[start - 1].isNumber || chars[start - 1] == "." { start -= 1 }
        // Un importe con céntimos («78,40 €») no es de euros enteros.
        guard start < end, !(start > 0 && chars[start - 1] == ","),
              let euros = Int(String(chars[start..<end]).replacingOccurrences(of: ".", with: "")) else { return nil }
        prefix = String(chars[..<start])
        self.euros = euros
        suffix = String(chars[(euro + 1)...])
    }
}
