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

    // MARK: R39 — filas con celdas sobrantes vacías o cabecera con columnas sin nombre

    @Test func extraTrailingEmptyCellsAreTrimmed() throws {
        let t = try parse("a;b;c\n1;2;3;\n4;5;6;;\n7;8;9\n")
        #expect(t.headers == ["a", "b", "c"])
        #expect(t.rows == [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]])
        #expect(t.malformedRows == 0)
    }

    @Test func missingTrailingCellsArePaddedOnlyUnderUnnamedHeaders() throws {
        let t = try parse("a;b;c;\n1;2;3\n4;5;6;\n")
        #expect(t.headers == ["a", "b", "c", ""])
        #expect(t.rows == [["1", "2", "3", ""], ["4", "5", "6", ""]])
        #expect(t.malformedRows == 0)
        // Falta una columna con nombre: no se rellena.
        let named = try parse("a;b;c;d\n1;2;3\n")
        #expect(named.rows.isEmpty)
        #expect(named.malformedRows == 1)
    }

    @Test func rowWithARealExtraValueIsStillRejected() throws {
        let t = try parse("a;b;c\n1;2;3;x\n4;5;6;;x\n7;8;9\n")
        #expect(t.rows == [["7", "8", "9"]])
        #expect(t.malformedRows == 2)
        // Cabecera con columna sin nombre y fila corta en dos: solo falta una sin nombre y otra con nombre.
        let mixed = try parse("a;b;;d\n1;2\n")
        #expect(mixed.rows.isEmpty)
        #expect(mixed.malformedRows == 1)
    }

    // MARK: SEC-11 — topes de filas, columnas y longitud de celda

    @Test func rejectsTooManyColumns() throws {
        let okHeader = (1...CSVTable.maxColumns).map { "c\($0)" }.joined(separator: ",")
        let okRow = (1...CSVTable.maxColumns).map { "\($0)" }.joined(separator: ",")
        let ok = try parse("\(okHeader)\n\(okRow)\n")
        #expect(ok.headers.count == CSVTable.maxColumns)

        let tooManyHeader = (1...(CSVTable.maxColumns + 1)).map { "c\($0)" }.joined(separator: ",")
        #expect(throws: CSVLimitError.tooManyColumns(limit: CSVTable.maxColumns)) {
            try parse("\(tooManyHeader)\n")
        }
    }

    @Test func rejectsCellLongerThanLimit() throws {
        let okCell = String(repeating: "a", count: CSVTable.maxCellLength)
        let ok = try parse("a,b\n\(okCell),1\n")
        #expect(ok.rows.first?.first?.count == CSVTable.maxCellLength)

        let tooLongCell = String(repeating: "a", count: CSVTable.maxCellLength + 1)
        #expect(throws: CSVLimitError.cellTooLong(limit: CSVTable.maxCellLength)) {
            try parse("a,b\n\(tooLongCell),1\n")
        }
    }

    @Test func rejectsTooManyRows() throws {
        var csv = "a,b\n"
        csv.reserveCapacity(4 + (CSVTable.maxRows + 1) * 4)
        for _ in 0..<CSVTable.maxRows { csv += "1,2\n" }
        let ok = try parse(csv)
        #expect(ok.rows.count == CSVTable.maxRows)

        csv += "1,2\n"
        #expect(throws: CSVLimitError.tooManyRows(limit: CSVTable.maxRows)) {
            try parse(csv)
        }
    }
}
