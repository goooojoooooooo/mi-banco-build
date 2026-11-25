import SwiftUI
import MiBancoCore

/// Teclado numérico propio de «Mover dinero»: teclas ≥ 44×52 pt que se hunden como el cristal.
/// `KeypadAmount` vive en `MiBancoCore` (U26); las teclas ignoradas disparan háptica de error.
/// Cada tecla cambia el importe dentro de un muelle de `\.motion` (con Reducir movimiento, un fundido): la cifra de
/// arriba (`KeypadAmountDisplay`) hace con él su entrada dígito a dígito.
struct AmountKeypad: View {
    @Binding var amount: KeypadAmount
    @Environment(\.motion) private var motion
    @ScaledMetric(relativeTo: .title2) private var digitSize: CGFloat = 24
    @ScaledMetric(relativeTo: .title2) private var iconSize: CGFloat = 20
    @State private var tapTick = 0
    @State private var errorTick = 0

    private let rows: [[Key]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)],
        [.comma, .digit(0), .backspace],
    ]

    private enum Key: Hashable {
        case digit(Int)
        case comma
        case backspace

        var label: String {
            switch self {
            case .digit(let n): "\(n)"
            case .comma: ","
            case .backspace: "⌫"
            }
        }

        var spokenLabel: String {
            switch self {
            case .digit(let n): "\(n)"
            case .comma: "Coma decimal"
            case .backspace: "Borrar"
            }
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { key in
                        Button {
                            press(key)
                        } label: {
                            Group {
                                if key == .backspace {
                                    Image(systemName: "delete.left")
                                        .font(.system(size: iconSize, weight: .medium))
                                } else {
                                    Text(key.label)
                                        .font(.system(size: digitSize, weight: .medium))
                                        .monospacedDigit()
                                }
                            }
                            .foregroundStyle(Theme.label)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.logoLarge, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.logoLarge, style: .continuous))
                        }
                        .buttonStyle(.glassPress)
                        .accessibilityLabel(key.spokenLabel)
                        .accessibilityIdentifier(key == .backspace ? "keypad-backspace" : key.label)
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: tapTick)
        .sensoryFeedback(Haptics.error, trigger: errorTick)
    }

    private func press(_ key: Key) {
        #if DEBUG
        // Solo demo (`-MiBancoDemoKeypadDelay <s>`): la tecla hace efecto un instante después del toque, para que la
        // ráfaga de fotogramas ya esté en marcha cuando el dígito entra.
        if let delay = DemoMode.keypadDelay {
            Task {
                try? await Task.sleep(for: .seconds(delay))
                handle(key)
            }
            return
        }
        #endif
        handle(key)
    }

    private func handle(_ key: Key) {
        var changed = false
        withAnimation(KeypadAmountDisplay.reflow(motion)) {
            switch key {
            case .digit(let n): changed = amount.tapDigit(n)
            case .comma: changed = amount.tapComma()
            case .backspace: changed = amount.backspace()
            }
        }
        if changed {
            tapTick += 1
        } else {
            errorTick += 1
        }
    }
}

/// El importe que se teclea, dígito a dígito (maqueta aprobada, `kpRender`): el dígito nuevo entra desde 14 pt más
/// abajo, al 45 %, apareciendo; los demás le hacen sitio con un muelle; el punto de millar aparece creciendo desde el
/// 20 %; un dígito borrado se va hacia arriba encogiéndose. El «€» va más pequeño y en gris.
/// - Con el ojo cerrado cada dígito es un punto («••,• €»): se ve que se teclea, nunca qué.
/// - Con Reducir movimiento los dígitos se funden en su sitio.
/// - Para VoiceOver y las pruebas es un solo texto con el importe entero («12,50 €», o «importe oculto»).
struct KeypadAmountDisplay: View {
    let amount: KeypadAmount
    let hidden: Bool
    /// Cuerpo de los dígitos (el «€» va al 60 %).
    let size: CGFloat

