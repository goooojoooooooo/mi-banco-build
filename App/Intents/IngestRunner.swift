import Foundation
import MiBancoCore

/// Lo que comparten los dos intents: registrar, avisar y mostrar la Live Activity.
enum IngestRunner {
    private struct Snapshot: Sendable {
        var outcome: IngestOutcome
        var before: Int?
        var beforeEstimated: Bool
        var after: Int?
        var afterEstimated: Bool
        var total: Int?
        var balances: [String: Int]
    }

    /// Si el almacén falla, lanza el error para que Atajos lo muestre.
    static func run(_ input: IngestInput) async throws {
        let bank: BankID
        switch input {
        case .notification(let b, _, _, _), .wallet(let b, _, _): bank = b
        }
        let snap = try SharedStore.make().update { ledger -> Snapshot in
            let before = ledger.balance(bank)
            let outcome = ledger.ingest(input, now: Date())
            let after = ledger.balance(bank)
            var balances: [String: Int] = [:]
            for b in BankID.allCases { if let c = ledger.balance(b)?.cents { balances[b.rawValue] = c } }
            return Snapshot(outcome: outcome, before: before?.cents, beforeEstimated: before?.estimated ?? false,
                            after: after?.cents, afterEstimated: after?.estimated ?? false,
                            total: ledger.total(), balances: balances)
        }
        // Si la app está abierta, Home se recarga con esto.
        NotificationCenter.default.post(name: .ledgerDidChange, object: nil)
        switch snap.outcome {
        case .stored(let m):
            await AlertPoster.post(movement: m, balance: snap.after, estimated: snap.afterEstimated,
                                   balances: snap.balances, previousBalance: snap.before)
            _ = await LiveActivityController.show(movement: m, balance: snap.after, estimated: snap.afterEstimated, total: snap.total)
        case .unread:
            await AlertPoster.postUnread(bank: bank)
        case .duplicate:
            // Un duplicado puede traer el saldo del banco: se corrige la Live Activity sin avisar ni sonar.
            if snap.after != snap.before || snap.afterEstimated != snap.beforeEstimated {
                await LiveActivityController.updateBalance(bank: bank, balance: snap.after, estimated: snap.afterEstimated, total: snap.total)
            }
        case .ignored:
            break
        }
    }
}
