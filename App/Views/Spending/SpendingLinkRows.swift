import SwiftUI

/// Las filas del final de Gasto que empujan otras pantallas, con el estilo de «Comercios silenciados» de Avisos.
struct SpendingLinkRows: View {
    let links: SpendingLinkTexts


    var body: some View {
        VStack(spacing: Theme.Space.gutter) {
            card {
                link(.budgets, "Presupuestos", links.budgets, "gauge.with.dots.needle.67percent", id: "gasto.presupuestos")
            }
            if let transfers = links.transfers {
                card {
                    link(.transfers, "Traspasos entre tus cuentas", transfers, "arrow.left.arrow.right", id: "gasto.traspasos")
                }
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
            .padding(.horizontal, 16)
    }

    private func link(_ route: SpendingRoute, _ title: String, _ detail: String, _ symbol: String, id: String) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: Theme.Space.row) {
                OptionLabel(title: title, detail: detail, systemImage: symbol)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.passive)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle(background: Theme.raised))
        .accessibilityIdentifier(id)
    }
}
