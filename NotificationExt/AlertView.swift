import SwiftUI
import MiBancoCore

/// Aviso ampliado en Titanio: negro puro y, de escenario, la tarjeta de titanio del banco. Dentro: el logo de la tienda,
/// el comercio y el importe, y lo más grande, "Te quedan". Debajo, este mes en ese comercio y lo gastado hoy.
/// Se monta como en Inicio: la tarjeta aparece, el logo se posa, el importe cuenta desde 0, "Te quedan" rueda del saldo
/// anterior al nuevo y las líneas de abajo entran escalonadas. Con Reducir movimiento, todo es un fundido.
struct AlertView: View {
    let model: AlertModel
    /// true solo para medir la altura que pide el contenido (sin estirarse a la vista).
    var measuring = false
    /// Revisión del aviso ya montada. Se deriva (no se reinicia): un aviso nuevo nunca enseña un fotograma
    /// del estado final antes de empezar.
    @State private var landedRevision = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var landed: Bool { measuring || landedRevision == model.revision }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            stage
                .opacity(landed ? 1 : 0)
                .scaleEffect(landed || reduceMotion ? 1 : 0.96)
                .animation(step(0, spring: true), value: landed)
            details
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: measuring ? nil : .infinity, alignment: .topLeading)
        .background(Theme.canvas)
        .task(id: model.revision) {
            guard !measuring else { return }
            // Un fotograma en el estado inicial y, después, el montaje.
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 60))
            landedRevision = model.revision
        }
    }

    // MARK: Tarjeta

    private var stage: some View {
        let material = model.bank?.material ?? .all
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                logo
                    .scaleEffect(landed || reduceMotion ? 1 : 0.5)
                    .offset(y: landed || reduceMotion ? 0 : -10)
                    .opacity(landed ? 1 : 0)
                    // N1: el logo se posa con el muelle `snap` del kit, a Expresivo fijo (la extensión no tiene ajustes).
                    .animation(landed ? (reduceMotion ? .easeOut(duration: 0.25) : Theme.Motion.expressive(Theme.Motion.snapSpec).delay(0.08)) : nil,
                               value: landed)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(Theme.font(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(model.bank?.displayName ?? "")
                        .font(Theme.font(size: 13))
                        .foregroundStyle(Theme.card2)
                        .lineLimit(1)
                }
                .modifier(Rise(landed: landed, reduceMotion: reduceMotion, animation: step(0.12)))
                Spacer(minLength: 8)
                RollingFigure(value: landed ? Double(model.amountCents) : 0, style: .signed)
                    .font(Theme.font(size: 20, weight: .semibold))
                    .foregroundStyle(model.isIncome ? Theme.income : Theme.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .animation(number(Theme.Motion.countUp, delay: 0.15), value: landed)
                    .accessibilityLabel(model.title)
            }

            Spacer(minLength: 18)

            if let after = model.balanceAfter {
                Text(model.estimated ? "Te quedan unos" : "Te quedan")
                    .font(Theme.font(size: 13, weight: .medium))
                    .foregroundStyle(Theme.card2)
                    .modifier(Rise(landed: landed, reduceMotion: reduceMotion, animation: step(0.22)))
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    RollingFigure(value: Double(landed ? after : (model.balanceBefore ?? after)), style: .hero)
                        .foregroundStyle(Theme.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .animation(number(Theme.Motion.roll, delay: 0.35), value: landed)
                    if model.estimated {
                        Text("estimado")
                            .font(Theme.font(size: 12))
                            .foregroundStyle(Theme.card2)
                            .fixedSize()
                    }
                }
                .padding(.top, 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(model.body)
                Text("en \(model.bank?.displayName ?? "")")
                    .font(Theme.font(size: 13))
                    .foregroundStyle(Theme.card2)
                    .modifier(Rise(landed: landed, reduceMotion: reduceMotion, animation: step(0.3)))
            } else {
                Text(model.body)
                    .font(Theme.font(size: 15, weight: .medium))
                    .foregroundStyle(Theme.card2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: typeSize.isAccessibilitySize ? nil : 180, alignment: .topLeading)
        .background(material.gradient, in: shape)
        .overlay {
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.03), .white.opacity(0.14)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1)
        }
    }

    @ViewBuilder
    private var logo: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.logo, style: .continuous)
        if let domain = model.logoDomain, let image = BundledLogos.image(domain: domain) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: 40, height: 40)
                .background(Color.white)
                .clipShape(shape)
                .overlay(shape.strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
                .accessibilityHidden(true)
        } else {
            Image(systemName: model.isIncome ? "arrow.down.left" : "creditcard")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.monogram)
                .frame(width: 40, height: 40)
                .background(Theme.raised, in: shape)
                .accessibilityHidden(true)
        }
    }

    private var headline: String { model.merchant ?? (model.isIncome ? "Ingreso" : "Pago") }

    // MARK: Debajo de la tarjeta

    @ViewBuilder
    private var details: some View {
        let lines = detailLines
        if !lines.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .firstTextBaseline) {
                        Text(line.label)
                            .font(Theme.font(.footnote))
                            .foregroundStyle(Theme.label2)
                        Spacer(minLength: 8)
                        Text(line.value)
                            .font(Theme.font(.footnote, weight: .semibold))
                            .foregroundStyle(Theme.label)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Theme.separator).frame(height: 0.5).opacity(index == lines.count - 1 ? 0 : 1)
                    }
                    .accessibilityElement(children: .combine)
                    // N1: las filas entran 55 ms × 0,8ⁿ (como el kit, a Expresivo).
                    .modifier(Rise(landed: landed, reduceMotion: reduceMotion,
                                   animation: step(0.45 + Theme.Motion.expressiveStagger(index))))
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var detailLines: [(label: String, value: String)] {
        var out: [(label: String, value: String)] = []
        if let count = model.monthCount, let cents = model.monthCents, let merchant = model.merchant {
            let times = count == 1 ? "1 compra" : "\(count) compras"
            out.append(("Este mes en \(merchant)", "\(times) · \(formatEUR(cents))"))
        }
        if let today = model.todaySpent, today > 0 {
            out.append(("Hoy has gastado", formatEUR(today)))
        }
        return out
    }

    // MARK: Tiempos

    /// Pieza del montaje: muelle (rebote solo en objetos, nunca en texto) con su retraso. Al volver al estado
    /// inicial (aviso nuevo) no se anima. Con Reducir movimiento, un fundido corto.
    private func step(_ delay: Double, spring: Bool = false, bounce: Double = 0.15) -> Animation? {
        guard landed else { return nil }
        if reduceMotion { return .easeOut(duration: 0.25) }
        return (spring ? Animation.spring(duration: 0.5, bounce: bounce) : Animation.spring(duration: 0.45, bounce: 0))
            .delay(delay)
    }

    /// Cifras: cuentan o ruedan con su curva; con Reducir movimiento, sin rodar (el fundido de la tarjeta basta).
    private func number(_ curve: Animation, delay: Double) -> Animation? {
        guard landed, !reduceMotion else { return nil }
        return curve.delay(delay)
    }
}

