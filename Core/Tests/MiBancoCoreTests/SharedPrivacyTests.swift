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

    /// N-3: en la app, el ojo de la carga sale de la fuente de verdad, no de la copia: si la copia de la suite falta o
    /// se quedó vieja, la carga sigue diciendo «cerrado» y la vista ampliada tapa las cifras igual.
    @Test func theAppEyeComesFromTheSourceOfTruthNotFromTheCopy() throws {
        let truthName = "SharedPrivacyTests-truth-\(UUID().uuidString)"
        let copyName = "SharedPrivacyTests-copy-\(UUID().uuidString)"
        let truth = try #require(UserDefaults(suiteName: truthName))
        let copy = try #require(UserDefaults(suiteName: copyName))
        defer {
            truth.removePersistentDomain(forName: truthName)
            copy.removePersistentDomain(forName: copyName)
        }
        truth.set(true, forKey: "privateMode") // así lo guarda AppPreferences (clave `privateModeKey`)
        #expect(SharedPrivacy.key == "privateMode")
        #expect(SharedPrivacy.appEye(from: truth))
        // La copia nunca se escribió: la carga sola basta.
        #expect(SharedPrivacy.masks(payload: SharedPrivacy.appEye(from: truth), shared: SharedPrivacy.read(from: copy)))
        // La copia se quedó vieja («abierto»): la carga, de la fuente de verdad, manda igual.
        SharedPrivacy.publish(false, to: copy)
        #expect(SharedPrivacy.masks(payload: SharedPrivacy.appEye(from: truth), shared: SharedPrivacy.read(from: copy)))
        truth.set(false, forKey: "privateMode")
        #expect(!SharedPrivacy.appEye(from: truth))
    }

    /// N-4: la Live Activity acaba siempre con el ojo de ahora: se corrige si no coincide, y no se toca si coincide.
    @Test func theLiveActivityEndsWithTheCurrentEye() {
        #expect(SharedPrivacy.reconciled(current: false, eyeNow: true) == true)
        #expect(SharedPrivacy.reconciled(current: nil, eyeNow: true) == true, "un estado viejo sin el campo se corrige")
        #expect(SharedPrivacy.reconciled(current: true, eyeNow: false) == false)
        #expect(SharedPrivacy.reconciled(current: true, eyeNow: true) == nil)
        #expect(SharedPrivacy.reconciled(current: nil, eyeNow: false) == nil)
        // Dos cambios rápidos en cualquier orden: lo que queda es el último ojo leído, no el orden de llegada.
        var state: Bool? = nil
        for eye in [true, false, true] {
            if let next = SharedPrivacy.reconciled(current: state, eyeNow: eye) { state = next }
        }
        #expect(state == true)
    }

    @Test func theSuiteIsTheAppGroup() {
        #expect(resolveAppGroupID(infoDictionary: [:]) == "group.com.mibanco.shared")
        #expect(resolveAppGroupID(infoDictionary: ["ALTAppGroups": ["group.x.y"]]) == "group.x.y")
    }
}
