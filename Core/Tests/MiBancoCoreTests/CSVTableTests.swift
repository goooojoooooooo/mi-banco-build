import Foundation
import Testing
@testable import MiBancoCore

@Suite struct CSVTableTests {
    private func parse(_ s: String) throws -> CSVTable { try CSVTable.parse(Data(s.utf8)) }

    @Test func parsesQuotedSemicolonCSV() throws {
        let t = try parse("\u{FEFF}a;b\r\n\"x;1\";\"dijo \"\"hola\"\"\"\r\n\r\n")
        #expect(t.headers == ["a", "b"])
        #expect(t.rows == [["x;1", "dijo \"hola\""]])
    }

    @Test func parsesLatin1() throws {
        // Windows-1252: cada carácter es un byte (É = 0xC9).
        let text = "Fecha;Movimiento\n01/11/2026;CAF\u{C9}\n"
        let bytes = text.unicodeScalars.map { UInt8($0.value) }
        let t = try CSVTable.parse(Data(bytes))
        #expect(t.headers == ["Fecha", "Movimiento"])
        #expect(t.rows == [["01/11/2026", "CAFÉ"]])
    }

    @Test func parsesWindows1252SpecialCharacters() throws {
        // 0x80 = €, 0x92 = ’ en Windows-1252 (no son Latin-1).
        let t = try CSVTable.parse(Data([0x61, 0x3B, 0x62, 0x0A, 0x80, 0x3B, 0x92, 0x0A]))
        #expect(t.rows == [["€", "\u{2019}"]])
    }

    @Test func parsesCommaCRLFAndEmbeddedNewline() throws {
        let t = try parse("a,b\r\n\"línea 1\nlínea 2\",2\r\n3,\"4,5\"\r\n")
        #expect(t.headers == ["a", "b"])
        #expect(t.rows == [["línea 1\nlínea 2", "2"], ["3", "4,5"]])
    }

    @Test func parsesTabSeparatedAndLastRowWithoutNewline() throws {
        let t = try parse("a\tb\n1\t2")
        #expect(t.headers == ["a", "b"])
        #expect(t.rows == [["1", "2"]])
    }

    @Test func delimiterIsDecidedOutsideQuotes() throws {
        // La cabecera trae una coma entre comillas; el separador real es `;`.
        let t = try parse("\"a,b\";c\n1;2\n")
        #expect(t.headers == ["a,b", "c"])
        #expect(t.rows == [["1", "2"]])
    }

    @Test func noHeaderIsEmpty() {
        #expect(throws: StatementError.empty) { try CSVTable.parse(Data()) }
        #expect(throws: StatementError.empty) { try CSVTable.parse(Data("\r\n\r\n".utf8)) }
    }

    @Test func headerOnlyHasNoRows() throws {
        let t = try parse("a;b\n")
        #expect(t.rows.isEmpty)
    }

    @Test func columnMatchesByAliasIgnoringCaseAccentsAndUnderscores() throws {
        let t = try parse("Fecha de Finalización,Transaction_ID , Importe\n1,2,3\n")
        #expect(t.column(["fecha de finalizacion"]) == 0)
        #expect(t.column(["transaction_id"]) == 1)
        #expect(t.column(["amount", "importe"]) == 2)
        #expect(t.column(["saldo"]) == nil)
    }

    @Test func normalizeHeaderFolds() {
        #expect(normalizeHeader("  Más   Datos ") == "mas datos")
        #expect(normalizeHeader("counterparty_name") == "counterparty name")
        #expect(normalizeHeader("\u{FEFF}Fecha") == "fecha")
    }

    @Test func parseSignedEuropeanAmountCases() {
        #expect(parseSignedEuropeanAmount("-23,45") == -2345)
        #expect(parseSignedEuropeanAmount("1.250,00") == 125_000)
        #expect(parseSignedEuropeanAmount("+5,00") == 500)
        #expect(parseSignedEuropeanAmount("7") == 700)
        #expect(parseSignedEuropeanAmount("abc") == nil)
        #expect(parseSignedEuropeanAmount("") == nil)
        #expect(parseSignedEuropeanAmount("-1.284,55 €") == -128_455)
        #expect(parseSignedEuropeanAmount("12.50") == 1250)
        #expect(parseSignedEuropeanAmount("23,45-") == -2345)
    }
}
