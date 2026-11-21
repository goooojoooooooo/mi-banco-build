import Foundation
import Observation
import SwiftUI
import UIKit
import MiBancoCore

extension Notification.Name {
    /// Los intents la publican tras guardar en el almacén; el modelo recarga al recibirla.
    static let ledgerDidChange = Notification.Name("com.mibanco.ledgerDidChange")
    // `ledgerDidSyncFromBank` (consulta a un banco) vive en `App/Banking/BankSync.swift`.
}

/// Un movimiento nuevo que acaba de llegar con la app abierta: dispara la coreografía de Inicio (la tarjeta se desliza,
/// las cifras ruedan, la fila se asienta), la háptica y el aviso de VoiceOver.
/// No cambia al recargar al volver a la app, al borrar ni al cambiar un saldo.
struct Arrival: Equatable, Sendable {
    let id: UUID
    let bank: BankID
    let isIncome: Bool
    let title: String
    let amountCents: Int
}

@MainActor @Observable
final class LedgerModel {
    private(set) var state = LedgerState()
    private(set) var arrival: Arrival?
    /// Se reconstruye solo cuando `state` cambia (ver `publish`).
    private(set) var snapshot = LedgerSnapshot()
    /// Traspasos preparados con «Mover dinero» pendientes o recién confirmados (nunca llevan IBAN).
    private(set) var pendingMoves: [PendingMove] = []
    private(set) var pendingMoveStates: [UUID: MoveState] = [:]
    private let store: FileStore
    @ObservationIgnored private var observer: Task<Void, Never>?
    @ObservationIgnored private var syncObserver: Task<Void, Never>?
    /// Publicación aplazada de una llegada; cualquier publicación posterior la deja sin efecto.
    @ObservationIgnored private var staged: Task<Void, Never>?
    @ObservationIgnored private var doneMoveTimers: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var resolvingMoves = false
    @ObservationIgnored private var generation = 0
    /// Presupuestos escritos que no se entienden («abc»): se quedan (solo en memoria) para enseñarlos con su error al
    /// volver a la pantalla, en vez de perderse sin decir nada.
    @ObservationIgnored var budgetDrafts: [BudgetScope: String] = [:]
    #if DEBUG
    /// Demo: lo que "escribiría el intent en el almacén"; `reload` lo recoge como si lo leyera de disco.
    @ObservationIgnored private var demoIncoming: LedgerState?
    #endif

