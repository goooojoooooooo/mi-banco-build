import SwiftUI
import MiBancoCore

/// «Traspasos entre tus cuentas»: los pagos y los ingresos que la app ha emparejado como dinero que solo cambia de
/// banco. No cuentan como gasto ni como ingreso. Tocar uno abre su detalle.
struct TransfersView: View {
    let model: LedgerModel
    let openDetail: (UUID) -> Void

    @Namespace private var zoom

    var body: some View {
        let snapshot = model.snapshot
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("Dinero que solo cambia de un banco tuyo a otro. No cuenta como gasto ni como ingreso.")
                    .titan(.callout)
                    .foregroundStyle(Theme.label2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Space.gutter)
                    .staggeredEntrance(0, rise: 8)
                    .accessibilityIdentifier("traspasos.explicacion")
                ForEach(snapshot.transferEntries) { entry in
                    ListEntryView(entry: entry, logoDomain: domain(entry, snapshot), isFresh: false, zoom: zoom,
                                  onOpen: openDetail, onDeleteUnread: { _ in })
                        .staggeredEntrance(1 + entry.order)
                }
            }
            .padding(.bottom, Theme.Space.section)
        }
        .scrollIndicators(.hidden)
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Traspasos")
        .navigationBarTitleDisplayMode(.large)
        .assemblesOnFirstAppear()
    }

    private func domain(_ entry: ListEntry, _ snapshot: LedgerSnapshot) -> String? {
        if case let .row(row, _) = entry.kind { return snapshot.logoDomains[row.id] }
        return nil
    }
}
