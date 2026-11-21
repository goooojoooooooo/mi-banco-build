import Foundation
import Testing
@testable import MiBancoCore

@Suite struct AuthCallbackTests {
    private func parse(_ text: String, state: String = "s1") -> AuthCallbackResult {
        parseAuthCallback(URL(string: text)!, expectedState: state)
    }

    @Test func callbackAcceptsCode() {
        #expect(parse("mibanco://cb?code=abc&state=s1") == .code("abc"))
        #expect(parse("mibanco://cb?state=s1&code=a%2Fb") == .code("a/b"))
    }

    @Test func callbackRejectsWrongState() {
        #expect(parse("mibanco://cb?code=abc&state=s1", state: "s2") == .stateMismatch)
        #expect(parse("mibanco://cb?code=abc") == .stateMismatch)
        #expect(parse("mibanco://cb?code=abc&state=s1", state: "") == .stateMismatch)
        #expect(parse("mibanco://cb?code=abc&state=s1x") == .stateMismatch)
        #expect(parse("mibanco://cb?code=abc&state=s") == .stateMismatch)
    }

    @Test func callbackDenied() {
        #expect(parse("mibanco://cb?error=access_denied&state=s1") == .denied)
        #expect(parse("mibanco://cb?error=access_denied&state=zz") == .stateMismatch)
    }

    @Test func callbackRejectsForeignHost() {
        #expect(parse("https://evil.example/cb?code=x&state=s1") == .malformed)
        #expect(parse("mibanco://other?code=x&state=s1") == .malformed)
        #expect(parse("mibanco://cb?state=s1") == .malformed)
        #expect(parse("mibanco://cb?code=&state=s1") == .malformed)
        #expect(parse("otro://cb?code=x&state=s1") == .malformed)
    }

    @Test func callbackRejectsPathUserPasswordAndPort() {
        #expect(parse("mibanco://cb/extra?code=x&state=s1") == .malformed)
        #expect(parse("mibanco://cb/a/b?code=x&state=s1") == .malformed)
        #expect(parse("mibanco://user@cb?code=x&state=s1") == .malformed)
        #expect(parse("mibanco://user:pass@cb?code=x&state=s1") == .malformed)
        #expect(parse("mibanco://cb:8080?code=x&state=s1") == .malformed)
        // Una ruta vacía o "/" sigue valiendo.
        #expect(parse("mibanco://cb/?code=x&state=s1") == .code("x"))
        #expect(parse("mibanco://cb?code=x&state=s1") == .code("x"))
    }

    @Test func constantTimeCompare() {
        #expect(constantTimeEqual("abc", "abc"))
        #expect(!constantTimeEqual("abc", "abd"))
        #expect(!constantTimeEqual("abc", "ab"))
        #expect(constantTimeEqual("", ""))
    }
}
