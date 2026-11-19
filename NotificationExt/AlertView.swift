import SwiftUI
import MiBancoCore

/// Aviso ampliado. Orden por importancia: qué pasó (con el logo de la tienda si va en la app),
/// lo que te queda en ese banco (lo más grande), el río que pasa del saldo anterior al nuevo y, lo último, el total.
struct AlertView: View {
    let model: AlertModel
    /// true solo para medir la altura que pide el contenido (sin estirarse a la vista).
    var measuring = false
    /// Revisión del aviso que ya muestra el saldo nuevo. Se deriva (no se reinicia): un aviso nuevo
    /// nunca enseña un fotograma del estado final antes de empezar.
    @State private var landedRevision = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var landed: Bool { landedRevision == model.revision }
    private var shown: [BankID: Int] { landed ? model.after : model.before }
    private var total: Int { shown.values.reduce(0, +) }

    var body: some View {
        let large = typeSize.isAccessibilitySize
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: Theme.Space.row) {
                if let domain = model.logoDomain, let logo = BundledLogos.image(domain: domain) {
                    Image(uiImage: logo)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(4)
                        .frame(width: 32, height: 32)
                        .background(Theme.label, in: .rect(cornerRadius: 9))
                        .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.raised, lineWidth: 1) }
                        .accessibilityHidden(true)
                }
                Text(model.title)
                    .font(Theme.font(.callout, weight: .semibold))
                    .foregroundStyle(Theme.label)
                    .lineLimit(large ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(model.body)
                .font(Theme.font(size: 17, weight: .medium, relativeTo: .headline))
                .foregroundStyle(Theme.label)
                .lineLimit(large ? nil : 2)
                .minimumScaleFactor(large ? 1 : 0.85)
                .fixedSize(horizontal: false, vertical: true)

            RiverBar(cents: shown, height: 44)

            if !shown.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Total")
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.label2)
                    Text(formatEUR(total))
                        .font(Theme.font(.footnote, weight: .medium))
                        .foregroundStyle(Theme.label2)
                        .contentTransition(.numericText(value: Double(total)))
                        .lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Total, \(formatEUR(model.after.values.reduce(0, +)))")
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.gutter)
        .frame(maxWidth: .infinity, maxHeight: measuring ? nil : .infinity, alignment: .topLeading)
        .background(Theme.canvas)
        .task(id: model.revision) {
            guard !reduceMotion else {
                landedRevision = model.revision
                return
            }
            try? await Task.sleep(for: Theme.Motion.alertPreRoll)
            withAnimation(Theme.Motion.alertLand) { landedRevision = model.revision }
        }
    }
}
