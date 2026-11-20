import Foundation
import Testing
@testable import MiBancoCore

private final class RecordingSigner: JWTSigner, @unchecked Sendable {
    private let lock = NSLock()
    private var _received: Data?
    var received: Data? { lock.withLock { _received } }
    func signRS256(_ message: Data) throws -> Data {
        lock.withLock { _received = message }
        return Data([1, 2, 3])
    }
}

private func decodeB64URL(_ s: String) -> Data? {
    var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while t.count % 4 != 0 { t += "=" }
    return Data(base64Encoded: t)
}

@Suite struct JWTTests {
    private let appID = "00000000-0000-4000-8000-000000000001"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func base64URLHasNoPaddingAndSafeAlphabet() {
        #expect(base64URL(Data([0xfb, 0xff])) == "-_8")
        #expect(base64URL(Data("a".utf8)) == "YQ")
    }

    @Test func jwtSigningInputIsExact() {
        let input = enableBankingJWTSigningInput(appID: appID, now: now, lifetime: 3600)
        let header = #"{"alg":"RS256","kid":"00000000-0000-4000-8000-000000000001","typ":"JWT"}"#
        let claims = #"{"aud":"api.enablebanking.com","exp":1800003600,"iat":1800000000,"iss":"enablebanking.com"}"#
        #expect(input == base64URL(Data(header.utf8)) + "." + base64URL(Data(claims.utf8)))
    }

    @Test func jwtLifetimeIsClamped() throws {
        let input = enableBankingJWTSigningInput(appID: appID, now: now, lifetime: 100_000)
        let payload = try #require(decodeB64URL(String(input.split(separator: ".")[1])))
        #expect(String(decoding: payload, as: UTF8.self).contains(#""exp":1800086400"#))
    }

    @Test func jwtAppendsSignature() throws {
        let signer = RecordingSigner()
        let token = try enableBankingJWT(appID: appID, now: now, signer: signer)
        #expect(token.hasSuffix(".AQID"))
        let input = enableBankingJWTSigningInput(appID: appID, now: now, lifetime: 3600)
        #expect(signer.received == Data(input.utf8))
        #expect(token == input + ".AQID")
    }
}
