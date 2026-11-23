import SwiftUI

/// Una fila «título … importe» del kit: dos hijos, primero el título y después el importe (un `RollingAmount`).
/// - Si el título a su ancho ideal, `spacing` y el importe a su tamaño natural caben, el importe va a tamaño completo y
///   pegado a la derecha (la columna de importes queda igual en todas las filas que caben).
/// - Si no caben, el importe encoge SOLO lo que el título necesita, hasta `minimumAmountScale` (la mitad).
/// - De ahí para abajo cede el título (se parte en varias líneas); el importe nunca se sale de la fila.
/// Con un `HStack` y un `Spacer` el reparto lo hacía el `HStack`, que ofrecía al importe media fila primero: con el texto
/// más grande «+1.250,00 €» salía a ~0,70 con 82 pt vacíos (K21). Los dos hijos van centrados en vertical.
struct AmountRowLayout: Layout {
    /// Hueco mínimo entre el título y el importe (con las sangrías de los glifos quedan al menos 8 pt de tinta a tinta).
    var spacing: CGFloat = 12
    /// Lo más que encoge el importe antes de que ceda el título.
    var minimumAmountScale: CGFloat = 0.5

    private struct Split {
        var title: CGSize
        var amount: CGSize
        var height: CGFloat { max(title.height, amount.height) }
    }

    private func split(width: CGFloat?, subviews: Subviews) -> Split? {
        guard subviews.count == 2 else { return nil }
        let title = subviews[0], amount = subviews[1]
        let natural = amount.sizeThatFits(.unspecified)
        let titleIdeal = title.sizeThatFits(.unspecified)
        guard let width, width.isFinite else { return Split(title: titleIdeal, amount: natural) }
        var amountWidth = natural.width
        if titleIdeal.width + spacing + natural.width > width {
            amountWidth = min(natural.width, max(natural.width * minimumAmountScale, width - spacing - titleIdeal.width))
        }
        amountWidth = max(0, min(amountWidth, width))
        let amountSize = amount.sizeThatFits(ProposedViewSize(width: amountWidth, height: nil))
        let titleWidth = max(0, width - spacing - amountSize.width)
        var titleSize = title.sizeThatFits(ProposedViewSize(width: titleWidth, height: nil))
        titleSize.width = min(titleSize.width, titleWidth)
        return Split(title: titleSize, amount: amountSize)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let split = split(width: proposal.width, subviews: subviews) else {
            // Uso equivocado (no son dos hijos): ocupa lo que se le ofrezca y no coloca nada raro.
            return proposal.replacingUnspecifiedDimensions()
        }
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? split.title.width + spacing + split.amount.width
        return CGSize(width: width, height: split.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let split = split(width: bounds.width, subviews: subviews) else {
            for subview in subviews { subview.place(at: bounds.origin, proposal: proposal) }
            return
        }
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
            proposal: ProposedViewSize(width: split.title.width, height: split.title.height))
        subviews[1].place(
            at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing,
            proposal: ProposedViewSize(width: split.amount.width, height: nil))
    }
}
