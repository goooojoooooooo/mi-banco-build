import Testing
@testable import MiBancoCore

/// Lote final (menores C-lote3): la voz lee el texto recortado y la línea que suena sale de `SpokenBriefing.line(at:)`
/// sobre ESE texto (antes la app repetía la búsqueda y la corrección de rangos por su cuenta).
@Suite struct SpokenBriefingTrimTests {
    private let spoken = SpokenBriefing(
        text: "  Hola. Has gastado poco. Te entra la nómina. ",
        lines: [.init(id: "headline", range: 8..<25), .init(id: "salary", range: 26..<45)])

    @Test func trimmingShiftsEveryLine() {
        let trimmed = spoken.trimmed()
        #expect(trimmed.text == "Hola. Has gastado poco. Te entra la nómina.")
        #expect(trimmed.lines.map(\.range) == [6..<23, 24..<43])
        let utf16 = Array(trimmed.text.utf16)
        for line in trimmed.lines {
            let piece = String(decoding: utf16[line.range], as: UTF16.self)
            #expect(!piece.isEmpty && piece.first != " ", "\(line.id): «\(piece)»")
        }
        #expect(String(decoding: utf16[trimmed.lines[0].range], as: UTF16.self) == "Has gastado poco.")
    }

    @Test func theLineAtAnOffsetOfTheSpokenText() {
        let trimmed = spoken.trimmed()
        #expect(trimmed.line(at: 0) == nil, "el saludo no es una línea")
        #expect(trimmed.line(at: 6) == "headline")
        #expect(trimmed.line(at: 22) == "headline")
        #expect(trimmed.line(at: 23) == nil, "entre líneas")
        #expect(trimmed.line(at: 30) == "salary")
        #expect(trimmed.line(at: 500) == nil)
    }

    @Test func nothingToTrimKeepsItAsIs() {
        let plain = SpokenBriefing(text: "Hola. Poco.", lines: [.init(id: "headline", range: 6..<11)])
        #expect(plain.trimmed() == plain)
    }
}
