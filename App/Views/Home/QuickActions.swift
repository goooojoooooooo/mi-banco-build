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
                            onMove(MoveRequest(from: bestSource(excluding: .rev), target: .own(.rev)))
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
            .frame(height: 36)
            .background(Theme.raised, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
    }

    private func bestSource(excluding dest: BankID) -> BankID? {
        let now = Date()
        var balances: [BankID: Int] = [:]
        var estimated = Set<BankID>()
        for bank in BankID.allCases where bank != dest {
            if let info = model.snapshot.balances[bank] {
                balances[bank] = info.cents
                if info.estimated { estimated.insert(bank) }
            }
        }
        let included = Set(BankID.allCases.filter { $0 != dest })
        let upcoming = upcomingCalendar(state: model.state, book: accountBook.book, now: now, calendar: DateText.madridCalendar)
            .prefix(7)
            .flatMap(\.charges)
        return whereToPay(
            amountCents: 10_000,
            balances: balances,
            floors: accountBook.book.floors,
            upcoming: Array(upcoming),
            included: included,
            estimated: estimated
        ).first(where: \.fits)?.bank
    }
}
