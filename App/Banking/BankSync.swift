import Foundation
import MiBancoCore
import Observation
import Security
import UIKit

extension Notification.Name {
    /// Un banco actualizó el libro. Distinta de `ledgerDidChange` (avisos e intents): esa puede traer una "llegada"
    /// animada en Inicio; esta nunca.
    static let ledgerDidSyncFromBank = Notification.Name("com.mibanco.ledgerDidSyncFromBank")
}

/// Estado para la pantalla de bancos y el diagnóstico de Ajustes. Este código no presenta nada.
@MainActor @Observable
final class BankSyncStatus {
    static let shared = BankSyncStatus()
    private(set) var running: Set<BankID> = []
    private(set) var lastOutcome: [BankID: SyncOutcome] = [:]
    /// Solo los NOMBRES de las cabeceras PSU requeridas según `GET /aspsps` (diagnóstico seguro en Ajustes).
    private(set) var requiredPSUHeaders: [BankID: [String]] = [:]

    fileprivate func begin(_ bank: BankID) { running.insert(bank) }
    fileprivate func end(_ bank: BankID, _ outcome: SyncOutcome?) {
        running.remove(bank)
        if let outcome { lastOutcome[bank] = outcome }
    }

    func updateRequiredPSUHeaders(_ bank: BankID, _ headers: [String]?) {
        if let headers {
            requiredPSUHeaders[bank] = headers
        } else {
            requiredPSUHeaders.removeValue(forKey: bank)
        }
    }

    func clearRequiredPSUHeaders() {
        requiredPSUHeaders = [:]
    }

