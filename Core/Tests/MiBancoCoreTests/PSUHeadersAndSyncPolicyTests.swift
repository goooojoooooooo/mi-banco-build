import Foundation
import Testing
@testable import MiBancoCore

private let madrid: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Madrid")!
    return c
}()

private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
    madrid.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
}

private let baseNow = at(2026, 11, 20, 12)

private func sampleLink(validUntil: Date = at(2027, 5, 19)) -> BankLinkInfo {
    BankLinkInfo(connectedAt: at(2026, 11, 1), consentValidUntil: validUntil)
}

private struct TestSigner: JWTSigner {
    func signRS256(_ message: Data) throws -> Data { Data([1, 2, 3]) }
}

private actor RecordingTransport: HTTPTransport {
    private var replies: [HTTPResponse]
    private(set) var requests: [HTTPRequest] = []

    init(_ replies: [HTTPResponse]) {
        self.replies = replies
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard !replies.isEmpty else { return HTTPResponse(status: 500, body: Data()) }
        return replies.removeFirst()
    }
}

private func makeClient(_ transport: RecordingTransport) -> EnableBankingClient {
    EnableBankingClient(
        transport: transport,
        signer: TestSigner(),
        appID: "00000000-0000-4000-8000-000000000001",
        now: { Date(timeIntervalSince1970: 1_795_172_400) }
    )
}

// MARK: - Regla pura psuHeaders

@Suite struct PSUHeadersRuleTests {
    private let localAvailable: [String: String] = [
        "Psu-User-Agent": "Onyx/0.3.0 (iOS 18.2)",
        "Psu-Accept-language": "es-ES",
    ]

    @Test func backgroundAlwaysReturnsNil() {
        #expect(psuHeaders(for: .background, required: nil, available: localAvailable) == nil)
        #expect(psuHeaders(for: .background, required: [], available: localAvailable) == nil)
        #expect(psuHeaders(for: .background, required: ["Psu-User-Agent"], available: localAvailable) == nil)
    }

    @Test func appOpenAndManualWithNoRequiredReturnAvailable() {
        for trigger in [SyncTrigger.appOpen, .manual, .afterConnect] {
            #expect(psuHeaders(for: trigger, required: nil, available: localAvailable) == localAvailable)
            #expect(psuHeaders(for: trigger, required: [], available: localAvailable) == localAvailable)
        }
    }

