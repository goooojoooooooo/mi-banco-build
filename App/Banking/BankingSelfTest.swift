#if DEBUG
import Foundation
import MiBancoCore
import Security
import SwiftUI

/// Autoprueba del simulador: prueba que la firma RS256 se produce y se verifica, y que el Llavero guarda y borra.
/// Se abre con el argumento de lanzamiento `-MiBancoSelfTest`. Las claves se generan en ejecución.
enum BankingSelfTest {
    static let testService = "com.mibanco.banking.selftest"

    static func run(onStep: (@MainActor @Sendable (String) -> Void)? = nil) async -> String {
        func step(_ name: String) async {
            if let onStep { await onStep(name) }
        }
        await step("1-clave")
        // 1. Clave RSA-2048 en memoria (no permanente) y su PKCS#1.
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048,
            kSecAttrIsPermanent: false,
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey),
              let pkcs1 = SecKeyCopyExternalRepresentation(privateKey, &error) as Data?
        else { return failure("clave") }

        // 2. PKCS#8 y PEM, con la misma estructura DER que el test de Core; el PEM se monta por concatenación.
        let pkcs8 = der(0x30, [0x02, 0x01, 0x00] + der(0x30, rsaOID + [0x05, 0x00]) + der(0x04, [UInt8](pkcs1)))
        let b64 = Data(pkcs8).base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        let label = "PRIVATE KEY"
        let pem = "-----BEGIN " + label + "-----\n" + b64 + "\n-----END " + label + "-----\n"

        // 3. El PEM vuelve a los mismos bytes.
        guard let back = try? rsaPKCS1DER(fromPEM: pem), back == pkcs1 else { return failure("pem") }

