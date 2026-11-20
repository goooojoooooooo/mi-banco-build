import XCTest

/// La autoprueba DEBUG genera una clave, firma un JWT, verifica la firma y recorre el Llavero en el simulador.
final class BankingSelfTestUITests: XCTestCase {
    func testSignerAndKeychain() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-MiBancoSelfTest", "-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()
        let ok = app.staticTexts["Autoprueba: OK"]
        if !ok.waitForExistence(timeout: 20) {
            // Dice en qué paso falla (o si la pantalla ni apareció) en vez de un fallo mudo.
            let shown = app.staticTexts.allElementsBoundByIndex.map { $0.label }.joined(separator: " | ")
            XCTFail("La autoprueba no termina en OK. Texto en pantalla: \(shown)")
        }
    }
}
