import SwiftUI
import MiBancoCore

/// Sección «Lo que he visto» dentro de la hoja de Nyx (diseño §6.7 y §6.13).
/// Agrupa las entradas en «Nuevo» y «Antes»; sin entradas, enseña su frase fija.
struct NyxSeenList: View {
    let entries: [NyxEntry]
    let initialNewIDs: Set<String>
    let state: LedgerState
    let hidden: Bool
    let undoStates: [String: NyxUndoState]
    var highlightedEntryID: String? = nil
    let now: Date
    let onAction: (NyxAction, NyxEntry) -> Void
    let onDismiss: (NyxEntry) -> Void
    let onUndo: (String) -> Void

    @Environment(\.motion) private var motion

    private var visibleEntries: [NyxEntry] {
        entries.filter { $0.status != .dismissed || undoStates[$0.id] != nil }
    }

    private var newEntries: [NyxEntry] {
        visibleEntries.filter { initialNewIDs.contains($0.id) }
    }

    private var earlierEntries: [NyxEntry] {
        visibleEntries.filter { !initialNewIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lo que he visto")
                .titan(.header)
                .foregroundStyle(Theme.label3)
                .padding(.horizontal, 6)
                .accessibilityAddTraits(.isHeader)

            if visibleEntries.isEmpty {
                Text("Aún no he visto nada. Lo que vea aparecerá aquí.")
                    .titan(.callout)
                    .foregroundStyle(Theme.label2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
                    .accessibilityIdentifier("nyx-seen-empty")
            } else {
                if !newEntries.isEmpty {
                    group(title: "Nuevo", items: newEntries, offset: 0)
                }
                if !earlierEntries.isEmpty {
                    group(title: "Antes", items: earlierEntries, offset: newEntries.count)
                }
            }
        }
        .animation(motion.reduce ? motion.fade : motion.animation(.row), value: visibleEntries.map(\.id))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nyx-seen-list")
    }

    private func group(title: String, items: [NyxEntry], offset: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .titan(.captionStrong)
                .foregroundStyle(Theme.label2)
                .padding(.horizontal, 6)
                .accessibilityAddTraits(.isHeader)

            ForEach(Array(items.enumerated()), id: \.element.id) { index, entry in
                let message = nyxMessage(for: entry.observation, now: now, calendar: DateText.madridCalendar)
                let available = nyxAvailableActions(message, state: state)
                let titles = NyxActionHandler.titles(for: available, in: message, hidden: hidden)

                NyxMessageRow(
                    entryID: entry.id,
                    message: message,
                    delivery: entry.delivery,
                    hidden: hidden,
                    actions: available,
                    actionTitles: titles,
                    undoState: undoStates[entry.id],
                    showDismiss: true,
                    isHighlighted: highlightedEntryID == entry.id,
                    onAction: { action in onAction(action, entry) },
                    onDismiss: { onDismiss(entry) },
                    onUndo: { onUndo(entry.id) }
                )
                .id("nyx-row-\(entry.id)")
                .staggeredEntrance(min(offset + index, 8), rise: 10)
            }
        }
    }
}
