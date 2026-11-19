import Testing
@testable import MiBancoCore

@Suite struct AppGroupTests {
    @Test func usaElPrimerGrupoDeAltStore() {
        #expect(resolveAppGroupID(infoDictionary: ["ALTAppGroups": ["group.com.mibanco.shared.ABCDE12345"]])
            == "group.com.mibanco.shared.ABCDE12345")
    }

    @Test func sinAltStoreUsaElFallback() {
        #expect(resolveAppGroupID(infoDictionary: [:]) == "group.com.mibanco.shared")
    }
}