    @Test func requiredHeadersMatchedCaseInsensitivelyAndCanonicalized() {
        let available = [
            "psu-user-agent": "Onyx/0.3.0 (iOS 18.2)",
            "PSU-ACCEPT-LANGUAGE": "es-ES",
        ]
        let required = ["PSU-USER-AGENT", "psu-accept-language"]
        let result = psuHeaders(for: .appOpen, required: required, available: available)
        #expect(result == [
            "Psu-User-Agent": "Onyx/0.3.0 (iOS 18.2)",
            "Psu-Accept-language": "es-ES",
        ])
    }

    @Test func missingRequiredIPHeaderReturnsNilAllOrNothing() {
        #expect(psuHeaders(for: .appOpen, required: ["Psu-Ip-Address"], available: localAvailable) == nil)
        #expect(psuHeaders(for: .manual, required: ["psu-ip-address"], available: localAvailable) == nil)
        #expect(psuHeaders(for: .appOpen, required: ["Psu-User-Agent", "Psu-Ip-Address"], available: localAvailable) == nil)
    }

    @Test func unknownRequiredHeaderOutsideAllowlistReturnsNil() {
        let available = localAvailable.merging(["Psu-Device-Id": "abc"]) { a, _ in a }
        #expect(psuHeaders(for: .appOpen, required: ["Psu-Device-Id"], available: available) == nil)
    }

    @Test func emptyAvailableOrOnlyDisallowedHeadersReturnsNil() {
        #expect(psuHeaders(for: .appOpen, required: nil, available: [:]) == nil)
        #expect(psuHeaders(for: .manual, required: [], available: [:]) == nil)
        let disallowed = [
            "Authorization": "Bearer fake",
            "Cookie": "a=b",
            "X-Custom": "1",
        ]
        #expect(psuHeaders(for: .appOpen, required: nil, available: disallowed) == nil)
    }

    @Test func filtersDisallowedNamesEmptyValuesAndControlCharacters() {
        let mixed: [String: String] = [
            "Psu-User-Agent": "  Onyx/0.3.0 (iOS 18.2)  ",
            "Psu-Accept-language": "es-ES\r\nX-Injected: 1",
            "Psu-Referer": "",
            "Psu-Accept": "   ",
            "Psu-Accept-Charset": "utf-8\n",
            "Psu-Accept-Encoding": "gzip\0",
            "Psu-Geo-Location": "GEO:1\t2",
            "Authorization": "Bearer steal",
            "X-Other": "ignored",
        ]
        let result = psuHeaders(for: .appOpen, required: nil, available: mixed)
        #expect(result == ["Psu-User-Agent": "Onyx/0.3.0 (iOS 18.2)"])
        // Si la cabecera requerida traía CR/LF o estaba vacía, tampoco sirve y devuelve nil.
        #expect(psuHeaders(for: .appOpen, required: ["Psu-Accept-language"], available: mixed) == nil)
        #expect(psuHeaders(for: .appOpen, required: ["Psu-Referer"], available: mixed) == nil)
    }

    @Test func acceptsAllEightOfficialEnableBankingPSUHeadersWithCanonicalCasing() {
        let allEight: [String: String] = [
            "psu-ip-address": "198.51.100.1",
            "psu-user-agent": "Onyx/0.3.0 (iOS 18.2)",
            "psu-referer": "https://example.com",
            "psu-accept": "application/json",
            "psu-accept-charset": "utf-8",
            "psu-accept-encoding": "gzip",
            "psu-accept-language": "es-ES",
            "psu-geo-location": "GEO:40.4168,-3.7038",
        ]
        let result = psuHeaders(for: .manual, required: Array(allEight.keys), available: allEight)
        #expect(result == [
            "Psu-Ip-Address": "198.51.100.1",
            "Psu-User-Agent": "Onyx/0.3.0 (iOS 18.2)",
            "Psu-Referer": "https://example.com",
            "Psu-Accept": "application/json",
            "Psu-Accept-Charset": "utf-8",
            "Psu-Accept-Encoding": "gzip",
            "Psu-Accept-language": "es-ES",
            "Psu-Geo-Location": "GEO:40.4168,-3.7038",
        ])
    }

    @Test func buildLocalPSUHeadersNeverIncludesIPAndSanitizesInputs() {
        let headers = buildLocalPSUHeaders(
            appName: "Onyx",
            appVersion: "0.3.0",
            osVersion: "18.2",
            preferredLanguage: "es_ES"
        )
        #expect(headers == [
            "Psu-User-Agent": "Onyx/0.3.0 (iOS 18.2)",
            "Psu-Accept-language": "es-ES",
        ])
        #expect(headers["Psu-Ip-Address"] == nil)

        let noLang = buildLocalPSUHeaders(
            appName: "Onyx",
            appVersion: "0.3.0",
            osVersion: "18.2",
            preferredLanguage: "es\r\nX-Evil: 1"
        )
        #expect(noLang == ["Psu-User-Agent": "Onyx/0.3.0 (iOS 18.2)"])
    }
}

// MARK: - Cupo separado en SyncPolicy y espera 429

@Suite struct SyncPolicyPSUQuotaTests {
    @Test func userPresentAppOpenAndManualHaveNoDailyQuotaAndAllowManyFetchesSpaced120s() {
        var l = sampleLink()
        l.historyLoaded = true
        var t = at(2026, 11, 20, 8, 0, 0)
        // 10 consultas el mismo día separadas exactamente 120 s (muy por encima del cupo de 4/24 h).
        for step in 0..<10 {
            let trigger: SyncTrigger = step.isMultiple(of: 2) ? .appOpen : .manual
            let decision = SyncPolicy.decide(l, trigger: trigger, now: t, calendar: madrid, hasPSUHeaders: true)
            guard case .fetch = decision else {
                Issue.record("Debía consultar en la iteración \(step), dio \(decision)")
                return
            }
            l = l.recordingAttempt(at: t, countsTowardDailyBudget: false).recordingSuccess(at: t)
            t = t.addingTimeInterval(120)
        }
        // Ninguna consulta con usuario presente gastó el cupo diario de segundo plano.
        #expect(l.fetchLog.isEmpty)
    }

