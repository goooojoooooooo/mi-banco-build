import Foundation
import Testing
@testable import MiBancoCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Madrid")!
    c.locale = Locale(identifier: "es_ES")
    return c
}()

private func nov(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

private func pay(_ cents: Int, _ merchant: String?, _ when: Date, bank: BankID = .rev, isShop: Bool = false,
                 flagged: Bool = false, note: String? = nil, ownTransfer: Bool? = nil,
                 category: SpendingCategory? = nil) -> Movement {
    Movement(bank: bank, amountCents: -cents, merchant: merchant, kind: .payment, source: .notification, date: when,
             isShop: isShop, note: note, flaggedNotMine: flagged, category: category, ownTransfer: ownTransfer)
}

private func income(_ cents: Int, _ merchant: String?, _ when: Date, bank: BankID = .ima, note: String? = nil) -> Movement {
    Movement(bank: bank, amountCents: cents, merchant: merchant, kind: .income, source: .notification, date: when, note: note)
}

private func tempDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("backup-tests-\(UUID().uuidString)")
}

@Suite struct BackupTests {
    private func fullState() -> LedgerState {
        var s = LedgerState(
            balances: [.rev: ManualBalance(cents: 123_456, setAt: nov(1), fromBank: false)],
            movements: [
                pay(1250, "Mercadona", nov(19, 23, 35), isShop: true, note: "Compra semanal", category: .supermercado),
                pay(20000, "Transferencia a imagin", nov(15, 10, 0), ownTransfer: true),
                income(20000, "Transferencia de Revolut", nov(15, 10, 5)),
            ],
            unread: [UnreadNotice(bank: .tr, text: "texto", date: nov(10))],
            mutedMerchants: ["glovo"],
            categoryOverrides: ["glovo": .comerFuera],
            dismissedSubscriptions: ["rev|netflix"])
        s.alertSettings = AlertSettings(everyMovement: false, lowBalance: false, lowBalanceThresholdCents: 4_200,
                                        largePayment: true, largePaymentThresholdCents: 33_300, income: false,
                                        subscriptions: false, duplicateCharge: false, weeklyDigest: false,
                                        spendingPace: false, budgets: false)
        s.budgets = Budgets(monthlyCents: 90_000, byCategory: [.supermercado: 30_000, .ocio: 5_000])
        return s
    }

    @Test func idaYVuelta() throws {
        let s = fullState()
        let file = try decodeBackup(encodeBackup(s, exportedAt: nov(20, 9)))
        #expect(file.ledger == s)
        #expect(file.ledger.alertSettings != AlertSettings())
        #expect(file.ledger.alertSettings.largePaymentThresholdCents == 33_300)
        #expect(file.version == 1)
        #expect(file.app == "MiBanco")
        #expect(file.exportedAt == nov(20, 9))
    }

