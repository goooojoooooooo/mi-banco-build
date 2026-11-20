import XCTest

/// La autoprueba DEBUG genera una clave, firma un JWT, verifica la firma y recorre el Llavero en el simulador.
final class BankingSelfTestUITests: XCTestCase {
    func testSignerAndKeychain() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-MiBancoSelfTest", "-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Autoprueba: OK"].waitForExistence(timeout: 20),
                      "La autoprueba no termina en OK")
    }
}
