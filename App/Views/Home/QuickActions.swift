import SwiftUI
import MiBancoCore

/// Acciones rápidas bajo el control segmentado de Inicio (Plan 4b, tarea 8): cápsulas visuales de 36 pt en
/// `Theme.raised` con zona táctil mínima de 44 pt. Solo aparecen en «Todo» y en las tarjetas de bancos.
struct QuickActions: View {
    let card: AccountCard
    let model: LedgerModel
    let accountBook: AccountBookModel
    let onMove: (MoveRequest) -> Void
    let onCopyIBAN: (String) -> Void
    let onShareIBAN: (String) -> Void
    let onOpenAccounts: () -> Void

    @State private var copyTick = 0

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if card == .all {
                    chip("Mover dinero", systemImage: "arrow.left.arrow.right") {
                        onMove(MoveRequest())
                    }
                } else if let bank = card.bank {
                    chip("Mover dinero", systemImage: "arrow.left.arrow.right") {
                        onMove(MoveRequest(from: bank))
                    }
                    if bank == .rev {
                        chip("Añadir dinero", systemImage: "plus") {
                            // Sin fijar origen para que `whereToPay` elija dinámicamente el banco que mejor encaja según el importe.
                            onMove(MoveRequest(from: nil, target: .own(.rev)))
                        }
                    }
                    if let iban = accountBook.book.ibans[bank] {
                        chip("Copiar IBAN", systemImage: "doc.on.doc") {
                            Pasteboard.copy(normalizeIBAN(iban))
                            copyTick += 1
                            onCopyIBAN("IBAN copiado · se borra en 3 min")
                        }
                        chip("Compartir IBAN", systemImage: "square.and.arrow.up") {
                            onShareIBAN("Mi IBAN de \(bank.displayName): \(formatIBAN(iban))")
                        }
                    } else {
                        chip("Añadir IBAN", systemImage: "creditcard") {
                            onOpenAccounts()
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Space.gutter)
        }
        .scrollIndicators(.hidden)
        .padding(.top, 8)
        .sensoryFeedback(Haptics.success, trigger: copyTick)
    }

    private func chip(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityHidden(true)
                Text(title)
                    .titan(.subtitle)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.label)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 36)
            .background(Theme.raised, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
    }
}
