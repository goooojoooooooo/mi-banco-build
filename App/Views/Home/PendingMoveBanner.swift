import SwiftUI
import MiBancoCore

/// Aviso en la parte superior de la lista de Inicio para traspasos preparados pendientes o recién confirmados.
struct PendingMoveBanner: View {
    let moves: [PendingMove]
    let states: [UUID: MoveState]
    let accountBook: AccountBookModel
    let onDismiss: (UUID) -> Void

    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        if !moves.isEmpty {
            VStack(spacing: 8) {
                ForEach(moves) { move in
                    row(for: move, state: states[move.id] ?? .waiting)
                }
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.top, 12)
        }
    }

    private func row(for move: PendingMove, state: MoveState) -> some View {
        let targetName = accountBook.displayName(for: move.target)
        let isDone: Bool = if case .done = state { true } else { false }
        let hidden = preferences.privateMode
        let spokenPrefix = isDone ? "Hecho" : "Esperando"
        let spoken = "\(spokenPrefix): \(spokenAmount(move.amountCents, hidden: hidden)) de \(move.from.displayName) a \(targetName)"

        return HStack(spacing: 12) {
            if isDone {
                DrawnCheck(lineWidth: 2.2, color: Theme.income)
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "clock")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.label2)
                    .accessibilityHidden(true)
            }

            HStack(spacing: 0) {
                Text(isDone ? "Hecho: " : "Esperando: ")
                    .foregroundStyle(isDone ? Theme.income : Theme.label2)
                Text(formatEUR(move.amountCents))
                    .foregroundStyle(Theme.label)
                    .privateAmount()
                Text(" de \(move.from.displayName) a \(targetName)")
                    .foregroundStyle(Theme.label2)
            }
            .titan(.subtitle)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)

            if !isDone {
                Button {
                    onDismiss(move.id)
                } label: {
                    Text("Quitar")
                        .titan(.meta)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.label2)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.grouped, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