    /// Lee del Llavero (y respaldo de la lista en memoria) únicamente los nombres de cabeceras PSU requeridas.
    func reloadRequiredPSUHeaders(cachedASPSPs: [EBASPSP]? = nil) {
        #if DEBUG
        if DemoMode.isActive { return }
        #endif
        var next: [BankID: [String]] = [:]
        for bank in BankID.allCases {
            if let session = (try? KeychainVault.codable(StoredSession.self, for: KeychainVault.session(for: bank))) ?? nil {
                if let req = session.requiredPSUHeaders {
                    next[bank] = req
                } else if let list = cachedASPSPs,
                          let matched = findASPSP(name: session.aspspName, country: session.aspspCountry, bank: bank, in: list) {
                    next[bank] = matched.requiredPSUHeaders ?? []
                }
            }
        }
        requiredPSUHeaders = next
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
    private var queuedAfterConnect: [BankID: Bool] = [:]
    /// Sesiones en las que Enable Banking devolvió 422 PSU aunque `GET /aspsps` no exigía nada nuevo:
    /// se evita repetir cabeceras PSU en bucle hasta cambiar de sesión.
    private var psuRejectedSessions: Set<String> = []

    nonisolated static var isEnabled: Bool {
        #if DEBUG
        if DemoMode.isActive { return false }
        #endif
        return BankingCredentials.isReady
    }

    /// Cabeceras PSU construidas solo con datos locales no identificativos del iPhone (sin modelo de hardware,
    /// sin UDID, sin nombre del teléfono y sin consultar ningún servicio externo).
    nonisolated static func localPSUHeaders() -> [String: String] {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = os.patchVersion > 0
            ? "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
            : "\(os.majorVersion).\(os.minorVersion)"
        return buildLocalPSUHeaders(
            appName: AppIdentity.displayName,
            appVersion: appVersion,
            osVersion: osVersion,
            preferredLanguage: Locale.preferredLanguages.first
        )
    }

    /// Al abrir la app: solo si ya se superó el bloqueo y está de verdad en primer plano EN ESTE MOMENTO
    /// (se lee el estado vivo, no el de cuando se pidió).
    @MainActor
    static func refreshOnOpen(isUnlocked: Bool) {
        guard isUnlocked, UIApplication.shared.applicationState == .active else { return }
        Task { _ = await BankSync.shared.refresh(trigger: .appOpen, isUnlocked: true) }
    }

    /// Un banco se conectó, renovó o desconectó: se rehacen los avisos de caducidad y, si sigue conectado, se consulta.
    func linkDidChange(_ bank: BankID?, isUnlocked: Bool = true) async {
        await rescheduleReminders()
        guard let bank else { return }
        _ = await refresh(trigger: .afterConnect, only: bank, isUnlocked: isUnlocked)
    }

    func refresh(trigger: SyncTrigger, only bank: BankID? = nil, isUnlocked: Bool = true) async -> [BankID: SyncOutcome] {
        guard Self.isEnabled else { return [:] }
        let banks = bank.map { [$0] } ?? BankID.allCases
        if running {
            if trigger == .afterConnect {
                for b in banks { queuedAfterConnect[b] = (queuedAfterConnect[b] ?? false) || isUnlocked }
            }
            return Dictionary(uniqueKeysWithValues: banks.map { ($0, SyncOutcome.skipped(.fresh)) })
        }
        running = true
        defer { running = false }

        var results = await runBanks(banks, trigger: trigger, isUnlocked: isUnlocked)
        // Lo que pidieron "tras conectar" mientras tanto, ya sin nadie más en marcha.
        while !queuedAfterConnect.isEmpty, !Task.isCancelled {
            let next = queuedAfterConnect.sorted { $0.key.rawValue < $1.key.rawValue }
            queuedAfterConnect = [:]
            for (queuedBank, queuedUnlocked) in next {
                if Task.isCancelled { break }
                results.merge(await runBanks([queuedBank], trigger: .afterConnect, isUnlocked: queuedUnlocked)) { _, new in new }
            }
        }
        queuedAfterConnect = [:]
        await rescheduleReminders()
        return results
    }

    /// Para el diagnóstico de Ajustes: si algún banco conectado todavía no tiene `requiredPSUHeaders` leído
    /// (sesión guardada antes de L1), consulta `GET /aspsps` una sola vez y guarda los nombres requeridos.
    func prefetchMissingRequiredPSUHeaders() async {
        guard Self.isEnabled else { return }
        let links = (try? SharedStore.make().load().links) ?? [:]
        var aspspCache: [String: [EBASPSP]] = [:]
        for bank in BankID.allCases where links[bank] != nil {
            if Task.isCancelled { break }
            guard let session = (try? KeychainVault.codable(StoredSession.self, for: KeychainVault.session(for: bank))) ?? nil else {
                continue
            }
            if let existing = session.requiredPSUHeaders {
                await BankSyncStatus.shared.updateRequiredPSUHeaders(bank, existing)
                continue
            }
            _ = await fetchAndStoreRequiredPSUHeaders(for: bank, session: session, aspspCache: &aspspCache, forceNetwork: false)
        }
    }

    // MARK: - Interno

    private func runBanks(_ banks: [BankID], trigger: SyncTrigger, isUnlocked: Bool) async -> [BankID: SyncOutcome] {
        let store = SharedStore.make()
        var results: [BankID: SyncOutcome] = [:]
        let loaded = (try? store.load()) ?? LedgerState()
        var links = loaded.links
        let calendar = bankingCalendar

        // En segundo plano NUNCA se construyen ni se envían cabeceras PSU; con usuario presente, solo en primer plano
        // y con el bloqueo superado.
        let availablePSU: [String: String]
        if trigger == .background {
            availablePSU = [:]
        } else {
            let active = await MainActor.run { UIApplication.shared.applicationState == .active }
            availablePSU = (active && isUnlocked) ? Self.localPSUHeaders() : [:]
        }

        var aspspCache: [String: [EBASPSP]] = [:]
        var psuByBank: [BankID: [String: String]] = [:]
        if !availablePSU.isEmpty {
            let now = Date()
            for bank in banks {
                if Task.isCancelled { break }
                guard let link = links[bank] else { continue }
                let blockedEarly = now >= link.consentValidUntil
                    || link.problem == .consentExpired
                    || link.problem == .keyRejected
                    || (link.backoffUntil.map { $0 > now } ?? false)
                guard !blockedEarly else { continue }
                if let resolved = await resolvePSUHeaders(
                    for: bank, trigger: trigger, availablePSU: availablePSU, aspspCache: &aspspCache) {
                    psuByBank[bank] = resolved
                }
            }
        }
        let hasPSUByBank = Dictionary(uniqueKeysWithValues: banks.map { ($0, psuByBank[$0] != nil) })

        let plans = banksToFetch(
            links: links.filter { banks.contains($0.key) }, trigger: trigger, now: Date(), calendar: calendar,
            oldestPending: oldestPending(in: loaded, calendar: calendar),
            hasPSUHeaders: hasPSUByBank)
        let planned = Dictionary(uniqueKeysWithValues: plans.map { ($0.bank, $0) })

        for bank in banks {
            if Task.isCancelled { break }
            let bankPSU = psuByBank[bank]
            // Un banco que falla nunca frena a los demás: cada uno devuelve su propio resultado.
            guard planned[bank] != nil else {
                if case let .skip(reason) = SyncPolicy.decide(
                    links[bank], trigger: trigger, now: Date(), calendar: calendar, hasPSUHeaders: bankPSU != nil) {
                    results[bank] = .skipped(reason)
                }
                continue
            }
            // El libro puede haber cambiado mientras iban los bancos anteriores: se decide otra vez con lo vivo.
            let live = (try? store.load()) ?? loaded
            links = live.links
            let decision = SyncPolicy.decide(
                links[bank], trigger: trigger, now: Date(), calendar: calendar,
                oldestPending: Ledger(state: live).oldestPendingBankRow(bank, now: Date(), calendar: calendar),
                hasPSUHeaders: bankPSU != nil)
            guard case let .fetch(dateFrom, strategy) = decision else {
                if case let .skip(reason) = decision { results[bank] = .skipped(reason) }
                continue
            }
            await BankSyncStatus.shared.begin(bank)
            let outcome = await sync(
                bank, trigger: trigger, dateFrom: dateFrom, strategy: strategy,
                psuHeaders: bankPSU, availablePSU: availablePSU, store: store, calendar: calendar)
            await BankSyncStatus.shared.end(bank, outcome)
            if let outcome { results[bank] = outcome }
        }
        return results
    }

    private func resolvePSUHeaders(
        for bank: BankID,
        trigger: SyncTrigger,
        availablePSU: [String: String],
        aspspCache: inout [String: [EBASPSP]]
    ) async -> [String: String]? {
        guard trigger != .background, !availablePSU.isEmpty else { return nil }
        guard let session = (try? KeychainVault.codable(StoredSession.self, for: KeychainVault.session(for: bank))) ?? nil else {
            return nil
        }
        guard !psuRejectedSessions.contains(session.sessionID) else { return nil }
        let required: [String]?
        if let stored = session.requiredPSUHeaders {
            required = stored
            await BankSyncStatus.shared.updateRequiredPSUHeaders(bank, stored)
        } else {
            required = await fetchAndStoreRequiredPSUHeaders(
                for: bank, session: session, aspspCache: &aspspCache, forceNetwork: false)
        }
        // Si no se han podido confirmar las cabeceras requeridas del banco, no arriesgamos un 422: seguimos sin PSU.
        guard let required else { return nil }
        return psuHeaders(for: trigger, required: required, available: availablePSU)
    }

    private func fetchAndStoreRequiredPSUHeaders(
        for bank: BankID,
        session: StoredSession,
        aspspCache: inout [String: [EBASPSP]],
        forceNetwork: Bool
    ) async -> [String]? {
        let countryKey = session.aspspCountry.uppercased()
        var list: [EBASPSP]?
        if !forceNetwork {
            if let inRun = aspspCache[countryKey] {
                list = inRun
            } else if countryKey == BankingConstants.country.uppercased(),
                      let cached = await MainActor.run(body: { BankConnector.shared.cachedASPSPs }) {
                list = cached
                aspspCache[countryKey] = cached
            }
        }
        if list == nil {
            guard let client = try? BankingCredentials.client(),
                  let fetched = try? await client.aspsps(country: session.aspspCountry) else {
                return nil
            }
            list = fetched
            aspspCache[countryKey] = fetched
            if countryKey == BankingConstants.country.uppercased() {
                await BankConnector.shared.cacheASPSPs(fetched)
            }
        }
        guard let list,
              let matched = findASPSP(name: session.aspspName, country: session.aspspCountry, bank: bank, in: list) else {
            return nil
        }
        let resolved = matched.requiredPSUHeaders ?? []
        persistRequiredPSUHeaders(resolved, for: bank, expectedSessionID: session.sessionID)
        await BankSyncStatus.shared.updateRequiredPSUHeaders(bank, resolved)
        return resolved
    }

    private func persistRequiredPSUHeaders(_ headers: [String]?, for bank: BankID, expectedSessionID: String) {
        let item = KeychainVault.session(for: bank)
        guard var current = (try? KeychainVault.codable(StoredSession.self, for: item)) ?? nil,
              current.sessionID == expectedSessionID else { return }
        current.requiredPSUHeaders = headers
        try? KeychainVault.setCodable(current, for: item)
    }

    /// `nil` = cancelada: ni éxito ni fallo, no se anota nada más y el banco no aparece en el resultado.
    private func sync(
        _ bank: BankID,
        trigger: SyncTrigger,
        dateFrom: Date,
        strategy: TransactionStrategy,
        psuHeaders activePSU: [String: String]?,
        availablePSU: [String: String],
        store: FileStore,
        calendar: Calendar
    ) async -> SyncOutcome? {
        // 0. Sesión y cliente ANTES de anotar nada: un fallo local (Llavero sin desbloquear tras reiniciar, credenciales
        // ilegibles) no gasta uno de los intentos del día, no pone espera ni aparece como fallo del banco.
        var stored: StoredSession?
        do {
            stored = try KeychainVault.codable(StoredSession.self, for: KeychainVault.session(for: bank))
        } catch {
            // Solo el Llavero aún bloqueado tras reiniciar es pasajero; un dato ilegible o cualquier otro error se trata
            // como sesión que falta (se anota y se avisa de que hay que renovar), no se calla para siempre.
            if !recordsSessionReadFailure(Self.sessionReadFailure(error)) { return nil }
            stored = nil
        }
        let client: EnableBankingClient
        do { client = try BankingCredentials.client() } catch { return nil }
        guard let session = stored else {
            // Hay conexión en el libro pero no sesión en el Llavero (otro dispositivo, copia restaurada): hay que renovar.
            return await recordFailure(bank, BankingClientError.api(.consentExpired, code: nil), startedSession: nil,
                                       attemptAt: Date(), store: store)
        }

        // Revalidamos las cabeceras PSU contra la sesión viva (por si hubo una reconexión entre medias).
        let effectivePSU: [String: String]?
        if let activePSU, !psuRejectedSessions.contains(session.sessionID), let required = session.requiredPSUHeaders {
            effectivePSU = psuHeaders(for: trigger, required: required, available: activePSU)
        } else {
            effectivePSU = nil
        }

        // 1. El intento queda anotado antes de llamar (solo cuenta para el cupo diario de 4/24 h si va sin cabeceras PSU).
        let attemptAt = Date()
        let linkBeforeAttempt: BankLinkInfo?
        do {
            linkBeforeAttempt = try store.update { ledger -> BankLinkInfo? in
                guard let link = ledger.state.links[bank] else { return nil }
                ledger.setLink(bank, link.recordingAttempt(at: attemptAt, countsTowardDailyBudget: effectivePSU == nil))
                return link
            }
        } catch {
            // Un fallo de disco no es del banco: sin resultado.
            return nil
        }
        guard let linkBeforeAttempt else { return .skipped(.notConnected) }

        do {
            return try await performFetchAndApply(
                bank: bank, session: session, client: client, dateFrom: dateFrom, strategy: strategy,
                psuHeaders: effectivePSU, store: store, calendar: calendar)
        } catch {
            // Una cancelación (caducó la tarea de fondo, la app se va) o un fallo local (disco) no son un fallo del
            // banco: no se anotan.
            if error is CancellationError || Task.isCancelled || !isBankFailure(error) { return nil }
            if effectivePSU != nil, isPSUHeaderRejection(error) {
                return await handlePSURejection(
                    bank: bank, trigger: trigger, session: session, client: client,
                    linkBeforeAttempt: linkBeforeAttempt, availablePSU: availablePSU,
                    store: store, calendar: calendar)
            }
            return await recordFailure(bank, error, startedSession: session.sessionID, attemptAt: attemptAt, store: store)
        }
    }

    private func performFetchAndApply(
        bank: BankID,
        session: StoredSession,
        client: EnableBankingClient,
        dateFrom: Date,
        strategy: TransactionStrategy,
        psuHeaders: [String: String]?,
        store: FileStore,
        calendar: Calendar
    ) async throws -> SyncOutcome {
        let from = bankDateParameter(dateFrom, calendar: calendar)
        // 2 y 3. Saldos y movimientos de cada cuenta. Todo se reúne antes de tocar el libro.
        var balances: [[EBBalance]] = []
        var transactions: [EBTransaction] = []
        var complete = true
        for uid in session.accountUIDs {
            balances.append(try await client.balances(accountUID: uid, psuHeaders: psuHeaders))
            let fetch = try await client.fetchTransactions(
                accountUID: uid, dateFrom: from, strategy: strategy, psuHeaders: psuHeaders)
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
    }

    /// Ante un 422 (`PSU_HEADER_NOT_PROVIDED` / `PSU_HEADER_INVALID`) en una consulta con cabeceras PSU:
    /// refresca `required_psu_headers` de `GET /aspsps` (o los invalida si no se pueden leer) para no repetir el 422
    /// en bucle y, si el cupo sin cabeceras PSU lo permite, hace un único reintento limpio sin cabeceras PSU.
    private func handlePSURejection(
        bank: BankID,
        trigger: SyncTrigger,
        session: StoredSession,
        client: EnableBankingClient,
        linkBeforeAttempt: BankLinkInfo,
        availablePSU: [String: String],
        store: FileStore,
        calendar: Calendar
    ) async -> SyncOutcome? {
        var freshCache: [String: [EBASPSP]] = [:]
        let refreshed = await fetchAndStoreRequiredPSUHeaders(
            for: bank, session: session, aspspCache: &freshCache, forceNetwork: true)
        if let refreshed {
            if psuHeaders(for: trigger, required: refreshed, available: availablePSU) != nil {
                psuRejectedSessions.insert(session.sessionID)
            }
        } else {
            persistRequiredPSUHeaders(nil, for: bank, expectedSessionID: session.sessionID)
            await BankSyncStatus.shared.updateRequiredPSUHeaders(bank, nil)
            psuRejectedSessions.insert(session.sessionID)
        }

        let liveSession = (try? KeychainVault.codable(StoredSession.self, for: KeychainVault.session(for: bank))) ?? nil
        guard liveSession?.sessionID == session.sessionID else { return nil }
        let liveState = (try? store.load()) ?? LedgerState()
        guard liveState.links[bank] != nil else { return .skipped(.notConnected) }

        let now = Date()
        let fallbackDecision = SyncPolicy.decide(
            linkBeforeAttempt,
            trigger: trigger,
            now: now,
            calendar: calendar,
            oldestPending: Ledger(state: liveState).oldestPendingBankRow(bank, now: now, calendar: calendar),
            hasPSUHeaders: false
        )
        guard case let .fetch(fallbackDateFrom, fallbackStrategy) = fallbackDecision else {
            if case let .skip(reason) = fallbackDecision { return .skipped(reason) }
            return nil
        }

        let fallbackAttemptAt = Date()
        let stillConnected: Bool
        do {
            stillConnected = try store.update { ledger -> Bool in
                guard let link = ledger.state.links[bank] else { return false }
                ledger.setLink(bank, link.recordingAttempt(at: fallbackAttemptAt, countsTowardDailyBudget: true))
                return true
            }
        } catch {
            return nil
        }
        guard stillConnected else { return .skipped(.notConnected) }

        do {
            return try await performFetchAndApply(
                bank: bank, session: session, client: client, dateFrom: fallbackDateFrom, strategy: fallbackStrategy,
                psuHeaders: nil, store: store, calendar: calendar)
        } catch {
            if error is CancellationError || Task.isCancelled || !isBankFailure(error) { return nil }
            return await recordFailure(
                bank, error, startedSession: session.sessionID, attemptAt: fallbackAttemptAt, store: store)
        }
    }

    private func oldestPending(in state: LedgerState, calendar: Calendar) -> [BankID: Date] {
        let ledger = Ledger(state: state)
        let now = Date()
        var out: [BankID: Date] = [:]
        for bank in BankID.allCases {
            if let date = ledger.oldestPendingBankRow(bank, now: now, calendar: calendar) { out[bank] = date }
        }
        return out
    }

    private static func sessionReadFailure(_ error: Error) -> SessionReadFailure {
        if let keychain = error as? KeychainError, case .status(let code) = keychain, code == errSecInteractionNotAllowed {
            return .deviceLocked
        }
        return .unreadable
    }

    /// Si mientras tanto hubo una reconexión o renovación, el fallo es de la sesión vieja: no se anota, no se borra la
    /// sesión nueva del Llavero y no hay resultado (decide Core: `syncFailureAction`).
    private func recordFailure(
        _ bank: BankID, _ error: Error, startedSession: String?, attemptAt: Date, store: FileStore
    ) async -> SyncOutcome? {
        let problem = syncProblem(for: error)
        let current = (try? KeychainVault.codable(StoredSession.self, for: KeychainVault.session(for: bank))) ?? nil
        let action = (try? store.update { ledger -> SyncFailureAction in
            let action = syncFailureAction(
                problem: problem, startedSessionID: startedSession, currentSessionID: current?.sessionID,
                link: ledger.state.links[bank], attemptAt: attemptAt)
            if case .record = action, let link = ledger.state.links[bank] {
                ledger.setLink(bank, link.applying(.failure(error), at: Date()))
            }
            return action
        }) ?? .drop
        guard case let .record(deleteSession) = action else { return nil }
        if deleteSession {
            // Se vuelve a leer justo antes de borrar: solo se borra la sesión con la que arrancó esta consulta (o una
            // ilegible si no había ninguna); una reconexión en medio dejó otra y esa no se toca.
            let nowID = ((try? KeychainVault.codable(StoredSession.self, for: KeychainVault.session(for: bank))) ?? nil)?.sessionID
            if nowID == startedSession { try? KeychainVault.delete(KeychainVault.session(for: bank)) }
        }
        NotificationCenter.default.post(name: .ledgerDidSyncFromBank, object: nil)
        return .failed(problem)
    }

    private func rescheduleReminders() async {
        let links = (try? SharedStore.make().load().links) ?? [:]
        await BankReminders.reschedule(links: links)
    }
}
