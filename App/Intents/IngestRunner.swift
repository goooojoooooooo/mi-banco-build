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
        /// El libro ya guardado: reglas de avisos, silenciados y lo que calculan los avisos extra.
        var state: LedgerState
    }

    /// Si el almacén falla, lanza el error para que Atajos lo muestre.
    static func run(_ input: IngestInput) async throws {
        let bank: BankID?
        switch input {
        case .notification(let b, _, _, _), .wallet(let b, _, _): bank = b
        case .unattributedNotice: bank = nil
        }
        let snap = try SharedStore.make().update { ledger -> Snapshot in
            let before = bank.flatMap { ledger.balance($0) }
            let now = Date()
            let outcome = ledger.ingest(input, now: now)
            let after = bank.flatMap { ledger.balance($0) }
            var balances: [String: Int] = [:]
            for b in BankID.allCases { if let c = ledger.balance(b)?.cents { balances[b.rawValue] = c } }
            return Snapshot(outcome: outcome, before: before?.cents, beforeEstimated: before?.estimated ?? false,
                            after: after?.cents, afterEstimated: after?.estimated ?? false,
                            total: ledger.total(now: now), balances: balances, state: ledger.state)
        }
        // Si la app está abierta, Home se recarga con esto.
        NotificationCenter.default.post(name: .ledgerDidChange, object: nil)
        switch snap.outcome {
        case .stored(let m), .merged(let m):
            // Un registro del banco que se fusiona con su aviso no avisó antes: se trata como uno nuevo.
            let now = Date()
            let calendar = Calendar.current
            let ledger = Ledger(state: snap.state)
            // Traspasos y capturados sin confirmar: no son gasto de hoy ni del comercio (calculado una vez).
            let transfers = spendingExclusions(in: snap.state, now: now)
            // "Cada movimiento" apagado o comercio silenciado: el movimiento queda guardado (e Inicio se actualiza),
            // pero ni aviso básico ni Live Activity.
            if snap.state.alertSettings.everyMovement && !ledger.isMuted(merchant: m.merchant) {
                let month = m.merchant.map { merchantHistory(for: $0, in: snap.state.movements, now: now, calendar: calendar, notSpending: transfers) }
                await AlertPoster.post(movement: m, balance: snap.after, estimated: snap.afterEstimated,
                                       balances: snap.balances, previousBalance: snap.before,
                                       merchantMonth: m.kind == .payment ? month : nil,
                                       todaySpentCents: spentToday(in: snap.state.movements, now: now, calendar: calendar, notSpending: transfers))
                _ = await LiveActivityController.show(movement: m, balance: snap.after, estimated: snap.afterEstimated,
                                                      total: snap.total)
            }
            // Avisos extra (saldo bajo, pago grande, duplicado...), uno por idea y nunca repetidos.
            await InsightNotifier.post(immediateAlerts(afterStoring: m, in: snap.state, now: now, calendar: calendar, notSpending: transfers))
            await AlertScheduler.reschedule(for: snap.state, now: now, calendar: calendar)
        case .unread:
            await AlertPoster.postUnread(bank: bank)
        case .duplicate:
            // Un duplicado puede traer el saldo del banco: se corrige la Live Activity sin avisar ni sonar.
            if let bank, snap.after != snap.before || snap.afterEstimated != snap.beforeEstimated {
                await LiveActivityController.updateBalance(bank: bank, balance: snap.after, estimated: snap.afterEstimated, total: snap.total)
            }
        case .ignored:
            break
        }
    }
}
