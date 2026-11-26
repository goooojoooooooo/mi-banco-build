import SwiftUI
import MiBancoCore

/// Pinta una línea del resumen o del asistente a partir de `[BriefingPart]`.
/// - En modo normal, usa `AttributedString` con verde `Theme.income` en variaciones positivas, signo menos tipográfico
///   (`−`, U+2212) y cifras tabulares. Si `countsFirstAmount` está activo (total de «Tu dinero»), el primer importe rueda
///   desde 0 con `RollingAmount` (obedece la intensidad y la cámara lenta de grabación) sin mover el resto de la frase:
///   la frase se trocea en palabras que fluyen igual que el texto y el importe es una pieza más. Con Reducir movimiento
///   o si el dueño saltó la entrada, la frase es texto corrido, sin cuenta.
/// - En modo privado, sustituye cada parte numérica y cualquier importe o porcentaje incrustado por «•••», sin exponer
///   jamás «€» ni «%» ni en pantalla ni en VoiceOver. En ese modo no se monta ningún importe que ruede.
struct BriefingLineView: View {
    let parts: [BriefingPart]
    var role: TitanFont = .row
    var color: Color = Theme.label
    var countsFirstAmount: Bool = false
    var snapCountImmediately: Bool = false

    @Environment(AppPreferences.self) private var preferences
    @Environment(\.motion) private var motion

    var body: some View {
        let hidden = preferences.privateMode
        let label = Self.accessibleText(for: parts, hidden: hidden)
        Group {
            if hidden {
                Text(Self.maskedVisualText(for: parts))
                    .foregroundStyle(color)
            } else if countsFirstAmount, !motion.reduce, !snapCountImmediately,
                      let sentence = RollingSentence(parts: parts, baseColor: color) {
                SentenceFlow {
                    ForEach(sentence.items) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            ForEach(item.pieces) { piece in
                                switch piece.kind {
                                case .text(let text):
                                    Text(text)
                                case .amount(let cents):
                                    RollingAmount(cents: cents).foregroundStyle(color)
                                }
                            }
                        }
                    }
                }
                // Una sola etiqueta para toda la frase (la de siempre), no una por palabra.
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isStaticText)
            } else {
                Text(Self.attributed(parts: parts, overrideFirstAmount: nil, baseColor: color))
            }
        }
        .titan(role)
        .fixedSize(horizontal: false, vertical: true)
        .privacySensitive()
        .accessibilityLabel(label)
    }

    /// Texto pintado en modo privado: conserva «•••» y oculta cualquier importe o porcentaje incrustado en texto libre.
    static func maskedVisualText(for parts: [BriefingPart]) -> String {
        render(parts, .masked).replacingOccurrences(
            of: "[+\\-\u{2212}]?[0-9][0-9.,]*[ \u{00A0}\u{202F}]*(?:€|%)",
            with: "•••",
            options: .regularExpression
        )
    }

    /// Etiqueta hablada para VoiceOver: en privado sustituye importes, porcentajes y «•••» por «importe oculto» (U36).
    static func accessibleText(for parts: [BriefingPart], hidden: Bool) -> String {
        guard hidden else { return render(parts, .plain) }
        return privateSpokenText(render(parts, .masked))
    }

    static func attributed(parts: [BriefingPart], overrideFirstAmount: Int?, baseColor: Color) -> AttributedString {
        var out = AttributedString()
        var usedOverride = false
        for part in parts {
            let chunk: String
            var tint = baseColor
            switch part {
            case .text(let text):
                chunk = text
            case .amount(let cents):
                let value: Int
                if let overrideFirstAmount, !usedOverride {
                    usedOverride = true
                    value = overrideFirstAmount
                } else {
                    value = cents
                }
                chunk = uniformMinus(formatEUR(value))
            case .signed(let cents):
                chunk = uniformMinus(formatSignedEUR(cents))
                if cents > 0 { tint = Theme.income }
            case .whole(let cents):
                chunk = uniformMinus(formatEURWhole(cents))
            case .percentTenths(let tenths):
                chunk = uniformMinus(formatPercentTenths(tenths, signed: true))
                if tenths > 0 { tint = Theme.income }
            }
            var segment = AttributedString(chunk)
            segment.foregroundColor = tint
            out.append(segment)
        }
        return out
    }

    private static func uniformMinus(_ text: String) -> String {
        text.hasPrefix("-") ? "\u{2212}" + text.dropFirst() : text
    }
}

