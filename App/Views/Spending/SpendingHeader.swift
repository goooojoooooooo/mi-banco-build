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

/// Total del mes (cuenta desde el valor anterior al cambiar de mes) y sus dos frases: la comparación y la previsión.
struct SpendingTotal: View {
    let cents: Int
    let monthName: String

    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        HeroBalance(cents: cents, centsColor: Theme.label2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Gastado en \(monthName.lowercased()): \(spokenAmount(cents, hidden: preferences.privateMode))")
            .accessibilityIdentifier("gasto.total")
    }
}

/// Las frases bajo el total («78,40 € menos que en octubre a estas alturas»). Con el modo privado, los importes se tapan.
struct SpendingSentences: View {
    let comparison: String?
    let forecast: String?

    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let comparison { line(comparison, id: "gasto.comparacion") }
            if let forecast { line(forecast, id: "gasto.prevision") }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func line(_ text: String, id: String) -> some View {
        let hidden = preferences.privateMode
        return Text(hidden ? maskingAmounts(text) : text)
            .titan(.callout)
            .foregroundStyle(Theme.label2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(hidden ? maskingAmounts(text, with: "importe oculto") : text)
            .accessibilityIdentifier(id)
    }
}