        // 4. JWT firmado y verificado con la clave pública.
        guard let signer = try? RSASigner(pkcs1DER: back) else { return failure("firmante") }
        let appID = "00000000-0000-4000-8000-000000000001"
        let now = Date()
        guard let jwt = try? enableBankingJWT(appID: appID, now: now, signer: signer) else { return failure("firma") }
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return failure("jwt") }
        let input = String(parts[0]) + "." + String(parts[1])
        guard input == enableBankingJWTSigningInput(appID: appID, now: now, lifetime: BankingConstants.jwtLifetime),
              let signature = base64URLDecode(String(parts[2])) else { return failure("jwt") }
        let signedInput = Data(input.utf8)
        guard SecKeyVerifySignature(
            publicKey, .rsaSignatureMessagePKCS1v15SHA256, signedInput as CFData, signature as CFData, &error)
        else { return failure("verificacion") }
        // Una firma sobre otro texto no debe verificar.
        let other = Data("otro".utf8)
        if SecKeyVerifySignature(
            publicKey, .rsaSignatureMessagePKCS1v15SHA256, other as CFData, signature as CFData, nil) {
            return failure("verificacion")
        }

        // 5. Llavero con otro servicio: guardar, leer, actualizar (verificando kSecAttrAccessible, M-12), borrar.
        await step("5-llavero-M12")
        let secret = Data("valor-de-prueba".utf8)
        do {
            try KeychainVault.deleteAll(service: testService)

            // M-12: insertamos primero con accesibilidad distinta (WhenUnlocked) para demostrar que
            // `KeychainVault.set` actualiza de verdad `kSecAttrAccessible` en `SecItemUpdate`.
            let seedAdd: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: testService,
                kSecAttrAccount: KeychainVault.Item.appID.rawValue,
                kSecAttrSynchronizable: false,
                kSecValueData: secret,
                kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked,
            ]
            let seedStatus = SecItemAdd(seedAdd as CFDictionary, nil)
            guard seedStatus == errSecSuccess else {
                try? KeychainVault.deleteAll(service: testService)
                return failure("llavero (semilla M-12: \(seedStatus))")
            }
            guard genericPasswordAccessibility(for: .appID, service: testService)
                    == (kSecAttrAccessibleWhenUnlocked as String) else {
                try? KeychainVault.deleteAll(service: testService)
                return failure("llavero (accesibilidad inicial M-12)")
            }
            guard try KeychainVault.data(for: .appID, service: testService) == secret else {
                try? KeychainVault.deleteAll(service: testService)
                return failure("llavero (lectura distinta)")
            }
            try KeychainVault.set(Data("otro".utf8), for: .appID, service: testService)
            guard try KeychainVault.data(for: .appID, service: testService) == Data("otro".utf8) else {
                try? KeychainVault.deleteAll(service: testService)
                return failure("llavero (actualizacion distinta)")
            }
            guard genericPasswordAccessibility(for: .appID, service: testService)
                    == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String) else {
                try? KeychainVault.deleteAll(service: testService)
                return failure("llavero (SecItemUpdate no actualizo kSecAttrAccessible)")
            }
            try KeychainVault.delete(.appID, service: testService)
            guard try KeychainVault.data(for: .appID, service: testService) == nil else {
                return failure("llavero (borrado sin efecto)")
            }

            // 5b. Migración automática de clave privada heredada (generic password -> kSecClassKey) y firma directa.
            try KeychainVault.deleteAll(service: testService)
            try KeychainVault.set(back, for: .privateKey, service: testService)
            guard KeychainVault.hasPrivateKey(service: testService) else {
                try? KeychainVault.deleteAll(service: testService)
                return failure("llavero (clave heredada ausente)")
            }
            guard let migratedKey = try KeychainVault.loadPrivateKey(service: testService) else {
                try? KeychainVault.deleteAll(service: testService)
                return failure("llavero (migracion a kSecClassKey)")
            }
            // El elemento heredado debe desaparecer tras migrar a kSecClassKey.
            guard try KeychainVault.data(for: .privateKey, service: testService) == nil else {
                try? KeychainVault.deleteAll(service: testService)
                return failure("llavero (heredado sin borrar)")
            }
            let migratedSigner = RSASigner(key: migratedKey)
            guard let migratedJWT = try? enableBankingJWT(appID: appID, now: now, signer: migratedSigner),
                  verifyJWT(migratedJWT, publicKey: publicKey) else {
                try? KeychainVault.deleteAll(service: testService)
                return failure("verificacion (clave migrada)")
            }

            // 5c. Guardado directo de kSecClassKey, accesibilidad M-12, recarga y borrado completo.
            try KeychainVault.savePrivateKey(pkcs1DER: back, service: testService)
            guard privateKeyAccessibility(service: testService)
                    == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String) else {
                try? KeychainVault.deleteAll(service: testService)
                return failure("llavero (accesibilidad kSecClassKey)")
            }
            guard let preDeleteKey = try KeychainVault.loadPrivateKey(service: testService) else {
                try? KeychainVault.deleteAll(service: testService)
                return failure("llavero (recarga kSecClassKey)")
            }
            let preDeleteSigner = RSASigner(key: preDeleteKey)
            guard let reloadedJWT = try? enableBankingJWT(appID: appID, now: now, signer: preDeleteSigner),
                  verifyJWT(reloadedJWT, publicKey: publicKey) else {
                try? KeychainVault.deleteAll(service: testService)
                return failure("llavero (firma kSecClassKey)")
            }

            // 5d. M-1: «Olvidar clave y conexiones» — tras `deleteAll()`, la referencia `SecKey` retenida por el cliente
            // debe seguir firmando el JWT y enviando `DELETE /sessions/...` válido.
            await step("5d-M1-deleteAll")
            SelfTestURLProtocol.state.reset()
            let forgetTransport = URLSessionTransport(protocolClasses: [SelfTestURLProtocol.self])
            let preDeleteClient = EnableBankingClient(
                transport: forgetTransport,
                signer: preDeleteSigner,
                appID: appID,
                now: { now }
            )
            let deleteLocalError = ErrorBox()
            let deleteRemoteError = ErrorBox()
            await forgetEverythingPlan(
                readSessionIDs: { ["selftest-s1"] },
                deleteLocal: {
                    do {
                        try KeychainVault.deleteAll(service: testService)
                    } catch {
                        deleteLocalError.set(error)
                    }
                },
                unlinkLedger: {},
                deleteRemote: { sessionID in
                    do {
                        try await preDeleteClient.deleteSession(id: sessionID)
                    } catch {
                        deleteRemoteError.set(error)
                    }
                }
            )
            if let err = deleteLocalError.value { throw err }
            guard !KeychainVault.hasPrivateKey(service: testService) else {
                return failure("llavero (deleteAll no borro kSecClassKey)")
            }
            guard let postDeleteJWT = try? enableBankingJWT(appID: appID, now: now, signer: preDeleteSigner),
                  verifyJWT(postDeleteJWT, publicKey: publicKey) else {
                return failure("M-1 (firma tras deleteAll)")
            }
            if let err = deleteRemoteError.value {
                return failure("M-1 (deleteSession tras deleteAll: \(err))")
            }
            let deleteAuthHeaders = SelfTestURLProtocol.state.recordedDeleteSessionAuthHeaders
            guard deleteAuthHeaders.count == 1,
                  let auth = deleteAuthHeaders.first,
                  auth.hasPrefix("Bearer "),
                  verifyJWT(String(auth.dropFirst("Bearer ".count)), publicKey: publicKey) else {
                return failure("M-1 (cabecera DELETE remota)")
            }
        } catch {
            try? KeychainVault.deleteAll(service: testService)
            // El código del sistema (OSStatus) no es secreto y dice por qué falla el Llavero.
            if case KeychainError.status(let code) = error { return failure("llavero (\(code))") }
            return failure("llavero (\(error))")
        }

        // 6. I-3 + M-4: pruebas reales de `URLSessionTransport` (`NoRedirectDelegate` y tope de 10 MB / streaming).
        await step("6-transporte-I3")
        if let transportFailure = await verifyTransportPolicy(signer: signer, appID: appID, now: now, onStep: onStep) {
            return failure(transportFailure)
        }
        _ = URLSessionTransport()

        // 7. SEC-11: sin intento pendiente, una URL externa de vuelta bancaria se ignora sin lanzar flujo ni error.
        if let strayURL = URL(string: "\(BankingConstants.callbackScheme)://cb?code=fake&state=fake") {
            let connector = await MainActor.run { BankConnector.shared }
            let accepted = await MainActor.run { connector.shouldHandleExternalCallback(strayURL) }
            guard !accepted else { return failure("callback sin pendiente aceptado") }
            await connector.handle(url: strayURL)
            let phase = await MainActor.run { connector.phase }
            guard phase == .idle else { return failure("callback sin pendiente cambio fase") }
        }
        return "Autoprueba: OK"
    }

    private static func verifyTransportPolicy(
        signer: RSASigner,
        appID: String,
        now: Date,
        onStep: (@MainActor @Sendable (String) -> Void)?
    ) async -> String? {
        func step(_ name: String) async {
            if let onStep { await onStep(name) }
        }
        let redirectURL = URL(string: "https://selftest.example.com/redirect")!

        // 6a. Control: una URLSession SIN `NoRedirectDelegate` SÍ sigue el 302 hacia `/redirect-target`.
        await step("6a-control-302")
        SelfTestURLProtocol.state.reset()
        do {
            let controlConfig = URLSessionConfiguration.ephemeral
            controlConfig.protocolClasses = [SelfTestURLProtocol.self]
            let controlSession = URLSession(configuration: controlConfig)
            let (_, controlResponse) = try await controlSession.bytes(for: URLRequest(url: redirectURL))
            guard let controlHTTP = controlResponse as? HTTPURLResponse,
                  controlHTTP.statusCode == 200,
                  SelfTestURLProtocol.state.hitsOnRedirectTarget == 1 else {
                return "I-3 (control sin NoRedirectDelegate)"
            }
        } catch {
            return "I-3 (error en control 302)"
        }

        // 6b. `URLSessionTransport` CON `NoRedirectDelegate`: devuelve 302 y el destino recibe 0 peticiones.
        await step("6b-noref-302")
        SelfTestURLProtocol.state.reset()
        let defaultTransport = URLSessionTransport(protocolClasses: [SelfTestURLProtocol.self])
        do {
            let reply = try await defaultTransport.send(
                HTTPRequest(method: "GET", url: redirectURL, headers: ["Authorization": "Bearer secreto-selftest"])
            )
            guard reply.status == 302,
                  reply.body.isEmpty,
                  SelfTestURLProtocol.state.hitsOnRedirectTarget == 0 else {
                return "I-3 (NoRedirectDelegate siguio 302)"
            }
        } catch {
            return "I-3 (error en 302 con NoRedirectDelegate)"
        }

        // 6c. End-to-end `EnableBankingClient` + `URLSessionTransport` ante 302: rechaza y 0 peticiones al destino.
        SelfTestURLProtocol.state.reset()
        let client = EnableBankingClient(
            transport: defaultTransport, signer: signer, appID: appID, now: { now }
        )
        do {
            _ = try await client.balances(accountUID: "selftest-redirect")
            return "I-3 (cliente acepto 302)"
        } catch BankingClientError.api(.unknown, code: nil) {
            guard SelfTestURLProtocol.state.hitsOnRedirectTarget == 0 else {
                return "I-3 (cliente siguio destino 302)"
            }
        } catch {
            return "I-3 (error inesperado cliente 302)"
        }

        // 6d. Tope real de 10 MB por cabecera Content-Length (`10 MB + 1` bytes).
        await step("6d-tope-10MB")
        let headerTooLargeURL = URL(string: "https://selftest.example.com/too-large-header")!
        do {
            _ = try await defaultTransport.send(HTTPRequest(method: "GET", url: headerTooLargeURL))
            return "I-3 (tope 10 MB no rechazo cabecera)"
        } catch let error as URLError where error.code == .dataLengthExceedsMaximum {
            // OK
        } catch {
            return "I-3 (error inesperado tope 10 MB)"
        }

        // 6e. Corte real en streaming SIN Content-Length (límite exacto pasa; límite + 1 falla).
        let streamingTransport = URLSessionTransport(
            protocolClasses: [SelfTestURLProtocol.self],
            maxResponseBytes: 1_024
        )
        do {
            let exact = try await streamingTransport.send(
                HTTPRequest(method: "GET", url: URL(string: "https://selftest.example.com/stream-exact-1024")!)
            )
            guard exact.status == 200, exact.body.count == 1_024 else {
                return "I-3 (streaming limite exacto)"
            }
        } catch {
            return "I-3 (error en streaming limite exacto)"
        }
        do {
            _ = try await streamingTransport.send(
                HTTPRequest(method: "GET", url: URL(string: "https://selftest.example.com/stream-over-1024")!)
            )
            return "I-3 (streaming no corto en limite+1)"
        } catch let error as URLError where error.code == .dataLengthExceedsMaximum {
            // OK
        } catch {
            return "I-3 (error inesperado streaming)"
        }

        // 6f. M-4 end-to-end: respuesta demasiado grande en `EnableBankingClient` es `.badResponse`, no `.offline`.
        do {
            _ = try await client.balances(accountUID: "selftest-too-large")
            return "M-4 (cliente acepto >10 MB)"
        } catch BankingClientError.badResponse {
            // OK
        } catch {
            return "M-4 (mapeo >10 MB no fue badResponse)"
        }
        let streamingClient = EnableBankingClient(
            transport: streamingTransport, signer: signer, appID: appID, now: { now }
        )
        do {
            _ = try await streamingClient.balances(accountUID: "selftest-stream-over")
            return "M-4 (cliente acepto streaming excesivo)"
        } catch BankingClientError.badResponse {
            // OK
        } catch {
            return "M-4 (mapeo streaming no fue badResponse)"
        }

        // 6g. Respuesta 200 normal pasa intacta por `URLSessionTransport`.
        do {
            let ok = try await defaultTransport.send(
                HTTPRequest(method: "GET", url: URL(string: "https://selftest.example.com/ok")!)
            )
            guard ok.status == 200, ok.body == Data(#"{"balances":[]}"#.utf8) else {
                return "I-3 (respuesta 200 alterada)"
            }
        } catch {
            return "I-3 (error en respuesta 200)"
        }
        return nil
    }

    private static func verifyJWT(_ jwt: String, publicKey: SecKey) -> Bool {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let sig = base64URLDecode(String(parts[2])) else { return false }
        let input = Data((String(parts[0]) + "." + String(parts[1])).utf8)
        return SecKeyVerifySignature(
            publicKey, .rsaSignatureMessagePKCS1v15SHA256, input as CFData, sig as CFData, nil
        )
    }

    private static func genericPasswordAccessibility(for item: KeychainVault.Item, service: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: item.rawValue,
            kSecAttrSynchronizable: false,
            kSecReturnAttributes: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let attrs = result as? [String: Any] else { return nil }
        return attrs[kSecAttrAccessible as String] as? String
    }

    private static func privateKeyAccessibility(service: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrApplicationTag: Data("\(service).\(KeychainVault.Item.privateKey.rawValue)".utf8),
            kSecAttrSynchronizable: false,
            kSecReturnAttributes: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let attrs = result as? [String: Any] else { return nil }
        return attrs[kSecAttrAccessible as String] as? String
    }

    private static func failure(_ step: String) -> String { "Autoprueba: falla en \(step)" }

    private static let rsaOID: [UInt8] = [0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01]

    private static func der(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
        let n = content.count
        if n < 128 { return [tag, UInt8(n)] + content }
        if n < 256 { return [tag, 0x81, UInt8(n)] + content }
        if n < 65_536 { return [tag, 0x82, UInt8(n >> 8), UInt8(n & 0xff)] + content }
        return [tag, 0x83, UInt8(n >> 16), UInt8((n >> 8) & 0xff), UInt8(n & 0xff)] + content
    }

    private static func base64URLDecode(_ text: String) -> Data? {
        var s = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }

    private final class ErrorBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Error?

        func set(_ error: Error) {
            lock.lock()
            defer { lock.unlock() }
            stored = error
        }

        var value: Error? {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
    }
}

