import Foundation
import MiBancoCore
import Observation
import UIKit

extension Notification.Name {
    /// Un banco actualizó el libro. Distinta de `ledgerDidChange` (avisos e intents): esa puede traer una "llegada"
    /// animada en Inicio; esta nunca.
    static let ledgerDidSyncFromBank = Notification.Name("com.mibanco.ledgerDidSyncFromBank")
}

enum SyncOutcome: Equatable, Sendable {
    case skipped(SkipReason)
    case updated(added: Int)
    case failed(SyncProblem)
}

/// Estado para la pantalla de bancos (más adelante). Este código no presenta nada.
@MainActor @Observable
final class BankSyncStatus {
    static let shared = BankSyncStatus()
    private(set) var running: Set<BankID> = []
    private(set) var lastOutcome: [BankID: SyncOutcome] = [:]

    fileprivate func begin(_ bank: BankID) { running.insert(bank) }
    fileprivate func end(_ bank: BankID, _ outcome: SyncOutcome?) {
        running.remove(bank)
        if let outcome { lastOutcome[bank] = outcome }
    }
}

/// Consulta los bancos conectados (movimientos y saldo) y lo concilia en el libro. Solo lectura.
/// Una sola consulta a la vez en toda la app (al abrir, en segundo plano, a mano o tras conectar): una segunda llamada
/// mientras hay una en marcha no arranca otra; si era "tras conectar", queda apuntada y se hace al terminar la actual.
/// Las decisiones (qué bancos, cuándo, el problema de un fallo) son de Core; aquí solo se ejecutan.
/// Nunca publica avisos: no usa ningún tipo que publique notificaciones.
actor BankSync {
    static let shared = BankSync()

    private var running = false
    private var queuedAfterConnect: Set<BankID> = []

    nonisolated static var isEnabled: Bool {
        #if DEBUG
        if DemoMode.isActive { return false }
        #endif
        return BankingCredentials.isReady
    }

    /// Al abrir la app: solo si está de verdad en primer plano EN ESTE MOMENTO (se lee el estado vivo, no el de cuando
    /// se pidió).
    @MainActor
    static func refreshOnOpen() {
        guard UIApplication.shared.applicationState == .active else { return }
        Task { _ = await BankSync.shared.refresh(trigger: .appOpen) }
    }

    /// Un banco se conectó, renovó o desconectó: se rehacen los avisos de caducidad y, si sigue conectado, se consulta.
    func linkDidChange(_ bank: BankID?) async {
        await rescheduleReminders()
        guard let bank else { return }
        _ = await refresh(trigger: .afterConnect, only: bank)
    }

    func refresh(trigger: SyncTrigger, only bank: BankID? = nil) async -> [BankID: SyncOutcome] {
        guard Self.isEnabled else { return [:] }
        let banks = bank.map { [$0] } ?? BankID.allCases
        if running {
            if trigger == .afterConnect { queuedAfterConnect.formUnion(banks) }
            return Dictionary(uniqueKeysWithValues: banks.map { ($0, SyncOutcome.skipped(.fresh)) })
        }
        running = true
        defer { running = false }

        var results = await runBanks(banks, trigger: trigger)
        // Lo que pidieron "tras conectar" mientras tanto, ya sin nadie más en marcha.
        while !queuedAfterConnect.isEmpty, !Task.isCancelled {
            let next = queuedAfterConnect.sorted { $0.rawValue < $1.rawValue }
            queuedAfterConnect = []
            results.merge(await runBanks(next, trigger: .afterConnect)) { _, new in new }
        }
        queuedAfterConnect = []
        await rescheduleReminders()
        return results
    }

    // MARK: - Interno

    private func runBanks(_ banks: [BankID], trigger: SyncTrigger) async -> [BankID: SyncOutcome] {
        let store = SharedStore.make()
        var results: [BankID: SyncOutcome] = [:]
        var links = (try? store.load().links) ?? [:]
        let calendar = bankingCalendar
        let plans = banksToFetch(
            links: links.filter { banks.contains($0.key) }, trigger: trigger, now: Date(), calendar: calendar)
        let planned = Dictionary(uniqueKeysWithValues: plans.map { ($0.bank, $0) })

        for bank in banks {
            if Task.isCancelled { break }
            // Un banco que falla nunca frena a los demás: cada uno devuelve su propio resultado.
            guard planned[bank] != nil else {
                if case let .skip(reason) = SyncPolicy.decide(links[bank], trigger: trigger, now: Date(), calendar: calendar) {
                    results[bank] = .skipped(reason)
                }
                continue
            }
            // El libro puede haber cambiado mientras iban los bancos anteriores: se decide otra vez con lo vivo.
            links = (try? store.load().links) ?? links
            let decision = SyncPolicy.decide(links[bank], trigger: trigger, now: Date(), calendar: calendar)
            guard case let .fetch(dateFrom, strategy) = decision else {
                if case let .skip(reason) = decision { results[bank] = .skipped(reason) }
                continue
            }
            await BankSyncStatus.shared.begin(bank)
            let outcome = await sync(bank, dateFrom: dateFrom, strategy: strategy, store: store, calendar: calendar)
            await BankSyncStatus.shared.end(bank, outcome)
            if let outcome { results[bank] = outcome }
        }
        return results
    }

    /// `nil` = cancelada: ni éxito ni fallo, no se anota nada más y el banco no aparece en el resultado.
    private func sync(
        _ bank: BankID, dateFrom: Date, strategy: TransactionStrategy, store: FileStore, calendar: Calendar
    ) async -> SyncOutcome? {
        // 1. El intento queda anotado antes de llamar (cuenta para el límite diario aunque la app muera a mitad).
        let attemptAt = Date()
        let connected = (try? store.update { ledger -> Bool in
            guard let link = ledger.state.links[bank] else { return false }
            ledger.setLink(bank, link.recordingAttempt(at: attemptAt))
            return true
        }) ?? false
        guard connected else { return .skipped(.notConnected) }

        do {
            guard let session = try KeychainVault.codable(StoredSession.self, for: KeychainVault.session(for: bank)) else {
                // Hay conexión en el libro pero no sesión en el Llavero (otro dispositivo, copia restaurada): hay que renovar.
                throw BankingClientError.api(.consentExpired, code: nil)
            }
            let client = try BankingCredentials.client()
            let from = bankDateParameter(dateFrom, calendar: calendar)

            // 2 y 3. Saldos y movimientos de cada cuenta. Todo se reúne antes de tocar el libro.
            var balances: [[EBBalance]] = []
            var transactions: [EBTransaction] = []
            var complete = true
            for uid in session.accountUIDs {
                balances.append(try await client.balances(accountUID: uid))
                let fetch = try await client.fetchTransactions(accountUID: uid, dateFrom: from, strategy: strategy)
                transactions += fetch.transactions
                complete = complete && fetch.complete
            }
            try Task.checkCancellation()

            // Un solo instante para la consulta: hora de importación de las filas y de la lectura del saldo.
            let fetchedAt = Date()
            let records = bankRecords(from: transactions, bank: bank, calendar: calendar)
            let reading = combineBalanceReadings(balances.map { chooseBalanceReading($0, fetchedAt: fetchedAt) })

            // 5. Una sola escritura (sin puntos de suspensión dentro): movimientos, saldo y éxito juntos.
            let applied = try store.update { ledger in
                ledger.applyBankFetch(
                    bank: bank, records: records, balance: reading, dateFrom: dateFrom, complete: complete,
                    fetchedAt: fetchedAt, calendar: calendar)
            }
            guard let applied else { return .skipped(.notConnected) }
            // 6. Aviso al modelo del libro: recarga sin llegada animada, sin sonido ni vibración.
            NotificationCenter.default.post(name: .ledgerDidSyncFromBank, object: nil)
            return .updated(added: applied.report.added)
        } catch {
            // Una cancelación (caducó la tarea de fondo, la app se va) no es un fallo del banco: no se anota.
            if error is CancellationError || Task.isCancelled { return nil }
            let problem = syncProblem(for: error)
            _ = try? store.update { ledger in
                guard let link = ledger.state.links[bank] else { return }
                ledger.setLink(bank, link.applying(.failure(error), at: Date()))
            }
            if problem == .consentExpired {
                try? KeychainVault.delete(KeychainVault.session(for: bank))
            }
            NotificationCenter.default.post(name: .ledgerDidSyncFromBank, object: nil)
            return .failed(problem)
        }
    }

    private func rescheduleReminders() async {
        let links = (try? SharedStore.make().load().links) ?? [:]
        await BankReminders.reschedule(links: links)
    }
}