    @Environment(\.motion) private var motion

    /// El muelle con el que entra un dígito y los demás le hacen sitio (0,38 s, rebote 0,24 en Equilibrado).
    static func reflow(_ motion: MotionContext) -> Animation {
        guard !motion.reduce else { return motion.fade }
        let spec = MotionMath.scaled(SpringSpec(response: 0.38, dampingFraction: 0.76), level: motion.level,
                                     timeMultiplier: motion.timeMultiplier)
        return .spring(response: spec.response, dampingFraction: spec.dampingFraction)
    }

    private enum Kind { case digit, placeholder, separator, comma, euro }

    private struct Glyph: Identifiable {
        let id: String
        let text: String
        let kind: Kind
    }

    /// Las piezas del importe, cada una con una identidad que no cambia al teclear (el dígito n.º 2 sigue siendo el
    /// n.º 2): así el que entra es nuevo y los demás solo se desplazan.
    private var glyphs: [Glyph] {
        var out: [Glyph] = []
        let empty = amount.eurosText.isEmpty
        let euros = Array(empty ? "0" : amount.eurosText)
        for (index, character) in euros.enumerated() {
            let fromRight = euros.count - 1 - index
            if index > 0, fromRight % 3 == 2 {
                out.append(Glyph(id: "s\(fromRight)", text: ".", kind: .separator))
            }
            out.append(Glyph(id: empty ? "z" : "d\(index)", text: hidden ? "•" : String(character),
                             kind: empty ? .placeholder : .digit))
        }
        if amount.hasDecimal {
            out.append(Glyph(id: "c", text: ",", kind: .comma))
            for (index, character) in amount.centsText.enumerated() {
                out.append(Glyph(id: "f\(index)", text: hidden ? "•" : String(character), kind: .digit))
            }
        }
        out.append(Glyph(id: "e", text: "€", kind: .euro))
        return out
    }

    private var drawnText: String { glyphs.map(\.text).joined() }

    var body: some View {
        let spoken = hidden ? "importe oculto" : amount.typedText
        // Si el importe no cabe a su tamaño (texto muy grande), se dibuja más pequeño: nunca se corta.
        ViewThatFits(in: .horizontal) {
            cells(size)
            cells(size * 0.78)
            cells(size * 0.58)
        }
        .frame(maxWidth: .infinity)
        .privacySensitive()
        .accessibilityRepresentation {
            Text(spoken)
                .accessibilityIdentifier("move-amount-display")
        }
        #if DEBUG
        .onAppear { DrawnTextAudit.shared.record(drawnText, hidden: hidden) }
        .onChange(of: drawnText) { _, new in DrawnTextAudit.shared.record(new, hidden: hidden) }
        #endif
    }

    private func cells(_ size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: -size * 0.02) {
            ForEach(glyphs) { glyph in
                Text(glyph.text)
                    .font(.system(size: glyph.kind == .euro ? size * 0.6 : size, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(color(glyph.kind))
                    .padding(.leading, glyph.kind == .euro ? size * 0.14 : 0)
                    .transition(transition(glyph.kind))
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    private func color(_ kind: Kind) -> Color {
        switch kind {
        case .euro: Theme.label2
        case .placeholder: Theme.label3
        case .digit, .separator, .comma: amount.cents > 0 || amount.hasDecimal ? Theme.label : Theme.label3
        }
    }

    private func transition(_ kind: Kind) -> AnyTransition {
        guard !motion.reduce else { return .opacity }
        switch kind {
        case .separator:
            return .scale(scale: 0.2).combined(with: .opacity)
        case .digit, .comma:
            return .asymmetric(
                insertion: .scale(scale: 0.45).combined(with: .opacity).combined(with: .offset(y: motion.distance(14))),
                removal: .scale(scale: 0.6).combined(with: .opacity).combined(with: .offset(y: -motion.distance(8))))
        case .placeholder, .euro:
            return .opacity
        }
    }
}