    @Test func ficheroQueNoEsCopia() throws {
        #expect(throws: BackupError.notABackup) { try decodeBackup(Data("hola".utf8)) }
        let bare = try JSONEncoder().encode(fullState())
        #expect(throws: BackupError.notABackup) { try decodeBackup(bare) }
        let otherApp = Data(#"{"app":"Otra","version":1}"#.utf8)
        #expect(throws: BackupError.notABackup) { try decodeBackup(otherApp) }
    }

    @Test func versionMasNueva() throws {
        var file = BackupFile(exportedAt: nov(20, 9), ledger: fullState())
        file.version = 2
        let data = try JSONEncoder().encode(file)
        #expect(throws: BackupError.newerVersion(2)) { try decodeBackup(data) }
        // Una versión futura con otra forma tampoco se confunde con "no es una copia".
        let future = Data(#"{"app":"MiBanco","version":3,"ledger":{"cosa":1}}"#.utf8)
        #expect(throws: BackupError.newerVersion(3)) { try decodeBackup(future) }
    }

    @Test func copiaPreviaAntesDeRestaurar() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileStore(directory: dir)
        var a = LedgerState()
        a.movements = [pay(500, "Bar Manolo", nov(10))]
        var b = LedgerState()
        b.movements = [pay(900, "Zara", nov(11), isShop: true)]
        try store.save(a)
        try store.copyCurrent(to: "ledger-antes-de-restaurar.json")
        try store.update { $0.restore(b) }
        #expect(try store.load() == b)
        let saved = try Data(contentsOf: dir.appendingPathComponent("ledger-antes-de-restaurar.json"))
        #expect(try JSONDecoder().decode(LedgerState.self, from: saved) == a)
    }

    @Test func copyCurrentSinFicheroNoHaceNada() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileStore(directory: dir).copyCurrent(to: "ledger-antes-de-restaurar.json")
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("ledger-antes-de-restaurar.json").path))
    }

    @Test func nombres() {
        #expect(backupFileName(exportedAt: nov(20, 9), calendar: cal) == "MiBanco-2026-11-20.json")
        #expect(movementsCSVFileName(exportedAt: nov(20, 9), calendar: cal) == "MiBanco-movimientos-2026-11-20.csv")
    }

    @Test func csvEscapaPuntoYComaYComillas() {
        let rev = pay(1250, "Mercadona", nov(19, 23, 35), isShop: true)
        let ima = Movement(bank: .ima, amountCents: 2000, merchant: "Bizum de \"Laura\"; cena", kind: .income,
                           source: .notification, date: nov(18, 19, 12), note: "Cena; viernes")
        let csv = movementsCSV(LedgerState(movements: [rev, ima]), now: nov(20), calendar: cal)
        #expect(csv == "Fecha;Hora;Banco;Tipo;Comercio;Categoría;Importe;Nota;No es mío;Traspaso propio\r\n"
            + "2026-11-18;19:12;imagin;Ingreso;\"Bizum de \"\"Laura\"\"; cena\";;20,00;\"Cena; viernes\";;\r\n"
            + "2026-11-19;23:35;Revolut;Pago;Mercadona;Supermercado;-12,50;;;\r\n")
    }

    @Test func csvMarcas() {
        let notMine = pay(700, "Zara", nov(12), isShop: true, flagged: true)
        let transfer = pay(5000, "Mover dinero", nov(13), ownTransfer: true)
        let big = income(123_456, "Nómina", nov(14))
        let csv = movementsCSV(LedgerState(movements: [notMine, transfer, big]), now: nov(20), calendar: cal)
        let rows = csv.components(separatedBy: "\r\n")
        #expect(rows[1].hasSuffix(";-7,00;;sí;"))
        #expect(rows[2].hasSuffix(";-50,00;;;sí"))
        #expect(rows[3].contains(";1234,56;"))
        #expect(!rows[3].contains("1.234"))
    }

    @Test func csvConBOM() {
        let data = movementsCSVData(LedgerState(), now: nov(20), calendar: cal)
        #expect(Array(data.prefix(3)) == [0xEF, 0xBB, 0xBF])
        #expect(String(decoding: data.dropFirst(3), as: UTF8.self) == movementsCSV(LedgerState(), now: nov(20), calendar: cal))
    }

    @Test func csvNeutralizaFormulasEnColumnasDeTexto() {
        let evil = pay(1250, "=HYPERLINK(\"http://x\",\"y\")", nov(19), note: "+34 600 000 000")
        let at = income(500, "@SUM(A1)", nov(18), note: "-cmd")
        let tab = pay(100, "\tTab", nov(17), note: "\rCR")
        let csv = movementsCSV(LedgerState(movements: [evil, at, tab]), now: nov(20), calendar: cal)
        #expect(csv.contains("\"'=HYPERLINK(\"\"http://x\"\",\"\"y\"\")\""))
        #expect(csv.contains(";'+34 600 000 000;"))
        #expect(csv.contains(";'@SUM(A1);"))
        #expect(csv.contains(";'-cmd;"))
        #expect(csv.contains(";'\tTab;"))
        #expect(csv.contains("\"'\rCR\""))
        // Ningún campo de texto empieza ya por un carácter de fórmula.
        #expect(!csv.contains(";=HYPERLINK"))
        #expect(!csv.contains(";+34"))
    }

    @Test func csvNoTocaElImporte() {
        let neg = pay(1250, "Mercadona", nov(19), isShop: true)
        let pos = income(2000, "Nómina", nov(18))
        let csv = movementsCSV(LedgerState(movements: [neg, pos]), now: nov(20), calendar: cal)
        let rows = csv.components(separatedBy: "\r\n")
        #expect(rows[1].contains(";20,00;"))
        #expect(rows[2].contains(";-12,50;"))
        #expect(!csv.contains("'-12,50"))
    }

    @Test func copyCurrentSustituyeLaCopiaAnteriorSinDejarTemporales() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileStore(directory: dir)
        var a = LedgerState()
        a.movements = [pay(500, "Bar Manolo", nov(10))]
        var b = LedgerState()
        b.movements = [pay(900, "Zara", nov(11), isShop: true)]
        try store.save(a)
        try store.copyCurrent(to: "copia.json")
        try store.save(b)
        try store.copyCurrent(to: "copia.json")
        let saved = try Data(contentsOf: dir.appendingPathComponent("copia.json"))
        #expect(try JSONDecoder().decode(LedgerState.self, from: saved) == b)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(names == ["copia.json", "ledger.json"])
    }

    @Test func copiaQueFallaDejaIntactaLaAnterior() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileStore(directory: dir)
        var a = LedgerState()
        a.movements = [pay(500, "Bar Manolo", nov(10))]
        try store.save(a)
        try store.copyCurrent(to: "copia.json")
        let ledgerURL = dir.appendingPathComponent("ledger.json")
        // Con ledger.json ilegible la copia falla; si se ejecuta como root no hay forma de provocarlo y no se comprueba.
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: ledgerURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: ledgerURL.path) }
        guard !FileManager.default.isReadableFile(atPath: ledgerURL.path) else { return }
        #expect(throws: (any Error).self) { try store.copyCurrent(to: "copia.json") }
        let saved = try Data(contentsOf: dir.appendingPathComponent("copia.json"))
        #expect(try JSONDecoder().decode(LedgerState.self, from: saved) == a)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(names == ["copia.json", "ledger.json"])
    }

    @Test func restaurarGuardaCopiaYSustituye() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileStore(directory: dir)
        var a = LedgerState()
        a.movements = [pay(500, "Bar Manolo", nov(10))]
        var b = LedgerState()
        b.movements = [pay(900, "Zara", nov(11), isShop: true)]
        try store.save(a)
        try store.restoreKeepingCopy(b, copyName: "antes.json")
        #expect(try store.load() == b)
        let saved = try Data(contentsOf: dir.appendingPathComponent("antes.json"))
        #expect(try JSONDecoder().decode(LedgerState.self, from: saved) == a)
    }

    @Test func siFallaLaCopiaPreviaNoSeRestauraNada() throws {
        struct Boom: Error {}
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileStore(directory: dir)
        var a = LedgerState()
        a.movements = [pay(500, "Bar Manolo", nov(10))]
        var b = LedgerState()
        b.movements = [pay(900, "Zara", nov(11), isShop: true)]
        try store.save(a)
        #expect(throws: RestoreError.safetyCopyFailed) {
            try store.restoreKeepingCopy(b, copyName: "antes.json", makeCopy: { _, _ in throw Boom() })
        }
        #expect(try store.load() == a)
    }

    @Test func copiaQueFallaALaMitadDejaIntactaLaAnteriorTambienComoRoot() throws {
        struct Boom: Error {}
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileStore(directory: dir)
        var a = LedgerState()
        a.movements = [pay(500, "Bar Manolo", nov(10))]
        try store.save(a)
        try store.copyCurrent(to: "copia.json")
        let before = try Data(contentsOf: dir.appendingPathComponent("copia.json"))
        var b = LedgerState()
        b.movements = [pay(900, "Zara", nov(11), isShop: true)]
        try store.save(b)
        // La copia escribe algo y falla a mitad: la anterior no se toca y no queda ningún temporal.
        #expect(throws: Boom.self) {
            try store.copyCurrent(to: "copia.json", copy: { _, temp in
                try Data("a medias".utf8).write(to: temp)
                throw Boom()
            })
        }
        #expect(try Data(contentsOf: dir.appendingPathComponent("copia.json")) == before)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(names == ["copia.json", "ledger.json"])
    }

    @Test func restaurarFuncionaConElLibroActualCorrupto() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileStore(directory: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let corrupt = Data("esto no es json {{{".utf8)
        try corrupt.write(to: dir.appendingPathComponent("ledger.json"))
        var b = LedgerState()
        b.movements = [pay(900, "Zara", nov(11), isShop: true)]
        try store.restoreKeepingCopy(b, copyName: "antes.json")
        #expect(try store.load() == b)
        #expect(try Data(contentsOf: dir.appendingPathComponent("antes.json")) == corrupt)
        // Una copia corrupta no se ofrece como "lo de antes".
        #expect(store.copyInfo(named: "antes.json") == nil)
    }

    @Test func restaurarSinLibroPreviosTambienFunciona() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileStore(directory: dir)
        var b = LedgerState()
        b.movements = [pay(900, "Zara", nov(11), isShop: true)]
        try store.restoreKeepingCopy(b, copyName: "antes.json")
        #expect(try store.load() == b)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("antes.json").path))
    }

    @Test func copyInfoDevuelveLoGuardadoYSuFecha() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileStore(directory: dir)
        #expect(store.copyInfo(named: "antes.json") == nil)
        var a = LedgerState()
        a.movements = [pay(500, "Bar Manolo", nov(10))]
        try store.save(a)
        try store.copyCurrent(to: "antes.json")
        let info = try #require(store.copyInfo(named: "antes.json"))
        #expect(info.state == a)
        #expect(abs(info.date.timeIntervalSinceNow) < 120)
    }
}

