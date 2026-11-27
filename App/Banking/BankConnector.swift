import AuthenticationServices
import Foundation
import MiBancoCore
import Observation
import Security
import SwiftUI

extension Notification.Name {
    static let bankLinkDidChange = Notification.Name("com.mibanco.bankLinkDidChange")
}

/// Conecta un banco con Enable Banking (solo lectura). Las decisiones (bloqueo, escena, plazo, qué hace una vuelta en
/// cada estado) las toma `ConnectFlow` en Core; aquí solo se ejecutan sus acciones.
/// El bloqueo con Face ID no interviene: la hoja web solo enseña la página del banco, y una vuelta con la app
/// bloqueada se procesa igual; `phase` queda aquí para mostrarse tras desbloquear.
/// Nada de lo que pasa por aquí (código, `state`, id de sesión) se escribe en registros, descripciones ni ajustes.
@MainActor @Observable
final class BankConnector {
    static let shared = BankConnector()

    private var flow = ConnectFlow()
    /// Lista de bancos de Enable Banking, solo en memoria.
    private(set) var cachedASPSPs: [EBASPSP]?
    /// true mientras «Olvidar clave y conexiones» borra lo local (U43).
    var isForgetting = false

    // La dirección del banco y la hoja web viven solo en memoria.
    @ObservationIgnored private var authURL: URL?
    @ObservationIgnored private var requestedUntil: Date?
    @ObservationIgnored private var webSession: ASWebAuthenticationSession?
    @ObservationIgnored private var webToken: UUID?
    @ObservationIgnored private let anchorProvider = WebAnchorProvider()
    /// Cambia con cada intento: un intento viejo que despierta tras un `await` se retira.
    @ObservationIgnored private var attempt = UUID()

    /// Un intento a medias que ya caducó no sirve para nada: se borra al arrancar.
    private init() {
        #if DEBUG
        if DemoMode.isActive {
            if let spec = DemoMode.demoConnectPhase {
                applyDemoPhase(spec.phase, bank: spec.bank)
            }
            return
        }
        #endif
        if let pending = loadPending(), pending.isExpired(now: Date()) { deletePending() }
    }

    #if DEBUG
    private func applyDemoPhase(_ name: String, bank: BankID) {
        switch name {
        case "opening":
            _ = flow.handle(.start(bank))
        case "waitingForBank":
            _ = flow.handle(.start(bank))
            _ = flow.handle(.webOpened(bank))
        case "finishing":
            _ = flow.handle(.start(bank))
            _ = flow.handle(.webOpened(bank))
            _ = flow.handle(.callback(.valid(bank)))
        case "needsResume":
            _ = flow.handle(.start(bank))
            _ = flow.handle(.webOpened(bank))
            _ = flow.handle(.cancel)
        case "failed":
            _ = flow.handle(.start(bank))
            _ = flow.handle(.failed(bank, ConnectMessage.tooSlow))
        case "chooseASPSP":
            _ = flow.handle(.start(bank))
            _ = flow.handle(.needsChoice(bank, [
                EBASPSP(name: "Revolut", country: "ES"),
                EBASPSP(name: "imaginBank", country: "ES"),
            ]))
        default:
            break
        }
    }
    #endif

    var phase: ConnectPhase { flow.phase }

    /// Abriendo, esperando al banco o terminando.
    var isActive: Bool { flow.phase.isActive }

    func canConnect(_ bank: BankID) -> Bool {
        canConnectBank(bank, cachedList: cachedASPSPs)
    }

    /// Descarga y guarda en memoria la lista de bancos (así Trade Republic puede pasar a conectable).
    func refreshASPSPList() async {
        guard let client = try? BankingCredentials.client(),
              let list = try? await client.aspsps(country: BankingConstants.country) else { return }
        cachedASPSPs = list
        NotificationCenter.default.post(name: .ledgerDidSyncFromBank, object: nil)
    }

    // MARK: - Conectar

