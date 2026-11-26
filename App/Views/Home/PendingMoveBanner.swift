import SwiftUI
import MiBancoCore

/// Aviso en la parte superior de la lista de Inicio para traspasos preparados pendientes o recién confirmados.
/// Cuando la app ve salir el dinero (estado «hecho»), el reloj deja su sitio a un ✓ que salta de 0,3 a 1 y se traza
/// (el mismo del éxito de «Mover dinero», en pequeño) y la frase cambia con un fundido. El importe, con el ojo
/// cerrado, es «•••»: nunca se monta la cifra.
struct PendingMoveBanner: View {
    let moves: [PendingMove]
    let states: [UUID: MoveState]
    let accountBook: AccountBookModel
    let onDismiss: (UUID) -> Void

    @Environment(AppPreferences.self) private var preferences
    @Environment(\.motion) private var motion

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
        let spoken: String = isDone
            ? "He visto salir \(spokenAmount(move.amountCents, hidden: hidden)) de \(move.from.displayName) para \(targetName)"
            : "Esperando: \(spokenAmount(move.amountCents, hidden: hidden)) de \(move.from.displayName) a \(targetName)"
        let amountText = hidden ? "•••" : formatEUR(move.amountCents)
        let sentence: LocalizedStringKey = isDone
            ? "\(Text("He visto salir ").foregroundStyle(Theme.label2))\(Text(amountText).foregroundStyle(Theme.label))\(Text(" de \(move.from.displayName) para \(targetName)").foregroundStyle(Theme.label2))"
            : "\(Text("Esperando: ").foregroundStyle(Theme.label2))\(Text(amountText).foregroundStyle(Theme.label))\(Text(" de \(move.from.displayName) a \(targetName)").foregroundStyle(Theme.label2))"
        let dismissLabel = hidden
            ? "Quitar el traspaso a \(targetName)"
            : "Quitar el traspaso de \(spokenAmount(move.amountCents, hidden: false)) a \(targetName)"

        return HStack(spacing: 12) {
            if isDone {
                SuccessMark(size: 20)
                    .transition(.opacity)
            } else {
                Image(systemName: "clock")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.label2)
                    .accessibilityHidden(true)
            }

            Text(sentence)
                .titan(.subtitle)
                .contentTransition(.opacity)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .privacySensitive()
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
                .accessibilityLabel(dismissLabel)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.logoLarge, style: .continuous))
        .animation(motion.calmAnimation(.snap), value: isDone)
    }
}
