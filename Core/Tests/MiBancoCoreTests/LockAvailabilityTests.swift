import Foundation
import Testing
@testable import MiBancoCore

/// Clasificación pura del fallo de `canEvaluatePolicy` (SEC-08): solo `LAError.passcodeNotSet` es «sin código».
@Suite struct LockAvailabilityTests {
    private let laDomain = "com.apple.LocalAuthentication"

    @Test func sinErrorEsRecuperable() {
        #expect(lockAvailability(errorDomain: nil, errorCode: nil) == .unavailable)
        #expect(lockAvailability(errorDomain: laDomain, errorCode: nil) == .unavailable)
        #expect(lockAvailability(errorDomain: nil, errorCode: lockPasscodeNotSetErrorCode) == .unavailable)
    }

    @Test func passcodeNotSetEsSinCodigo() {
        #expect(lockPasscodeNotSetErrorCode == -5)
        #expect(lockAvailability(errorDomain: laDomain, errorCode: -5) == .passcodeNotSet)
    }

    @Test func otrosCodigosDeLocalAuthenticationSeReintentan() {
        // biometryLockout = -8, biometryNotAvailable = -6, biometryNotEnrolled = -7, userCancel = -2, systemCancel = -4.
        for code in [-8, -6, -7, -2, -4, -1, 0, 5] {
            #expect(lockAvailability(errorDomain: laDomain, errorCode: code) == .unavailable, "\(code)")
        }
    }

    @Test func otroDominioNuncaEsSinCodigo() {
        #expect(lockAvailability(errorDomain: NSCocoaErrorDomain, errorCode: -5) == .unavailable)
        #expect(lockAvailability(errorDomain: "", errorCode: -5) == .unavailable)
    }
}