    func connect(_ bank: BankID, aspsp: EBASPSP? = nil) async {
        #if DEBUG
        if DemoMode.isActive {
            guard !isActive else { return }
            _ = flow.handle(.start(bank))
            return
        }
        #endif
        guard !isActive else { return }
        // Un intento anterior (de este banco u otro) ya no puede contestar a este: se borra ANTES del primer `await`.
        deletePending()
        flow.handle(.start(bank))
        let mine = UUID()
        attempt = mine
        authURL = nil
        requestedUntil = nil

        let client: EnableBankingClient
        do { client = try BankingCredentials.client() } catch {
            fail(bank, ConnectMessage.missingCredentials)
            return
        }

        // Banco concreto: el dado, o el que encaja por nombre en la lista.
        var chosen = aspsp
        if chosen == nil {
            do {
                let list = try await client.aspsps(country: BankingConstants.country)
                guard attempt == mine, flow.phase == .opening(bank) else { return }
                cachedASPSPs = list
                chosen = matchASPSP(for: bank, in: list)
                if chosen == nil {
                    if bank == .tr {
                        // Trade Republic no se ofrece sin coincidencia.
                        run(flow.handle(.reset))
                    } else {
                        flow.handle(.needsChoice(bank, list))
                    }
                    return
                }
            } catch {
                guard attempt == mine else { return }
                fail(bank, connectMessage(for: error))
                return
            }
        }
        guard let chosen else { return }

        // `state` aleatorio del sistema; el intento queda en el Llavero ANTES de abrir la hoja web.
        guard let state = Self.randomState() else {
            fail(bank, ConnectMessage.storeFailed)
            return
        }
        let until = consentValidUntil(for: chosen, now: Date())
        let pending = PendingAuth(
            state: state, bank: bank, aspspName: chosen.name, aspspCountry: chosen.country, startedAt: Date())
        do { try KeychainVault.setCodable(pending, for: .pendingAuth) } catch {
            fail(bank, ConnectMessage.storeFailed)
            return
        }
        requestedUntil = until

        do {
            let url = try await client.startAuth(aspsp: chosen, validUntil: until, state: state)
            guard attempt == mine, flow.phase == .opening(bank) else {
                if attempt == mine { deletePending() }
                return
            }
            authURL = url
            openWeb(url, bank: bank)
        } catch {
            guard attempt == mine else { return }
            fail(bank, connectMessage(for: error))
        }
    }

    /// Vuelve a abrir la dirección guardada mientras el intento tenga menos de 15 minutos; si no, empieza de nuevo.
    func resume() async {
        let check = pendingCheck()
        let actions = flow.handle(.resume(pending: check, hasAuthURL: authURL != nil))
        for action in actions {
            switch action {
            case .openWeb(let bank):
                if let url = authURL { openWeb(url, bank: bank) } else { fail(bank, ConnectMessage.tooSlow) }
            case .restart(let bank):
                deletePending()
                await connect(bank)
            default:
                break
            }
        }
    }

    /// Cancelación explícita: cierra la hoja web; en `.opening` vuelve a reposo y en `.waitingForBank` pasa a `.needsResume` (U50).
    func cancelWebSession() {
        run(flow.handle(.cancel))
    }

    /// Sale de `.needsResume` o `.failed` («Dejarlo» o al salir de la pantalla, U50).
    func resetTransientPhase() {
        run(flow.handle(.reset))
    }

    /// Abandona cualquier trámite en curso desde CUALQUIER fase y vuelve a `.idle` (U42: «Olvidar clave y conexiones»).
    func resetForForgetEverything() {
        attempt = UUID()
        authURL = nil
        requestedUntil = nil
        closeWebSession()
        deletePending()
        cachedASPSPs = nil
        run(flow.handle(.forgetAll))
    }

    /// Cambios de escena. El bloqueo no se mira: solo cuánto tiempo se ha estado fuera.
    func sceneDidChange(to scenePhase: ScenePhase) {
        switch scenePhase {
        case .background: run(flow.handle(.sceneBackground(Date())))
        case .active: run(flow.handle(.sceneActive(Date())))
        default: break
        }
    }

    // MARK: - La vuelta del banco

    /// SEC-11: comprueba síncronamente si una URL externa de `onOpenURL` corresponde a una conexión pendiente.
    /// Si no hay intento pendiente, se ignora de inmediato sin lanzar flujo, tarea ni error.
    func shouldHandleExternalCallback(_ url: URL) -> Bool {
        #if DEBUG
        if DemoMode.isActive { return false }
        #endif
        return shouldHandleIncomingBankCallback(url, pending: pendingCheck())
    }

