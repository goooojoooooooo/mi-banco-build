import Foundation
import Testing
@testable import MiBancoCore

/// I-2 (lote 3): el ojo compartido con la extensión de avisos y la Live Activity.
@Suite struct SharedPrivacyTests {
    @Test func publishAndReadRoundTrip() throws {
        let name = "SharedPrivacyTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(SharedPrivacy.read(from: defaults) == nil, "sin escribir no dice nada")
        SharedPrivacy.publish(true, to: defaults)
        #expect(SharedPrivacy.read(from: defaults) == true)
        #expect(defaults.bool(forKey: "privateMode"), "la clave es «privateMode»")
        SharedPrivacy.publish(false, to: defaults)
        #expect(SharedPrivacy.read(from: defaults) == false)
        #expect(SharedPrivacy.read(from: nil) == nil)
        SharedPrivacy.publish(true, to: nil) // sin suite: no hace nada ni falla
    }

    /// La regla: carga O suite; sin suite legible, manda la carga; sin nada, cifras como siempre.
    @Test func masksWhenThePayloadOrTheSharedEyeSaySo() {
        #expect(SharedPrivacy.masks(payload: true, shared: nil))
        #expect(SharedPrivacy.masks(payload: true, shared: false))
        #expect(SharedPrivacy.masks(payload: false, shared: true))
        #expect(SharedPrivacy.masks(payload: nil, shared: true))
        #expect(!SharedPrivacy.masks(payload: false, shared: false))
        #expect(!SharedPrivacy.masks(payload: nil, shared: nil))
        #expect(!SharedPrivacy.masks(payload: "sí", shared: nil), "una carga que no es un booleano no cuenta")
    }

    @Test func theSuiteIsTheAppGroup() {
        #expect(resolveAppGroupID(infoDictionary: [:]) == "group.com.mibanco.shared")
        #expect(resolveAppGroupID(infoDictionary: ["ALTAppGroups": ["group.x.y"]]) == "group.x.y")
    }
}
