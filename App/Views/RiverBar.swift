import SwiftUI
import MiBancoCore

/// El elemento de la app: una barra con un tramo por banco, ancho proporcional al saldo.
/// Solo depende de SwiftUI, MiBancoCore y Theme (la usa también la notificación ampliada).
struct RiverBar: View {
    /// Saldo en céntimos por banco; el banco sin saldo no tiene tramo.
    let cents: [BankID: Int]
    var selected: BankID?
    var height: CGFloat = 56
    var onSelect: ((BankID) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let gap: CGFloat = 3
    /// Un tramo nunca baja de esto: un banco con poco (o nada) se sigue viendo como tramo, no como punto.
    private let minWidth: CGFloat = 14
    /// Esquinas entre tramos: más cerradas que las de fuera, para que se lea como un río y no como una barra segmentada.
    private let innerRadius: CGFloat = 6
    private var banks: [BankID] { BankID.allCases.filter { cents[$0] != nil } }
    private var positiveSum: Double { banks.reduce(0) { $0 + Double(max(cents[$1] ?? 0, 0)) } }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: gap) {
                ForEach(Array(banks.enumerated()), id: \.element) { index, bank in
                    stream(bank, shape: shape(at: index))
                        .frame(width: width(of: bank, in: geo.size.width))
                }
            }
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : Theme.Motion.river, value: cents)
        .animation(reduceMotion ? nil : Theme.Motion.quick, value: selected)
        // En Inicio la leyenda ya da lo mismo (y el porcentaje): VoiceOver no encuentra seis botones para tres bancos.
        .accessibilityHidden(onSelect != nil)
        .accessibilityElement(children: .combine)
    }

    private func shape(at index: Int) -> UnevenRoundedRectangle {
        let outer = Theme.Radius.river
        let first = index == 0
        let last = index == banks.count - 1
        return UnevenRoundedRectangle(
            topLeadingRadius: first ? outer : innerRadius,
            bottomLeadingRadius: first ? outer : innerRadius,
            bottomTrailingRadius: last ? outer : innerRadius,
            topTrailingRadius: last ? outer : innerRadius,
            style: .continuous)
    }

    private func share(of bank: BankID) -> Double {
        let sum = positiveSum
        guard sum > 0 else { return 1 / Double(max(banks.count, 1)) }
        return Double(max(cents[bank] ?? 0, 0)) / sum
    }

    /// Cada tramo tiene su mínimo y el resto se reparte en proporción: la suma nunca se sale del ancho.
    private func width(of bank: BankID, in available: CGFloat) -> CGFloat {
        let count = CGFloat(banks.count)
        let free = max(available - gap * max(count - 1, 0) - minWidth * count, 0)
        return minWidth + free * share(of: bank)
    }

    @ViewBuilder
    private func stream(_ bank: BankID, shape: UnevenRoundedRectangle) -> some View {
        let value = cents[bank] ?? 0
        Button { onSelect?(bank) } label: {
            Group {
                if value > 0 {
                    shape
                        .fill(bank.color)
                        // Luz suave arriba: da volumen sin sombras.
                        .overlay {
                            LinearGradient(colors: [.white.opacity(0.30), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.55))
                                .blendMode(.softLight)
                                .clipShape(shape)
                        }
                } else {
                    // A cero o en negativo: tramo fantasma, como en el estado vacío. No parece dinero.
                    shape
                        .fill(bank.color.opacity(0.18))
                        .overlay { shape.stroke(bank.color.opacity(0.7), lineWidth: 1) }
                }
            }
            // Destello del tramo cuyo saldo cambia: ataque rápido, caída lenta.
            .phaseAnimator([0.0, 0.28], trigger: reduceMotion ? 0 : value) { content, glow in
                content.brightness(glow)
            } animation: { glow in
                glow > 0 ? Theme.Motion.pulseAttack : Theme.Motion.pulseRelease
            }
            .opacity(selected == nil || selected == bank ? 1 : 0.28)
            .contentShape(shape)
        }
        .buttonStyle(StreamPressStyle())
        .allowsHitTesting(onSelect != nil)
        .accessibilityLabel("\(bank.displayName), \(formatEUR(value)), \(Int((share(of: bank) * 100).rounded())) % del total")
    }
}

/// Tramo del río: se ilumina un poco al pulsarlo (escalarlo abriría huecos entre tramos).
private struct StreamPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? 0.10 : 0)
            .animation(configuration.isPressed ? Theme.Motion.pressIn : Theme.Motion.pressOut, value: configuration.isPressed)
    }
}