    init() {
        store = SharedStore.make()
        #if DEBUG
        if DemoMode.isActive {
            state = DemoMode.state()
            snapshot = LedgerSnapshot(state: state)
        }
        #endif
        reload()
        observer = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .ledgerDidChange) {
                guard let model = self else { break }
                model.reloadAfterIngest()
            }
        }
        // Una consulta al banco recarga sin llegada animada, sin sonido ni vibración.
        syncObserver = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .ledgerDidSyncFromBank) {
                guard let model = self else { break }
                model.reloadAfterSync()
            }
        }
    }

    /// Si falla la lectura se conserva lo que ya se mostraba.
    func reload() {
        if let loaded = loadNext(), (loaded != state || !Calendar.current.isDateInToday(snapshot.day)) {
            publish(loaded)
        } else {
            resolvePendingMoves()
        }
    }

    /// Tras una consulta a un banco: el estado nuevo se publica tal cual, sin `arrival`.
    private func reloadAfterSync() {
        reload()
    }

    /// Lo siguiente que hay en el almacén (en la demo, lo que dejó la llegada simulada; si no, nada nuevo).
    private func loadNext() -> LedgerState? {
        #if DEBUG
        if DemoMode.isActive {
            defer { demoIncoming = nil }
            return demoIncoming
        }
        #endif
        return try? store.load()
    }

    private func publish(_ next: LedgerState) {
        generation += 1
        staged?.cancel()
        staged = nil
        state = next
        snapshot = LedgerSnapshot(state: next)
        reschedule(next)
        resolvePendingMoves()
    }

    func addPendingMove(_ move: PendingMove) {
        PendingMoves.add(move)
        resolvePendingMoves()
    }

    func removePendingMove(_ id: UUID) {
        doneMoveTimers[id]?.cancel()
        doneMoveTimers.removeValue(forKey: id)
        PendingMoves.remove(id)
        pendingMoves.removeAll { $0.id == id }
        pendingMoveStates.removeValue(forKey: id)
    }

    /// Resuelve los traspasos pendientes contra `state.movements`: caducados fuera en silencio;
    /// hechos en cuenta propia se marcan como traspaso propio y se retiran tras 6 s.
    func resolvePendingMoves(now: Date = Date()) {
        guard !resolvingMoves else { return }
        resolvingMoves = true
        defer { resolvingMoves = false }

        let stored = PendingMoves.all()
        var kept: [PendingMove] = []
        var states: [UUID: MoveState] = [:]
        var claimed = Set<UUID>()
        var ownTransfersToMark: [UUID] = []
        var removedExpired = false

        for move in stored {
            let resolved = moveState(move, movements: state.movements, now: now, claimed: claimed)
            switch resolved {
            case .expired:
                removedExpired = true
                doneMoveTimers[move.id]?.cancel()
                doneMoveTimers.removeValue(forKey: move.id)
            case .waiting:
                kept.append(move)
                states[move.id] = .waiting
            case .done(let movementID):
                claimed.insert(movementID)
                kept.append(move)
                states[move.id] = .done(movementID: movementID)
                if case .own = move.target,
                   let match = state.movements.first(where: { $0.id == movementID }),
                   match.ownTransfer != true {
                    ownTransfersToMark.append(movementID)
                }
                if doneMoveTimers[move.id] == nil {
                    let moveID = move.id
                    doneMoveTimers[moveID] = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(6))
                        guard !Task.isCancelled, let self else { return }
                        self.removePendingMove(moveID)
                    }
                }
            }
        }

        if removedExpired {
            PendingMoves.save(kept)
        }
        pendingMoves = kept
        pendingMoveStates = states

        for movementID in ownTransfersToMark {
            try? setOwnTransfer(true, for: movementID)
        }
    }

    /// Resumen semanal y recordatorios de suscripciones: se rehacen con cada cambio del libro (nunca en la demo).
    private func reschedule(_ next: LedgerState) {
        #if DEBUG
        if DemoMode.isActive { return }
        #endif
        Task { await AlertScheduler.reschedule(for: next) }
    }

    /// Solo desde el aviso de los intents. Si entre lo nuevo hay un movimiento que no estaba, es una llegada:
    /// se anuncia ya (Inicio desliza el carrusel hasta su banco) y el estado nuevo se publica un instante después,
    /// dentro de una animación de desaceleración, para que el saldo y el total rueden con la tarjeta ya en su sitio.
    private func reloadAfterIngest() {
        guard let next = loadNext(), next != state else { return }
        let known = Set(state.movements.map(\.id))
        // Solo un aviso o un pago de Cartera es una llegada; lo que trae el banco (aunque se cuele aquí) nunca.
        guard let newest = next.movements.filter({ !known.contains($0.id) && ($0.source == .notification || $0.source == .wallet) })
            .max(by: { $0.date < $1.date }),
              abs(newest.date.timeIntervalSinceNow) < 600 else {
            publish(next)
            return
        }
        arrival = Arrival(id: newest.id, bank: newest.bank, isIncome: newest.amountCents > 0,
                          title: newest.displayTitle, amountCents: newest.amountCents)
        generation += 1
        let mine = generation
        staged?.cancel()
        staged = Task { [weak self] in
            try? await Task.sleep(for: Theme.Motion.arrivalLead)
            guard let self, !Task.isCancelled, self.generation == mine else { return }
            let animation: Animation? = UIAccessibility.isReduceMotionEnabled ? nil : Theme.Motion.roll
            withAnimation(animation) {
                self.state = next
                self.snapshot = LedgerSnapshot(state: next)
            }
            self.staged = nil
            self.reschedule(next)
            self.resolvePendingMoves()
        }
    }

    #if DEBUG
    /// Demo (`-MiBancoDemoArrival`): ingesta un pago de Apple Pay con el mismo `Ledger.ingest` que los intents,
    /// deja el estado nuevo donde `reload` lo lee y publica `ledgerDidChange`: el resto (detección de la llegada,
    /// coreografía, háptica, aviso de VoiceOver) es el código real.
    func demoSimulateArrival() {
        var ledger = Ledger(state: state)
        guard case .stored = ledger.ingest(.wallet(bank: .ima, amount: "23,45", merchant: "Carrefour"), now: Date()) else { return }
        demoIncoming = ledger.state
        NotificationCenter.default.post(name: .ledgerDidChange, object: nil)
    }
    #endif

    // MARK: - Cambios (todos pasan por las mutaciones de Core y reconstruyen el snapshot)

    func setBalance(_ bank: BankID, cents: Int) throws {
        try mutate { $0.setBalance(bank, cents: cents, now: Date()) }
    }

    func deleteUnread(_ id: UUID) throws {
        try mutate { $0.removeUnread(id: id) }
    }

    func setNote(_ note: String?, for id: UUID) throws {
        try mutate { $0.setNote(note, for: id) }
    }

    func setFlaggedNotMine(_ flagged: Bool, for id: UUID) throws {
        try mutate { $0.setFlaggedNotMine(flagged, for: id) }
    }

    func setMuted(_ muted: Bool, merchant: String) throws {
        try mutate { $0.setMuted(muted, merchant: merchant) }
    }

    func deleteMovement(_ id: UUID) throws {
        try mutate { $0.deleteMovement(id: id) }
    }

    func updateAlertSettings(_ body: (inout AlertSettings) -> Void) throws {
        try mutate { $0.updateAlertSettings(body) }
    }

    func unmute(_ merchant: MutedMerchant) throws {
        try mutate { $0.setMuted(false, merchant: merchant.raw) }
    }

    /// Categoría de un pago; con `applyToMerchant` se recuerda para todo el comercio. nil devuelve la que decide la app.
    func setCategory(_ category: SpendingCategory?, for id: UUID, applyToMerchant: Bool) throws {
        try mutate { $0.setCategory(category, for: id, applyToMerchant: applyToMerchant) }
    }

    /// «Volver a la categoría automática» (ver `Ledger.resetCategoryToAutomatic`).
    func resetCategory(for id: UUID) throws {
        try mutate { $0.resetCategoryToAutomatic(for: id) }
    }

    /// true si la categoría del pago la eligió el dueño (en el pago o para su comercio).
    func hasChosenCategory(_ id: UUID) -> Bool {
        Ledger(state: state).hasChosenCategory(id)
    }

    /// true si el pago tiene categoría elegida en él mismo (no solo la de su comercio).
    func hasOwnCategory(_ id: UUID) -> Bool {
        Ledger(state: state).hasOwnCategory(id)
    }

    /// true = traspaso entre tus cuentas; false = no lo es (aunque lo parezca); nil = que lo decida la app.
    func setOwnTransfer(_ value: Bool?, for id: UUID) throws {
        try mutate { $0.setOwnTransfer(value, for: id) }
    }

    func setMonthlyBudget(_ cents: Int?) throws {
        try mutate { $0.setMonthlyBudget(cents) }
    }

    func setSubscriptionDismissed(_ dismissed: Bool, id: String) throws {
        try mutate { $0.setSubscriptionDismissed(dismissed, id: id) }
    }

    func setBudget(_ cents: Int?, for category: SpendingCategory) throws {
        try mutate { $0.setBudget(cents, for: category) }
    }

    /// Restaura una copia: antes guarda lo actual como `ledger-antes-de-restaurar.json`, las dos cosas dentro de una sola
    /// actualización coordinada. Si esa copia falla no se restaura nada y lanza `RestoreError.safetyCopyFailed`.
    func restore(_ file: BackupFile) throws {
        #if DEBUG
        if DemoMode.isActive {
            // Las mismas reglas que en disco (`Ledger.restore`: las conexiones con bancos no salen de la copia).
            var ledger = Ledger(state: state)
            ledger.restore(file.ledger)
            publish(ledger.state)
            restoreCount += 1
            return
        }
        #endif
        try store.restoreKeepingCopy(file.ledger, copyName: Self.safetyCopyName)
        // Se publica lo que quedó en disco aunque coincida con lo anterior: así se rehacen siempre el snapshot y los
        // recordatorios (`reschedule`) con los datos restaurados.
        let reloaded: LedgerState
        do { reloaded = try store.load() } catch { throw RestoreError.reloadFailed }
        publish(reloaded)
        restoreCount += 1
    }

    /// Nombre de la copia que se guarda antes de cada restauración.
    static let safetyCopyName = "ledger-antes-de-restaurar.json"

    /// Sube con cada restauración: Ajustes relee la copia previa.
    private(set) var restoreCount = 0

    /// La copia guardada antes de la última restauración, lista para "Volver a lo de antes" (nil si no hay).
    func previousPreview(portfolioSafetyCopy: Portfolio? = nil) -> RestorePreview? {
        #if DEBUG
        if DemoMode.isActive {
            guard DemoMode.scrollsToBackup else { return nil }
            let demo = DemoMode.demoPreviousPreview(currentCount: state.movements.count)
            return RestorePreview(
                file: BackupFile(exportedAt: demo.file.exportedAt, ledger: demo.file.ledger, portfolio: portfolioSafetyCopy),
                currentCount: demo.currentCount,
                isPrevious: true
            )
        }
        #endif
        guard let info = store.copyInfo(named: Self.safetyCopyName) else { return nil }
        return RestorePreview(file: BackupFile(exportedAt: info.date, ledger: info.state, portfolio: portfolioSafetyCopy),
                              currentCount: state.movements.count, isPrevious: true)
    }

    func movement(_ id: UUID) -> Movement? {
        state.movements.first { $0.id == id }
    }

    /// En la demo, los cambios se quedan en memoria (las capturas nunca escriben en el almacén).
    private func mutate(_ body: (inout Ledger) -> Void) throws {
        #if DEBUG
        if DemoMode.isActive {
            var ledger = Ledger(state: state)
            body(&ledger)
            publish(ledger.state)
            return
        }
        #endif
        try store.update { body(&$0) }
        reload()
    }
}