    func handle(url: URL, fromWebSession: Bool = false) async {
        #if DEBUG
        if DemoMode.isActive { return }
        #endif
        // Solo `mibanco://cb`: lo demás se ignora sin ruido.
        guard isBankCallbackURL(url) else { return }

        // Todo lo siguiente, hasta el primer `await`, es síncrono: la primera llamada consume el intento
        // (lo borra del Llavero) y una segunda no encuentra nada.
        // La vuelta se VERIFICA primero contra el `state` guardado: cualquier app puede abrir `mibanco://cb?...`, y una
        // vuelta falsa por `onOpenURL` no debe cerrar la hoja del banco ni borrar el intento verdadero (la máquina la ignora);
        // si vino del propio cierre de la hoja web (`fromWebSession: true`), falla con `foreignLink` (R43).
        let pending = loadPending()
        // SEC-11: sin intento pendiente, una vuelta externa (`onOpenURL`) se ignora de inmediato sin tocar el flujo ni mostrar error.
        if !fromWebSession, pending == nil { return }
        let check: PendingCheck
        if let pending {
            check = pending.isExpired(now: Date()) ? .expired(pending.bank) : .valid(pending.bank)
        } else {
            check = .none
        }
        let result: AuthCallbackResult = pending.map { parseAuthCallback(url, expectedState: $0.state) } ?? .malformed
        let actions = flow.handle(.callbackReceived(check, result, fromWebSession: fromWebSession))

        var bankToProcess: BankID?
        for action in actions {
            if case .processCallback(let bank) = action { bankToProcess = bank } else { run([action]) }
        }
        guard let bank = bankToProcess, let pending else { return }

        // Consumir: pase lo que pase, este intento no vuelve a servir.
        do { try KeychainVault.delete(.pendingAuth) } catch {
            fail(bank, ConnectMessage.storeFailed)
            return
        }
        guard case .code(let code) = result else {
            fail(bank, connectMessage(for: result) ?? ConnectMessage.foreignLink)
            return
        }
        await finish(bank: bank, code: code, pending: pending)
    }

    private func finish(bank: BankID, code: String, pending: PendingAuth) async {
        // Si la persona desconecta mientras tanto, `attempt` cambia y este intento se retira.
        let mine = attempt
        let client: EnableBankingClient
        do { client = try BankingCredentials.client() } catch {
            fail(bank, ConnectMessage.missingCredentials)
            return
        }
        let authorization: EBSessionAuthorization
        do { authorization = try await client.authorizeSession(code: code) } catch {
            guard attempt == mine else { return }
            fail(bank, connectMessage(for: error))
            return
        }
        let session = authorization.session
        // Desde aquí hasta escribir no hay más `await`: lo que se comprueba ahora sigue valiendo al escribir.
        guard attempt == mine, flow.phase == .finishing(bank) else {
            try? await client.deleteSession(id: session.sessionID)
            return
        }
        let accounts = selectAccounts(session.accounts)
        guard !accounts.isEmpty else {
            try? await client.deleteSession(id: session.sessionID)
            guard attempt == mine else { return }
            fail(bank, ConnectMessage.noEuroAccount(bank))
            return
        }
        let fallback = EBASPSP(name: pending.aspspName, country: pending.aspspCountry)
        let now = Date()
        let until = session.validUntil ?? requestedUntil ?? consentValidUntil(for: fallback, now: now)
        let stored = StoredSession(
            sessionID: session.sessionID, accountUIDs: accounts.map(\.uid), validUntil: until,
            aspspName: pending.aspspName, aspspCountry: pending.aspspCountry)
        // La sesión que funcionaba hasta ahora (si la hay) se guarda: si algo falla se deja todo como estaba.
        let item = KeychainVault.session(for: bank)
        let previous = (try? KeychainVault.codable(StoredSession.self, for: item)) ?? nil
        do {
            try KeychainVault.setCodable(stored, for: item)
            _ = try SharedStore.make().update { ledger in
                let info = ledger.state.links[bank]?.renewed(consentValidUntil: until, at: now)
                    ?? BankLinkInfo(connectedAt: now, consentValidUntil: until)
                ledger.setLink(bank, info)
            }
        } catch {
            var canDeleteNewRemote = true
            switch rollbackAfterLedgerFailure(previous: previous) {
            case .restore(let old):
                if (try? KeychainVault.setCodable(old, for: item)) == nil {
                    canDeleteNewRemote = false
                }
            case .deleteNew:
                try? KeychainVault.delete(item)
            }
            if canDeleteNewRemote {
                try? await client.deleteSession(id: session.sessionID)
            }
            guard attempt == mine else { return }
            fail(bank, ConnectMessage.storeFailed)
            return
        }
        authURL = nil
        requestedUntil = nil
        // IBAN propio (si vino validado e inequívoco): va directo a la libreta del Llavero solo si estaba vacío,
        // nunca a `StoredSession`, `ledger.json` ni Trade Republic.
        if bank != .tr, let iban = authorization.primaryEuroIBAN {
            _ = AccountBookStore.fillIBANIfEmpty(iban, for: bank)
        }
        flow.handle(.succeeded(bank))
        NotificationCenter.default.post(name: .ledgerDidChange, object: nil)
        NotificationCenter.default.post(name: .bankLinkDidChange, object: nil, userInfo: ["bank": bank.rawValue])
        // Reconexión: la sesión remota vieja ya no hace falta (mejor esfuerzo).
        if let old = staleRemoteSessionID(previous: previous, new: stored) {
            try? await client.deleteSession(id: old)
        }
    }