/// La frase del total troceada para que su primer importe ruede dentro de ella: palabras (con su color) y el importe,
/// agrupados en trozos que no se separan al saltar de línea (lo que va pegado sin espacio, como «(» o un punto).
/// Los espacios se quedan al final de la palabra anterior, así que entre trozos no hace falta separación.
private struct RollingSentence {
    struct Piece: Identifiable {
        enum Kind {
            case text(AttributedString)
            case amount(Int)
        }

        let id: Int
        let kind: Kind
    }

    struct Item: Identifiable {
        let id: Int
        let pieces: [Piece]
    }

    let items: [Item]

    /// nil si la frase no lleva ningún importe.
    init?(parts: [BriefingPart], baseColor: Color) {
        var found: (index: Int, cents: Int)?
        for (index, part) in parts.enumerated() {
            if case .amount(let cents) = part {
                found = (index, cents)
                break
            }
        }
        guard let found else { return nil }
        let before = BriefingLineView.attributed(
            parts: Array(parts[..<found.index]), overrideFirstAmount: nil, baseColor: baseColor)
        let after = BriefingLineView.attributed(
            parts: Array(parts[(found.index + 1)...]), overrideFirstAmount: nil, baseColor: baseColor)

        var items: [Item] = []
        var current: [Piece] = []
        var run = AttributedString()
        var lastWasSpace = false
        var nextID = 0

        func flushRun() {
            guard !run.characters.isEmpty else { return }
            current.append(Piece(id: nextID, kind: .text(run)))
            nextID += 1
            run = AttributedString()
        }
        // Aquí la línea puede saltar: se cierra el trozo.
        func cut() {
            flushRun()
            guard !current.isEmpty else { return }
            items.append(Item(id: nextID, pieces: current))
            nextID += 1
            current = []
        }
        func add(_ text: AttributedString) {
            var index = text.startIndex
            while index < text.endIndex {
                let next = text.characters.index(after: index)
                let isSpace = text.characters[index] == " "
                if !isSpace && lastWasSpace { cut() }
                run.append(text[index..<next])
                lastWasSpace = isSpace
                index = next
            }
        }

        add(before)
        if lastWasSpace { cut() } else { flushRun() }
        current.append(Piece(id: nextID, kind: .amount(found.cents)))
        nextID += 1
        lastWasSpace = false
        add(after)
        cut()
        self.items = items
    }
}

/// Coloca los trozos de una frase como lo haría un texto: uno tras otro, saltando de línea cuando el siguiente no
/// cabe, todos sobre la misma línea de base. Un trozo más ancho que la línea recibe el ancho de la línea (el texto se
/// parte dentro; el importe se encoge).
private struct SentenceFlow: Layout {
    private struct Row {
        var range: Range<Int>
        var width: CGFloat
        var ascent: CGFloat
        var descent: CGFloat
    }

    private func proposal(for subview: LayoutSubview, width: CGFloat) -> ProposedViewSize {
        let natural = subview.sizeThatFits(.unspecified)
        return natural.width > width ? ProposedViewSize(width: width, height: nil) : .unspecified
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row(range: 0..<0, width: 0, ascent: 0, descent: 0)
        for index in subviews.indices {
            let dimensions = subviews[index].dimensions(in: proposal(for: subviews[index], width: width))
            if row.range.count > 0, row.width + dimensions.width > width {
                rows.append(row)
                row = Row(range: index..<index, width: 0, ascent: 0, descent: 0)
            }
            let baseline = dimensions[.firstTextBaseline]
            row.range = row.range.lowerBound..<(index + 1)
            row.width += dimensions.width
            row.ascent = max(row.ascent, baseline)
            row.descent = max(row.descent, dimensions.height - baseline)
        }
        if row.range.count > 0 { rows.append(row) }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let lines = rows(width: width, subviews: subviews)
        return CGSize(
            width: min(width, lines.map(\.width).max() ?? 0),
            height: lines.reduce(0) { $0 + $1.ascent + $1.descent })
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.range {
                let size = self.proposal(for: subviews[index], width: bounds.width)
                let dimensions = subviews[index].dimensions(in: size)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + row.ascent - dimensions[.firstTextBaseline]),
                    anchor: .topLeading, proposal: size)
                x += dimensions.width
            }
            y += row.ascent + row.descent
        }
    }
}
