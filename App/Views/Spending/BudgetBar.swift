import SwiftUI
import MiBancoCore

/// «77 de 90 €  85 %» y la barra del kit (`FillBar`): se llena con un muelle que se pasa un poco, en escalera con las
/// demás, y desde el 90 % va en ámbar (la barra y su porcentaje a la vez: el texto toma el color de la barra). Cruzar el 90 % mientras se ve (un pago que llega, un límite que se cambia) trae el
/// fundido a ámbar, un pulso y una vibración de aviso, una sola vez por cruce; una barra que ya nace pasada sale en ámbar
/// sin pulso ni vibración. Con Reducir movimiento la barra se funde y el color se queda. Un presupuesto de 0 es una barra
/// vacía y sin aviso. Un solo elemento para VoiceOver.
struct BudgetBar: View {
    let status: BudgetStatus
    /// Nombre del presupuesto para VoiceOver ("Presupuesto del mes", "Presupuesto de Comer fuera").
    let name: String
    /// Orden: escalona el llenado de la barra.
    var index = 0
    /// Margen a la derecha de «77 de 90 €  85 %» (en Presupuestos, el porcentaje se alinea con el texto del campo).
    var textTrailingInset: CGFloat = 0

    /// A partir de aquí la barra (y su porcentaje) van en ámbar.
    static let warnAt = 0.9

    @Environment(AppPreferences.self) private var preferences
    @Environment(\.motion) private var motion
    /// Cruces del aviso vistos por esta barra (cada uno, una vibración).
    @State private var warnings = 0
    /// El color que la barra dibuja de verdad (ámbar o no): lo dice `FillBar`, no el dato.
    @State private var barWarned = false

    private var exceeded: Bool { status.level == .exceeded }

    /// Gastado sobre el límite, sin limpiar: con límite 0 no es un número y la barra lo trata como 0 (`MotionMath.finite`).
    private var fraction: Double { Double(status.spentCents) / Double(status.limitCents) }

    var body: some View {
        // Con el ojo cerrado no se monta ninguna cifra: «••• de ••• €» y «•• %», no un desenfoque.
        let hidden = preferences.privateMode
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(hidden ? "••• de •••\u{00A0}€" : amounts)
                    .titan(.callout)
                    .foregroundStyle(Theme.label2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Text(hidden ? "••\u{00A0}%" : "\(status.percent)\u{00A0}%")
                    .titan(.callout)
                    .fontWeight(.medium)
                    // El porcentaje va del color de la barra y cambia con ella: mismo instante, mismo fundido.
                    .foregroundStyle(barWarned ? Theme.warning : Theme.label)
                    .animation(motion.calmAnimation(.row), value: barWarned)
            }
            .padding(.trailing, textTrailingInset)
            .contentTransition(.identity)
            .privacySensitive()
            // Presupuestos entran 0,38 s después de empezar y luego una tras otra (48 ms × 0,86ⁿ), como en la maqueta.
            FillBar(fraction: fraction, warnAt: Self.warnAt, label: name,
                    delay: 0.38 + MotionMath.staggerDelays(count: index + 1, firstGap: 0.048, decay: 0.86)[index],
                    onWarn: { warnings += 1 }, onWarnedChange: { barWarned = $0 })
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityValue(debugValue)
    }

    /// «77 de 90 €»: el gastado sin el símbolo y el límite con él.
    private var amounts: String {
        let spent = formatEURWhole(status.spentCents).replacingOccurrences(of: "\u{00A0}€", with: "")
        return "\(spent) de \(formatEURWhole(status.limitCents))"
    }

    private var spoken: String {
        let hidden = preferences.privateMode
        let base = "\(name): \(spokenAmount(status.spentCents, hidden: hidden)) de \(spokenAmount(status.limitCents, hidden: hidden))"
        let level = exceeded ? ", límite superado" : ""
        return hidden ? base + level : "\(base), \(status.percent) por ciento\(level)"
    }

    /// Solo en la demo con `-MiBancoDemoBudgetWarnings`: cuántos avisos ha dado esta barra y si DIBUJA el ámbar (el
    /// estado real de la barra, no el dato), para la prueba de toque (una vibración no se puede observar desde fuera).
    /// En la app de verdad, nada.
    private var debugValue: String {
        #if DEBUG
        if DemoMode.isActive, DemoMode.exposesBudgetWarnings {
            return "avisos \(warnings), \(barWarned ? "ámbar" : "blanca")"
        }
        #endif
        return ""
    }
}