    // MARK: - Desconectar

    func disconnect(_ bank: BankID) async {
        #if DEBUG
        if DemoMode.isActive { return }
        #endif
        // Un trámite de este banco (también uno que está terminando) se abandona: `attempt` cambia y `finish` se retira.
        attempt = UUID()
        run(flow.handle(.disconnected(bank)))
        // U78 (B-M9): como «Olvidar», lo local primero (sesión del Llavero y enlace del libro) y el aviso al banco al final.
        // El cliente se crea antes de borrar nada, para poder avisar al banco aunque luego falte algo.
        let remoteClient = try? BankingCredentials.client()
        await disconnectBankPlan(
            readSessionID: {
                (try? KeychainVault.codable(StoredSession.self, for: KeychainVault.session(for: bank)))?.sessionID
            },
            deleteLocal: {
                try? KeychainVault.delete(KeychainVault.session(for: bank))
            },
            unlinkLedger: {
                _ = try? SharedStore.make().update { ledger in
                    ledger.setLink(bank, nil)
                    if let balance = ledger.state.balances[bank], balance.origin == .bank {
                        ledger.adoptBalance(bank, cents: balance.cents, at: balance.setAt, origin: .manual)
                    }
                }
                await MainActor.run {
                    NotificationCenter.default.post(name: .ledgerDidChange, object: nil)
                    NotificationCenter.default.post(name: .bankLinkDidChange, object: nil, userInfo: ["bank": bank.rawValue])
                }
            },
            deleteRemote: { sessionID in
                if let remoteClient {
                    try? await remoteClient.deleteSession(id: sessionID)
                }
            }
        )
    }

    // MARK: - Interno

    private func fail(_ bank: BankID, _ message: String) {
        run(flow.handle(.failed(bank, message)))
    }

    private func run(_ actions: [ConnectAction]) {
        for action in actions {
            switch action {
            case .cancelWebSession: closeWebSession()
            case .deletePending: deletePending()
            case .processCallback, .openWeb, .restart: break
            }
        }
    }

    private func loadPending() -> PendingAuth? {
        #if DEBUG
        if DemoMode.isActive { return nil }
        #endif
        return (try? KeychainVault.codable(PendingAuth.self, for: .pendingAuth)) ?? nil
    }

    private func pendingCheck() -> PendingCheck {
        guard let pending = loadPending() else { return .none }
        return pending.isExpired(now: Date()) ? .expired(pending.bank) : .valid(pending.bank)
    }

    private func deletePending() {
        #if DEBUG
        if DemoMode.isActive { return }
        #endif
        try? KeychainVault.delete(.pendingAuth)
    }

    /// Cierra la hoja web (si la hay) sin que su aviso de cierre cuente como cancelación de la persona.
    private func closeWebSession() {
        webToken = nil
        webSession?.cancel()
        webSession = nil
    }

    private func openWeb(_ url: URL, bank: BankID) {
        closeWebSession()
        let token = UUID()
        webToken = token
        let session = ASWebAuthenticationSession(
            url: url, callbackURLScheme: BankingConstants.callbackScheme
        ) { [weak self] callbackURL, _ in
            Task { @MainActor in
                guard let self else { return }
                if let callbackURL {
                    await self.handle(url: callbackURL, fromWebSession: true)
                } else if self.webToken == token {
                    // Cerrada por la persona (la app, al cerrarla, anula antes el `webToken`).
                    self.webToken = nil
                    self.webSession = nil
                    self.run(self.flow.handle(.webDismissedByUser))
                }
            }
        }
        session.prefersEphemeralWebBrowserSession = true
        session.presentationContextProvider = anchorProvider
        webSession = session
        if session.start() {
            flow.handle(.webOpened(bank))
        } else {
            closeWebSession()
            fail(bank, ConnectMessage.tooSlow)
        }
    }

    /// 32 bytes del generador seguro del sistema, en base64 de URL.
    private static func randomState() -> String? {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        return base64URL(Data(bytes))
    }
}

/// La hoja web se ancla a la ventana principal.
private final class WebAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
            return windows.first { $0.isKeyWindow } ?? windows.first ?? ASPresentationAnchor()
        }
    }
}
