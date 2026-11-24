import XCTest

/// Sonda temporal: la misma traza de deslizamientos sobre el código base (sin los cambios de la fase de animaciones).
final class MotionHomeTests: XCTestCase {
    var app: XCUIApplication!

    private func launchHome(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-MiBancoDemo", "-AppleLanguages", "(es)", "-AppleLocale", "es_ES"] + extra
        app.launch()
        XCTAssertTrue(app.staticTexts["Tu dinero"].waitForExistence(timeout: 15), "Inicio no aparece")
    }

    private func any(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    private func carousel() -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label ENDSWITH %@", " de 4")).firstMatch
    }

    private func frontCardNumber() -> Int {
        let label = carousel().label
        guard let range = label.range(of: #"([0-9]) de 4$"#, options: .regularExpression) else { return 0 }
        return Int(String(label[range].prefix(1))) ?? 0
    }

    func testFingerSwipesMoveOneCardEachWay() throws {
        launchHome(["-MiBancoDemoCardElements"])
        XCTAssertTrue(carousel().waitForExistence(timeout: 5), "Falta el carrusel")
        XCTAssertEqual(frontCardNumber(), 1)
        /// Dónde está cada tarjeta y los contadores de DEBUG, para el mensaje de un fallo.
        func snapshot() -> String {
            let frames = ["all", "rev", "ima", "tr"].map { name -> String in
                let front = self.any("card-front-\(name)")
                return front.exists ? "\(name)=\(Int(front.frame.minX))" : "\(name)=?"
            }.joined(separator: " ")
            let lifts = any("card-lift-count")
            let fixes = any("card-rest-fixes")
            return "\(frontCardNumber()) [\(frames) lev=\(lifts.exists ? lifts.label : "?") arr=\(fixes.exists ? fixes.label : "?")]"
        }
        // Tres a la izquierda y tres a la derecha, dejando que el carrusel se asiente entre uno y otro.
        var trace: [String] = []
        var numbers: [Int] = []
        for step in 0..<6 {
            if step < 3 { carousel().swipeLeft() } else { carousel().swipeRight() }
            Thread.sleep(forTimeInterval: 2.5)
            numbers.append(frontCardNumber())
            trace.append(snapshot())
        }
        XCTAssertEqual(numbers, [2, 3, 4, 3, 2, 1], "Cada deslizamiento debe mover una tarjeta: \(trace.joined(separator: " → "))")
    }
}