/// Sube 10 pt y aparece. Con Reducir movimiento, solo aparece.
private struct Rise: ViewModifier {
    let landed: Bool
    let reduceMotion: Bool
    let animation: Animation?

    func body(content: Content) -> some View {
        content
            .opacity(landed ? 1 : 0)
            .offset(y: landed || reduceMotion ? 0 : 10)
            .animation(animation, value: landed)
    }
}

/// Un importe animado (`Animatable`): SwiftUI interpola `value` y vuelve a dibujar la cifra en cada fotograma.
/// Cifras tabulares, así que nada tiembla.
private struct RollingFigure: View, Animatable {
    enum Style { case signed, hero }
    var value: Double
    let style: Style

    nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        let cents = Int(value.rounded())
        switch style {
        case .signed:
            Text((cents < 0 ? "−" : "+") + formatEUR(abs(cents)))
        case .hero:
            let s = formatEUR(abs(cents))
            let sign = cents < 0 ? "−" : ""
            if let i = s.lastIndex(of: ",") {
                Text("\(Text(sign + String(s[..<i])).font(.system(size: 40, weight: .semibold)))\(Text(String(s[i...])).font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.card2))")
                    .monospacedDigit()
                    .tracking(-1.2)
            } else {
                Text(sign + s)
                    .font(.system(size: 40, weight: .semibold))
                    .monospacedDigit()
            }
        }
    }
}
