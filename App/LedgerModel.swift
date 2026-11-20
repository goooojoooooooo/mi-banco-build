import Foundation
import Observation
import SwiftUI
import UIKit
import MiBancoCore

extension Notification.Name {
    /// Los intents la publican tras guardar en el almacén; el modelo recarga al recibirla.
    static let ledgerDidChange = Notification.Name("com.mibanco.ledgerDidChange")
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
    private let store: FileStore
    @ObservationIgnored private var observer: Task<Void, Never>?
    /// Publicación aplazada de una llegada; cualquier publicación posterior la deja sin efecto.
    @ObservationIgnored private var staged: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
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
    }

    /// Si falla la lectura se conserva lo que ya se mostraba.
    func reload() {
        guard let loaded = loadNext() else { return }
        if loaded != state || !Calendar.current.isDateInToday(snapshot.day) {
            publish(loaded)
        }
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
        guard let newest = next.movements.filter({ !known.contains($0.id) }).max(by: { $0.date < $1.date }),
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