    @Test func userPresentEnforcesExact120SecondMinimumSpacing() {
        var l = sampleLink()
        l.historyLoaded = true
        l = l.recordingAttempt(at: baseNow, countsTowardDailyBudget: false).recordingSuccess(at: baseNow)

        for trigger in [SyncTrigger.appOpen, .manual] {
            #expect(SyncPolicy.decide(l, trigger: trigger, now: baseNow.addingTimeInterval(60), calendar: madrid, hasPSUHeaders: true)
                == .skip(.fresh))
            #expect(SyncPolicy.decide(l, trigger: trigger, now: baseNow.addingTimeInterval(119), calendar: madrid, hasPSUHeaders: true)
                == .skip(.fresh))
            if case .fetch = SyncPolicy.decide(l, trigger: trigger, now: baseNow.addingTimeInterval(120), calendar: madrid, hasPSUHeaders: true) {
                // OK
            } else {
                Issue.record("A los 120 s exactos debía permitir consultar con \(trigger)")
            }
        }
    }

    @Test func userPresentBypassesExhaustedBackgroundDailyBudget() {
        var l = sampleLink()
        for h in [8, 9, 10, 11] { l = l.recordingAttempt(at: at(2026, 11, 20, h)) }
        l.lastSuccessAt = at(2026, 11, 20, 11)
        l.historyLoaded = true

        // Sin cabeceras PSU (o segundo plano): cupo de 4/24 h agotado.
        let budgetSkip = SyncDecision.skip(.budgetUsed(nextAt: at(2026, 11, 21, 8)))
        #expect(SyncPolicy.decide(l, trigger: .background, now: baseNow, calendar: madrid, hasPSUHeaders: false) == budgetSkip)
        #expect(SyncPolicy.decide(l, trigger: .background, now: baseNow, calendar: madrid, hasPSUHeaders: true) == budgetSkip)
        #expect(SyncPolicy.decide(l, trigger: .appOpen, now: baseNow, calendar: madrid, hasPSUHeaders: false) == budgetSkip)
        #expect(SyncPolicy.decide(l, trigger: .manual, now: baseNow, calendar: madrid, hasPSUHeaders: false) == budgetSkip)

        // Con cabeceras PSU y >= 120 s desde la última consulta: permitido.
        if case .fetch = SyncPolicy.decide(l, trigger: .appOpen, now: baseNow, calendar: madrid, hasPSUHeaders: true) {
            // OK
        } else {
            Issue.record(".appOpen con cabeceras PSU debía consultar aunque el cupo de segundo plano esté agotado")
        }
        if case .fetch = SyncPolicy.decide(l, trigger: .manual, now: baseNow, calendar: madrid, hasPSUHeaders: true) {
            // OK
        } else {
            Issue.record(".manual con cabeceras PSU debía consultar aunque el cupo de segundo plano esté agotado")
        }
    }

    @Test func backgroundAlwaysKeepsFourPerDayQuotaEvenIfHasPSUHeadersIsTrue() {
        var l = sampleLink()
        l.lastSuccessAt = at(2026, 11, 20, 11, 50)
        l.historyLoaded = true
        // Con solo 10 min desde el último éxito, `.background` sigue pidiendo 3 h (autoSpacing), nunca 120 s.
        #expect(SyncPolicy.decide(l, trigger: .background, now: baseNow, calendar: madrid, hasPSUHeaders: true) == .skip(.fresh))
    }

    @Test func rateLimit429BlocksUserPresentAndBackgroundForSixHours() {
        let problem = classifyEnableBankingError(
            status: 429,
            body: Data(#"{"error":"ASPSP_RATE_LIMIT_EXCEEDED"}"#.utf8)
        )
        #expect(problem == .rateLimited)
        let l = sampleLink().recordingFailure(problem, at: baseNow)
        let until = baseNow.addingTimeInterval(SyncPolicy.backoff)
        #expect(SyncPolicy.backoff == 21_600)
        #expect(l.backoffUntil == until)

        // Bloquea tanto con usuario presente (PSU) como sin PSU y en segundo plano durante las 6 h.
        let fiveHoursLater = baseNow.addingTimeInterval(5 * 3600 + 59 * 60 + 59)
        for trigger in [SyncTrigger.appOpen, .manual, .background, .afterConnect] {
            for psu in [false, true] {
                #expect(
                    SyncPolicy.decide(l, trigger: trigger, now: fiveHoursLater, calendar: madrid, hasPSUHeaders: psu)
                        == .skip(.waiting(until: until))
                )
            }
        }
        // A las 6 h exactas vuelve a dejar consultar.
        if case .fetch = SyncPolicy.decide(l, trigger: .appOpen, now: until, calendar: madrid, hasPSUHeaders: true) {
            // OK
        } else {
            Issue.record("A las 6 h exactas debía levantar el backoff")
        }
        if case .fetch = SyncPolicy.decide(l, trigger: .background, now: until, calendar: madrid, hasPSUHeaders: false) {
            // OK
        } else {
            Issue.record("A las 6 h exactas debía levantar el backoff en segundo plano")
        }
    }

    @Test func banksToFetchRespectsPerBankPSUAvailability() {
        var rev = sampleLink()
        var ima = sampleLink()
        for h in [8, 9, 10, 11] {
            rev = rev.recordingAttempt(at: at(2026, 11, 20, h))
            ima = ima.recordingAttempt(at: at(2026, 11, 20, h))
        }
        // Revolut tiene cabeceras PSU; imagin exige IP (hasPSUHeaders = false) y tiene el cupo diario lleno.
        let plans = banksToFetch(
            links: [.rev: rev, .ima: ima],
            trigger: .appOpen,
            now: baseNow,
            calendar: madrid,
            hasPSUHeaders: [.rev: true, .ima: false]
        )
        #expect(plans.map(\.bank) == [.rev])
    }

    @Test func psuHeaderRejectionDetectorMatches422CodesOnly() {
        #expect(isPSUHeaderRejection(BankingClientError.api(.unknown, code: "PSU_HEADER_NOT_PROVIDED")))
        #expect(isPSUHeaderRejection(BankingClientError.api(.unknown, code: "PSU_HEADER_INVALID")))
        #expect(!isPSUHeaderRejection(BankingClientError.api(.rateLimited, code: "ASPSP_RATE_LIMIT_EXCEEDED")))
        #expect(!isPSUHeaderRejection(BankingClientError.api(.consentExpired, code: "EXPIRED_SESSION")))
        #expect(!isPSUHeaderRejection(BankingClientError.api(.unknown, code: nil)))
        #expect(!isPSUHeaderRejection(BankingClientError.offline))
    }
}