/// `URLProtocol` controlado solo en DEBUG para ejercitar de verdad `NoRedirectDelegate`, el tope de 10 MB,
/// el corte en streaming sin `Content-Length` y el `DELETE /sessions/...` tras `deleteAll()` (I-3, M-1, M-4).
private final class SelfTestURLProtocol: URLProtocol {
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var redirectTargetHits = 0
        private var deleteSessionAuthHeaders: [String] = []

        func reset() {
            lock.lock()
            defer { lock.unlock() }
            redirectTargetHits = 0
            deleteSessionAuthHeaders = []
        }

        func recordRedirectTargetHit() {
            lock.lock()
            defer { lock.unlock() }
            redirectTargetHits += 1
        }

        var hitsOnRedirectTarget: Int {
            lock.lock()
            defer { lock.unlock() }
            return redirectTargetHits
        }

        func recordDeleteSessionAuth(_ header: String?) {
            lock.lock()
            defer { lock.unlock() }
            if let header { deleteSessionAuthHeaders.append(header) }
        }

        var recordedDeleteSessionAuthHeaders: [String] {
            lock.lock()
            defer { lock.unlock() }
            return deleteSessionAuthHeaders
        }
    }

    static let state = State()

    private let stopLock = NSLock()
    private var stopped = false

    private var isStopped: Bool {
        stopLock.lock()
        defer { stopLock.unlock() }
        return stopped
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func stopLoading() {
        stopLock.lock()
        stopped = true
        stopLock.unlock()
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        switch url.path {
        case "/redirect", "/accounts/selftest-redirect/balances":
            let targetURL = URL(string: "https://selftest.example.com/redirect-target")!
            let redirectResponse = HTTPURLResponse(
                url: url,
                statusCode: 302,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": targetURL.absoluteString]
            )!
            var redirectRequest = URLRequest(url: targetURL)
            redirectRequest.httpMethod = "GET"
            client?.urlProtocol(self, wasRedirectedTo: redirectRequest, redirectResponse: redirectResponse)
            // Si URLSession sigue el 302 (sin NoRedirectDelegate), CFNetwork llama a `stopLoading()` y abre `targetURL`.
            // Si `NoRedirectDelegate` rechaza con `completionHandler(nil)`, CFNetwork no para este protocolo y espera
            // a que entregue la propia respuesta 302 (`didReceive` + `didFinishLoading`).
            nonisolated(unsafe) let proto = self
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .milliseconds(30)) {
                guard !proto.isStopped else { return }
                proto.client?.urlProtocol(proto, didReceive: redirectResponse, cacheStoragePolicy: .notAllowed)
                proto.client?.urlProtocolDidFinishLoading(proto)
            }
            return

        case "/redirect-target":
            Self.state.recordRedirectTargetHit()
            sendResponse(url: url, status: 200, headers: ["Content-Type": "application/json"], body: Data(#"{"ok":true}"#.utf8))

        case "/ok":
            sendResponse(url: url, status: 200, headers: ["Content-Type": "application/json"], body: Data(#"{"balances":[]}"#.utf8))

        case "/too-large-header", "/accounts/selftest-too-large/balances":
            sendResponse(
                url: url,
                status: 200,
                headers: ["Content-Length": "\(BankingConstants.maxResponseBytes + 1)"],
                body: Data([0x7b])
            )

        case "/stream-exact-1024":
            streamBytes(url: url, totalBytes: 1_024)

        case "/stream-over-1024", "/accounts/selftest-stream-over/balances":
            streamBytes(url: url, totalBytes: 1_025)

        case "/sessions/selftest-s1" where request.httpMethod == "DELETE":
            Self.state.recordDeleteSessionAuth(request.value(forHTTPHeaderField: "Authorization"))
            sendResponse(url: url, status: 204, headers: nil, body: nil)

        default:
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
        }
    }

    private func sendResponse(url: URL, status: Int, headers: [String: String]?, body: Data?) {
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let body, !isStopped {
            client?.urlProtocol(self, didLoad: body)
        }
        if !isStopped {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    private func streamBytes(url: URL, totalBytes: Int) {
        // Sin cabecera Content-Length -> expectedContentLength == -1: fuerza el corte en streaming byte a byte.
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/octet-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let chunk = Data(repeating: 0x41, count: 256)
        var remaining = totalBytes
        while remaining > 0 && !isStopped {
            let n = min(remaining, chunk.count)
            client?.urlProtocol(self, didLoad: n == chunk.count ? chunk : Data(repeating: 0x41, count: n))
            remaining -= n
        }
        if !isStopped {
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}

struct BankingSelfTestView: View {
    @State private var result = "Autoprueba: en curso"

    var body: some View {
        Text(result)
            .padding()
            .task {
                result = await BankingSelfTest.run { step in
                    result = "Autoprueba: en curso (\(step))"
                }
            }
    }
}
#endif
