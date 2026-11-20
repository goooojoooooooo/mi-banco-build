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
    private var cachedASPSPs: [EBASPSP]?

    // La dirección del banco y la hoja web viven solo en memoria.
    @ObservationIgnored private var authURL: URL?
    @ObservationIgnored private var requestedUntil: Date?
    @ObservationIgnored private var webSession: ASWebAuthenticationSession?
    @ObservationIgnored private var webToken: UUID?
    @ObservationIgnored private let anchorProvider = WebAnchorProvider()
    /// Cambia con cada intento: un intento viejo que despierta tras un `await` se retira.
    @ObservationIgnored private var attempt = UUID()

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
    }

    // MARK: - Conectar

    func connect(_ bank: BankID, aspsp: EBASPSP? = nil) async {
        guard !isActive else { return }
        flow.handle(.start(bank))
        let mine = UUID()
        attempt = mine
        authURL = nil
        requestedUntil = nil

        let client: EnableBankingClient
        do { client = try BankingCredentials.client() } catch {
            fail(bank, ConnectMessage.tooSlow)
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
            fail(bank, ConnectMessage.tooSlow)
            return
        }
        let until = consentValidUntil(for: chosen, now: Date())
        let pending = PendingAuth(
            state: state, bank: bank, aspspName: chosen.name, aspspCountry: chosen.country, startedAt: Date())
        do { try KeychainVault.setCodable(pending, for: .pendingAuth) } catch {
            fail(bank, ConnectMessage.tooSlow)
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

    /// Cancelación explícita: cierra la hoja web y deja el trámite en `needsResume`.
    func cancelWebSession() {
        run(flow.handle(.cancel))
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

    func handle(url: URL) async {
        // Solo `mibanco://cb`: lo demás se ignora sin ruido.
        guard isBankCallbackURL(url) else { return }

        // Todo lo siguiente, hasta el primer `await`, es síncrono: la primera llamada consume el intento
        // (lo borra del Llavero) y una segunda no encuentra nada.
        let pending = loadPending()
        let check: PendingCheck
        if let pending {
            check = pending.isExpired(now: Date()) ? .expired(pending.bank) : .valid(pending.bank)
        } else {
            check = .none
        }
        let actions = flow.handle(.callback(check))

        var bankToProcess: BankID?
        for action in actions {
            if case .processCallback(let bank) = action { bankToProcess = bank } else { run([action]) }
        }
        guard let bank = bankToProcess, let pending else { return }

        let result = parseAuthCallback(url, expectedState: pending.state)
        // Consumir: pase lo que pase, este intento no vuelve a servir.
        do { try KeychainVault.delete(.pendingAuth) } catch {
            fail(bank, ConnectMessage.tooSlow)
            return
        }
        guard case .code(let code) = result else {
            fail(bank, connectMessage(for: result) ?? ConnectMessage.foreignLink)
            return
        }
        await finish(bank: bank, code: code, pending: pending)
    }

    private func finish(bank: BankID, code: String, pending: PendingAuth) async {
        let client: EnableBankingClient
        do { client = try BankingCredentials.client() } catch {
            fail(bank, ConnectMessage.tooSlow)
            return
        }
        let session: EBSession
        do { session = try await client.createSession(code: code) } catch {
            fail(bank, connectMessage(for: error))
            return
        }
        let accounts = selectAccounts(session.accounts)
        guard !accounts.isEmpty else {
            try? await client.deleteSession(id: session.sessionID)
            fail(bank, ConnectMessage.noEuroAccount(bank))
            return
        }
        let fallback = EBASPSP(name: pending.aspspName, country: pending.aspspCountry)
        let now = Date()
        let until = session.validUntil ?? requestedUntil ?? consentValidUntil(for: fallback, now: now)
        let stored = StoredSession(
            sessionID: session.sessionID, accountUIDs: accounts.map(\.uid), validUntil: until,
            aspspName: pending.aspspName, aspspCountry: pending.aspspCountry)
        do {
            try KeychainVault.setCodable(stored, for: KeychainVault.session(for: bank))
            _ = try SharedStore.make().update { ledger in
                let info = ledger.state.links[bank]?.renewed(consentValidUntil: until, at: now)
                    ?? BankLinkInfo(connectedAt: now, consentValidUntil: until)
                ledger.setLink(bank, info)
            }
        } catch {
            try? await client.deleteSession(id: session.sessionID)
            fail(bank, ConnectMessage.tooSlow)
            return
        }
        authURL = nil
        requestedUntil = nil
        flow.handle(.succeeded(bank))
        NotificationCenter.default.post(name: .ledgerDidChange, object: nil)
        NotificationCenter.default.post(name: .bankLinkDidChange, object: nil, userInfo: ["bank": bank.rawValue])
    }

    // MARK: - Desconectar

    func disconnect(_ bank: BankID) async {
        if flow.phase.isActive, phaseBank == bank { run(flow.handle(.cancel)) }
        if phaseBank == bank { run(flow.handle(.reset)) }
        if let session = try? KeychainVault.codable(StoredSession.self, for: KeychainVault.session(for: bank)),
           let client = try? BankingCredentials.client() {
            try? await client.deleteSession(id: session.sessionID)
        }
        try? KeychainVault.delete(KeychainVault.session(for: bank))
        _ = try? SharedStore.make().update { ledger in
            ledger.setLink(bank, nil)
            if let balance = ledger.state.balances[bank], balance.origin == .bank {
                ledger.adoptBalance(bank, cents: balance.cents, at: balance.setAt, origin: .manual)
            }
        }
        NotificationCenter.default.post(name: .ledgerDidChange, object: nil)
        NotificationCenter.default.post(name: .bankLinkDidChange, object: nil, userInfo: ["bank": bank.rawValue])
    }

    // MARK: - Interno

    private var phaseBank: BankID? {
        switch flow.phase {
        case .idle: nil
        case .opening(let b), .waitingForBank(let b), .finishing(let b), .connected(let b), .needsResume(let b),
             .failed(let b, _), .chooseASPSP(let b, _):
            b
        }
    }

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
        (try? KeychainVault.codable(PendingAuth.self, for: .pendingAuth)) ?? nil
    }

    private func pendingCheck() -> PendingCheck {
        guard let pending = loadPending() else { return .none }
        return pending.isExpired(now: Date()) ? .expired(pending.bank) : .valid(pending.bank)
    }

    private func deletePending() {
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
                    await self.handle(url: callbackURL)
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