// MARK: - EnableBankingClient cabeceras PSU

@Suite struct EnableBankingClientPSUHeaderTests {
    @Test func balancesSendsPSUHeadersWhenProvidedAndNeverOverwritesProtectedHeaders() async throws {
        let transport = RecordingTransport([HTTPResponse(status: 200, body: Data(#"{"balances":[]}"#.utf8))])
        let client = makeClient(transport)
        _ = try await client.balances(
            accountUID: "u-1",
            psuHeaders: [
                "Psu-User-Agent": "Onyx/0.3.0 (iOS 18.2)",
                "psu-accept-language": "es-ES",
                "Authorization": "Bearer EVIL",
                "Accept": "text/plain",
                "Content-Type": "text/plain",
                "X-Other": "ignored",
                "Psu-Referer": "bad\r\nHeader: x",
            ]
        )
        let request = try #require(await transport.requests.first)
        #expect(request.headers["Psu-User-Agent"] == "Onyx/0.3.0 (iOS 18.2)")
        #expect(request.headers["Psu-Accept-language"] == "es-ES")
        #expect(request.headers["Authorization"]?.hasPrefix("Bearer ") == true)
        #expect(request.headers["Authorization"] != "Bearer EVIL")
        #expect(request.headers["Accept"] == "application/json")
        #expect(request.headers["Content-Type"] == "application/json")
        #expect(request.headers["X-Other"] == nil)
        #expect(request.headers["Psu-Referer"] == nil)
        // La descripción redactada nunca expone cabeceras PSU.
        #expect(!String(describing: request).contains("Onyx/0.3.0"))
    }

    @Test func transactionsSendsPSUHeadersOnEveryPage() async throws {
        let page1 = Data(#"{"transactions":[],"continuation_key":"p2"}"#.utf8)
        let page2 = Data(#"{"transactions":[],"continuation_key":null}"#.utf8)
        let transport = RecordingTransport([
            HTTPResponse(status: 200, body: page1),
            HTTPResponse(status: 200, body: page2),
        ])
        let psu = ["Psu-User-Agent": "Onyx/0.3.0 (iOS 18.2)", "Psu-Accept-language": "es-ES"]
        let all = try await makeClient(transport).transactions(
            accountUID: "u-1",
            dateFrom: "2026-11-10",
            strategy: .standard,
            psuHeaders: psu
        )
        #expect(all.isEmpty)
        let requests = await transport.requests
        #expect(requests.count == 2)
        for req in requests {
            #expect(req.headers["Psu-User-Agent"] == "Onyx/0.3.0 (iOS 18.2)")
            #expect(req.headers["Psu-Accept-language"] == "es-ES")
        }
    }

    @Test func nilPSUHeadersSendsNoPSUHeadersOnBalancesTransactionsAspspsAndSessions() async throws {
        let transport = RecordingTransport([
            HTTPResponse(status: 200, body: Data(#"{"balances":[]}"#.utf8)),
            HTTPResponse(status: 200, body: Data(#"{"transactions":[]}"#.utf8)),
            HTTPResponse(status: 200, body: Data(#"{"aspsps":[]}"#.utf8)),
            HTTPResponse(status: 200, body: Data(#"{"session_id":"s-1","accounts":[]}"#.utf8)),
        ])
        let client = makeClient(transport)
        _ = try await client.balances(accountUID: "u-1", psuHeaders: nil)
        _ = try await client.fetchTransactions(accountUID: "u-1", dateFrom: "2026-11-10", strategy: .standard, psuHeaders: nil)
        _ = try await client.aspsps(country: "ES")
        _ = try await client.createSession(code: "code-1")
        let requests = await transport.requests
        #expect(requests.count == 4)
        for req in requests {
            #expect(!req.headers.keys.contains { $0.lowercased().hasPrefix("psu-") })
        }
    }
}

// MARK: - StoredSession, ASPSP y diagnóstico de cabeceras

@Suite struct StoredSessionAndDiagnosticTests {
    @Test func storedSessionDecodesLegacyJSONWithoutRequiredPSUHeadersAndOmitsNilOnEncode() throws {
        let legacyJSON = #"{"sessionID":"s-1","accountUIDs":["u-1"],"validUntil":"2027-05-19T10:00:00Z","aspspName":"Revolut","aspspCountry":"ES"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StoredSession.self, from: Data(legacyJSON.utf8))
        #expect(decoded.sessionID == "s-1")
        #expect(decoded.requiredPSUHeaders == nil)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encodedNil = String(decoding: try encoder.encode(decoded), as: UTF8.self)
        #expect(!encodedNil.contains("requiredPSUHeaders"))
    }

    @Test func storedSessionDistinguishesEmptyCheckedFromNilAndRoundTripsHeaderNames() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let checkedEmpty = StoredSession(
            sessionID: "s-1", accountUIDs: ["u-1"], validUntil: baseNow,
            aspspName: "Revolut", aspspCountry: "ES", requiredPSUHeaders: []
        )
        let backEmpty = try decoder.decode(StoredSession.self, from: try encoder.encode(checkedEmpty))
        #expect(backEmpty.requiredPSUHeaders == [])

        let withIP = StoredSession(
            sessionID: "s-2", accountUIDs: ["u-2"], validUntil: baseNow,
            aspspName: "imaginBank", aspspCountry: "ES", requiredPSUHeaders: ["Psu-Ip-Address"]
        )
        let backIP = try decoder.decode(StoredSession.self, from: try encoder.encode(withIP))
        #expect(backIP.requiredPSUHeaders == ["Psu-Ip-Address"])
        // La descripción redactada sigue sin exponer sesión ni cuentas.
        #expect(!String(describing: withIP).contains("s-2"))
        #expect(!String(describing: withIP).contains("u-2"))
    }

    @Test func pendingAuthBackwardCompatibleWithRequiredPSUHeaders() throws {
        let legacy = #"{"state":"st","bank":"rev","aspspName":"Revolut","aspspCountry":"ES","startedAt":"2026-11-20T11:00:00Z"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PendingAuth.self, from: Data(legacy.utf8))
        #expect(decoded.requiredPSUHeaders == nil)

        let withHeaders = PendingAuth(
            state: "st", bank: .rev, aspspName: "Revolut", aspspCountry: "ES",
            startedAt: baseNow, requiredPSUHeaders: ["Psu-User-Agent"]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let back = try decoder.decode(PendingAuth.self, from: try encoder.encode(withHeaders))
        #expect(back.requiredPSUHeaders == ["Psu-User-Agent"])
    }

    @Test func findASPSPMatchesByExactNameAndCountryBeforeFallback() {
        let list = [
            EBASPSP(name: "Revolut", country: "LT", requiredPSUHeaders: ["Psu-Ip-Address"]),
            EBASPSP(name: "Revolut", country: "ES", requiredPSUHeaders: []),
            EBASPSP(name: "imaginBank", country: "ES", requiredPSUHeaders: ["Psu-Ip-Address"]),
        ]
        #expect(findASPSP(name: "revolut", country: "es", bank: .rev, in: list)?.requiredPSUHeaders == [])
        #expect(findASPSP(name: "imaginBank", country: "ES", bank: .ima, in: list)?.requiredPSUHeaders == ["Psu-Ip-Address"])
        #expect(findASPSP(name: "Nombre Antiguo", country: "ES", bank: .ima, in: list)?.name == "imaginBank")
    }

    @Test func psuHeadersDiagnosticFormatsOnlySafeHeaderNames() {
        #expect(psuHeadersDiagnosticValue(nil) == "pendiente de comprobar")
        #expect(psuHeadersDiagnosticValue([]) == "ninguna")
        #expect(psuHeadersDiagnosticValue(["psu-ip-address"]) == "Psu-Ip-Address")
        #expect(psuHeadersDiagnosticValue(["psu-ip-address", "psu-user-agent"]) == "Psu-Ip-Address, Psu-User-Agent")
        // Filtra valores con saltos de línea o espacios (solo nombres de cabecera HTTP).
        #expect(psuHeadersDiagnosticValue(["Psu-Ip-Address", "malo\r\nvalor"]) == "Psu-Ip-Address")

        #expect(psuHeadersDiagnosticsLine(connectedBanks: [], requiredByBank: [:]) == nil)
        let line = psuHeadersDiagnosticsLine(
            connectedBanks: [.rev, .ima],
            requiredByBank: [.rev: [], .ima: ["psu-ip-address"]]
        )
        #expect(line == "Cabeceras PSU: Revolut ninguna · imagin Psu-Ip-Address")

        let pending = psuHeadersDiagnosticsLine(
            connectedBanks: [.rev],
            requiredByBank: [:]
        )
        #expect(pending == "Cabeceras PSU: Revolut pendiente de comprobar")
    }
}
