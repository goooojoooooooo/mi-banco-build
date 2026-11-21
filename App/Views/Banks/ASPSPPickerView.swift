import MiBancoCore
import SwiftUI

/// Selector con buscador de bancos de Enable Banking cuando el nombre no encaja a la primera (Plan 2, tarea 11).
struct ASPSPPickerView: View {
    let bank: BankID
    let list: [EBASPSP]
    var onSelect: (EBASPSP) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.presentationGate) private var gate
    @State private var query = ""

    private var filtered: [EBASPSP] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return list }
        return list.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        List {
            Section {
                ForEach(Array(filtered.enumerated()), id: \.offset) { _, item in
                    Button {
                        onSelect(item)
                        dismiss()
                    } label: {
                        HStack(spacing: Theme.Space.row) {
                            Text(item.name)
                                .titan(.option)
                                .foregroundStyle(Theme.label)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.passive)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.grouped)
                    .listRowSeparatorTint(Theme.separator)
                }
            } header: {
                SettingsHeader("Elige tu banco en la lista")
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.canvas.ignoresSafeArea())
        .searchable(text: $query, prompt: "Buscar \(bank.displayName)")
        .navigationTitle("Elegir \(bank.displayName)")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { query = "" }
        }
        .onChange(of: gate?.isLocked) { _, locked in
            if locked == true { query = "" }
        }
    }
}
