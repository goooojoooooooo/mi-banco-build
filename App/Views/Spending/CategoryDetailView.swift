import SwiftUI
import MiBancoCore

/// Los movimientos de una categoría en un mes: ficha y nombre, el total (cuenta), la comparación con el mes anterior,
/// la barra del presupuesto si lo hay (solo en el mes en curso) y debajo los pagos agrupados por día con las filas de Inicio.
/// Tocar una fila abre el detalle de siempre (la hoja de `RootView`). Todo sale del snapshot.
struct CategoryDetailView: View {
    let model: LedgerModel
    let category: SpendingCategory
    let month: Date
    let openDetail: (UUID) -> Void

    @Namespace private var zoom
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        let snapshot = model.snapshot
        let key = LedgerSnapshot.categoryKey(month: month, category: category)
        let header = snapshot.categoryHeaders[key]
        let entries = snapshot.categoryEntries[key] ?? []
        let isCurrent = snapshot.spendingMonths.last == month
        let budget = isCurrent ? snapshot.budgets.first { $0.scope == .category(category) } : nil
        let title = snapshot.spendingPages[month]?.title ?? ""
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 14) {
                        Image(systemName: category.symbolName)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(Theme.label)
                            .frame(width: 40, height: 40)
                            .background(Theme.raised, in: .rect(cornerRadius: Theme.Radius.logoLarge, style: .continuous))
                            .accessibilityHidden(true)
                        Text(category.displayName)
                            .titan(.cardTitle)
                            .foregroundStyle(Theme.label)
                            .accessibilityAddTraits(.isHeader)
                    }
                    .staggeredEntrance(0, rise: 8)

                    HeroBalance(cents: header?.cents ?? 0, centsColor: Theme.label2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 10)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Gastado en \(category.displayName), \(title.lowercased()): \(spokenAmount(header?.cents ?? 0, hidden: preferences.privateMode))")
                        .accessibilityIdentifier("categoria.total")
                        .staggeredEntrance(1)

                    if let comparison = header?.comparison {
                        Text(comparison)
                            .titan(.callout)
                            .foregroundStyle(Theme.label2)
                            .privateAmount(radius: 6)
                            .padding(.top, 4)
                            .accessibilityIdentifier("categoria.comparacion")
                            .staggeredEntrance(2)
                    }

                    if let budget {
                        BudgetBar(status: budget, name: "Presupuesto de \(category.displayName)", index: 0)
                            .padding(.top, 16)
                            .accessibilityIdentifier("categoria.presupuesto")
                            .staggeredEntrance(3)
                    }
                }
                .padding(.horizontal, Theme.Space.gutter)
                .padding(.top, 4)

                if entries.isEmpty {
                    Text("No hay pagos en esta categoría este mes.")
                        .titan(.callout)
                        .foregroundStyle(Theme.label2)
                        .padding(.horizontal, Theme.Space.gutter)
                        .padding(.top, Theme.Space.section)
                } else {
                    ForEach(entries) { entry in
                        ListEntryView(entry: entry, logoDomain: logoDomain(of: entry, in: snapshot), isFresh: false, zoom: zoom,
                                      onOpen: openDetail, onDeleteUnread: { _ in })
                            .staggeredEntrance(4 + order(of: entry))
                    }
                }
            }
            .padding(.bottom, Theme.Space.section)
        }
        .scrollIndicators(.hidden)
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .assemblesOnFirstAppear()
    }

    private func logoDomain(of entry: ListEntry, in snapshot: LedgerSnapshot) -> String? {
        if case let .row(row, _) = entry.kind { return snapshot.logoDomains[row.id] }
        return nil
    }

    private func order(of entry: ListEntry) -> Int { entry.order }
}
