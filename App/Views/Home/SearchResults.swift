import SwiftUI
import MiBancoCore

/// Resultados de la búsqueda (`searchMovements` de Core: comercio, banco, nota o importe, sin tildes), por días.
/// Se calculan al cambiar el texto, nunca en el `body`.
struct SearchResults: View {
    let index: [Movement]
    let logoDomains: [UUID: String]
    let query: String
    let zoom: Namespace.ID
    let onOpen: (UUID) -> Void

    @State private var entries: [ListEntry] = []
    @State private var searched = ""

    private static let limit = 120

    var body: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(spacing: 0) {
            if trimmed.isEmpty {
                SearchMessage(symbol: "magnifyingglass",
                              title: "Busca en tus movimientos",
                              detail: "Por comercio, banco, nota o importe, como «Mercadona» o «12,50».")
            } else if entries.isEmpty && searched == trimmed {
                SearchMessage(symbol: "text.magnifyingglass",
                              title: "Nada con «\(trimmed)»",
                              detail: "Prueba con otro nombre o con un importe, como 12,50.")
            } else {
                ForEach(entries) { entry in
                    ListEntryView(entry: entry, logoDomain: logoDomain(entry), isFresh: false, zoom: zoom,
                                  onOpen: onOpen, onDeleteUnread: { _ in })
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .top)
        .task(id: trimmed) { run(trimmed) }
        .onChange(of: index) { _, _ in run(trimmed) }
    }

    private func run(_ trimmed: String) {
        guard !trimmed.isEmpty else {
            entries = []
            searched = ""
            return
        }
        let found = searchMovements(index, query: trimmed).prefix(Self.limit).map { LedgerItem.movement($0) }
        let sections = LedgerSnapshot.sections(for: Array(found), showsBank: true, now: Date(), calendar: .current)
        entries = ListEntry.flatten(sections, prefix: "q")
        searched = trimmed
        let count = found.count
        AccessibilityNotification.Announcement(count == 0 ? "Sin resultados" : "\(count) \(count == 1 ? "resultado" : "resultados")").post()
    }

    private func logoDomain(_ entry: ListEntry) -> String? {
        guard case let .row(row, _) = entry.kind else { return nil }
        return logoDomains[row.id]
    }
}

/// Estado vacío o sin resultados de la búsqueda.
private struct SearchMessage: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: Theme.Space.small) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(Theme.passive)
                .padding(.bottom, Theme.Space.tight)
                .accessibilityHidden(true)
            Text(title)
                .titan(.option)
                .foregroundStyle(Theme.label)
            Text(detail)
                .titan(.subtitle)
                .foregroundStyle(Theme.label2)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .padding(.top, 56)
        .accessibilityElement(children: .combine)
    }
}
