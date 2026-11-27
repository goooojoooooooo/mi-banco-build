import Foundation
import Testing
@testable import MiBancoCore

@Suite struct StoreMigrationTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mibanco-mig-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func freshMigrationCopiesVerifiesAndDeletesLegacyLedger() throws {
        let legacyDir = try makeTempDir()
        let groupDir = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: legacyDir)
            try? FileManager.default.removeItem(at: groupDir)
        }

        var ledger = Ledger()
        ledger.setBalance(.rev, cents: 42_500, now: Date(timeIntervalSince1970: 1_700_000_000))
        try FileStore(directory: legacyDir).save(ledger.state)

        migrateLegacyStoreFiles(from: legacyDir, to: groupDir)

        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: legacyDir.appendingPathComponent("ledger.json").path))
        #expect(fm.fileExists(atPath: groupDir.appendingPathComponent("ledger.json").path))
        let migrated = try FileStore(directory: groupDir).load()
        #expect(migrated.balances[.rev]?.cents == 42_500)
    }

    @Test func alreadyMigratedDeletesOrphanWithoutOverwritingGroup() throws {
        let legacyDir = try makeTempDir()
        let groupDir = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: legacyDir)
            try? FileManager.default.removeItem(at: groupDir)
        }

        var oldLedger = Ledger()
        oldLedger.setBalance(.rev, cents: 10_000, now: Date(timeIntervalSince1970: 1_700_000_000))
        try FileStore(directory: legacyDir).save(oldLedger.state)

        var newLedger = Ledger()
        newLedger.setBalance(.rev, cents: 99_900, now: Date(timeIntervalSince1970: 1_700_001_000))
        try FileStore(directory: groupDir).save(newLedger.state)

        migrateLegacyStoreFiles(from: legacyDir, to: groupDir)

        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: legacyDir.appendingPathComponent("ledger.json").path))
        let kept = try FileStore(directory: groupDir).load()
        #expect(kept.balances[.rev]?.cents == 99_900)
    }

    @Test func corruptGroupTargetKeepsLegacyBackupIntact() throws {
        let legacyDir = try makeTempDir()
        let groupDir = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: legacyDir)
            try? FileManager.default.removeItem(at: groupDir)
        }

        var oldLedger = Ledger()
        oldLedger.setBalance(.ima, cents: 55_000, now: Date(timeIntervalSince1970: 1_700_000_000))
        try FileStore(directory: legacyDir).save(oldLedger.state)
        try Data("{not-valid-json".utf8).write(to: groupDir.appendingPathComponent("ledger.json"))

        migrateLegacyStoreFiles(from: legacyDir, to: groupDir)

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: legacyDir.appendingPathComponent("ledger.json").path))
        let legacyRead = try FileStore(directory: legacyDir).load()
        #expect(legacyRead.balances[.ima]?.cents == 55_000)
    }

    @Test func corruptLegacyIsNeverDeleted() throws {
        let legacyDir = try makeTempDir()
        let groupDir = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: legacyDir)
            try? FileManager.default.removeItem(at: groupDir)
        }

        let legacyFile = legacyDir.appendingPathComponent("ledger.json")
        try Data("{corrupt".utf8).write(to: legacyFile)

        migrateLegacyStoreFiles(from: legacyDir, to: groupDir)

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: legacyFile.path))
        #expect(!fm.fileExists(atPath: groupDir.appendingPathComponent("ledger.json").path))
    }

    @Test func sameDirectoryIsNoOpAndNeverDeletes() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        var ledger = Ledger()
        ledger.setBalance(.tr, cents: 12_000, now: Date(timeIntervalSince1970: 1_700_000_000))
        try FileStore(directory: dir).save(ledger.state)

        migrateLegacyStoreFiles(from: dir, to: dir)

        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("ledger.json").path))
    }

    @Test func migratesPortfolioAndAssistantPreferencesToo() throws {
        let legacyDir = try makeTempDir()
        let groupDir = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: legacyDir)
            try? FileManager.default.removeItem(at: groupDir)
        }

        var portfolio = Portfolio()
        portfolio.symbols["IE00BK5BQT80"] = "VWCE.DE"
        try PortfolioStore(directory: legacyDir).save(portfolio)

        var prefs = AssistantPreferences()
        prefs.disabledTopics.insert(.budgetClose)
        try AssistantPreferencesStore(directory: legacyDir).save(prefs)

        migrateLegacyStoreFiles(from: legacyDir, to: groupDir)

        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: legacyDir.appendingPathComponent("portfolio.json").path))
        #expect(!fm.fileExists(atPath: legacyDir.appendingPathComponent("assistant-preferences.json").path))
        #expect(try PortfolioStore(directory: groupDir).load().symbols["IE00BK5BQT80"] == "VWCE.DE")
        #expect(try AssistantPreferencesStore(directory: groupDir).load().disabledTopics.contains(.budgetClose))
    }

    private func setModificationDate(_ date: Date, for url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private func backupFiles(in dir: URL, for fileName: String) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("\(fileName).antes-de-rescate-") && $0.pathExtension == "bak" }
    }

    @Test func newerDistinctLegacyPromotesAllFourFilesAndPreservesOlderTargetsInBackup() throws {
        let legacyDir = try makeTempDir()
        let groupDir = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: legacyDir)
            try? FileManager.default.removeItem(at: groupDir)
        }

        let olderDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newerDate = Date(timeIntervalSince1970: 1_700_000_600)

        var oldLedger = Ledger()
        oldLedger.setBalance(.rev, cents: 10_000, now: olderDate)
        try FileStore(directory: groupDir).save(oldLedger.state)
        var newLedger = Ledger()
        newLedger.setBalance(.rev, cents: 88_800, now: newerDate)
        try FileStore(directory: legacyDir).save(newLedger.state)

        var oldPortfolio = Portfolio()
        oldPortfolio.symbols["IE00BK5BQT80"] = "OLD.DE"
        try PortfolioStore(directory: groupDir).save(oldPortfolio)
        var newPortfolio = Portfolio()
        newPortfolio.symbols["IE00BK5BQT80"] = "NEW.DE"
        try PortfolioStore(directory: legacyDir).save(newPortfolio)

        var oldPrefs = AssistantPreferences()
        oldPrefs.disabledTopics.insert(.budgetClose)
        try AssistantPreferencesStore(directory: groupDir).save(oldPrefs)
        var newPrefs = AssistantPreferences()
        newPrefs.disabledTopics.insert(.shortfall)
        try AssistantPreferencesStore(directory: legacyDir).save(newPrefs)

        let oldMove = PendingMove(from: .rev, target: .own(.ima), amountCents: 11_100, createdAt: olderDate)
        try PendingMovesStore(directory: groupDir).save([oldMove])
        let newMove = PendingMove(from: .ima, target: .own(.rev), amountCents: 77_700, createdAt: newerDate)
        try PendingMovesStore(directory: legacyDir).save([newMove])

        let allNames = ["ledger.json", "portfolio.json", "assistant-preferences.json", "pending-moves.json"]
        for name in allNames {
            try setModificationDate(olderDate, for: groupDir.appendingPathComponent(name))
            try setModificationDate(newerDate, for: legacyDir.appendingPathComponent(name))
        }

        migrateLegacyStoreFiles(from: legacyDir, to: groupDir)

        let fm = FileManager.default
        for name in allNames {
            #expect(!fm.fileExists(atPath: legacyDir.appendingPathComponent(name).path))
        }

        // El archivo más nuevo pasa a ser el activo en el App Group.
        #expect(try FileStore(directory: groupDir).load().balances[.rev]?.cents == 88_800)
        #expect(try PortfolioStore(directory: groupDir).load().symbols["IE00BK5BQT80"] == "NEW.DE")
        #expect(try AssistantPreferencesStore(directory: groupDir).load().disabledTopics == [.shortfall])
        #expect(PendingMovesStore(directory: groupDir).load() == [newMove])

        // El destino antiguo queda apartado intacto junto al destino, sin borrarse.
        let ledgerBackups = try backupFiles(in: groupDir, for: "ledger.json")
        #expect(ledgerBackups.count == 1)
        let savedOldLedger = try JSONDecoder().decode(LedgerState.self, from: Data(contentsOf: try #require(ledgerBackups.first)))
        #expect(savedOldLedger.balances[.rev]?.cents == 10_000)

        let portfolioBackups = try backupFiles(in: groupDir, for: "portfolio.json")
        #expect(portfolioBackups.count == 1)
        let savedOldPortfolio = try JSONDecoder().decode(Portfolio.self, from: Data(contentsOf: try #require(portfolioBackups.first)))
        #expect(savedOldPortfolio.symbols["IE00BK5BQT80"] == "OLD.DE")

        let prefsBackups = try backupFiles(in: groupDir, for: "assistant-preferences.json")
        #expect(prefsBackups.count == 1)
        let savedOldPrefs = try JSONDecoder().decode(AssistantPreferences.self, from: Data(contentsOf: try #require(prefsBackups.first)))
        #expect(savedOldPrefs.disabledTopics == [.budgetClose])

        let movesBackups = try backupFiles(in: groupDir, for: "pending-moves.json")
        #expect(movesBackups.count == 1)
        let savedOldMoves = decodePendingMoves(try Data(contentsOf: try #require(movesBackups.first)))
        #expect(savedOldMoves == [oldMove])
    }

    @Test func identicalBytesDeletesLegacyEvenIfNewerWithoutBackup() throws {
        let legacyDir = try makeTempDir()
        let groupDir = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: legacyDir)
            try? FileManager.default.removeItem(at: groupDir)
        }

        var ledger = Ledger()
        ledger.setBalance(.rev, cents: 42_000, now: Date(timeIntervalSince1970: 1_700_000_000))
        let encoded = try JSONEncoder().encode(ledger.state)
        let targetFile = groupDir.appendingPathComponent("ledger.json")
        let legacyFile = legacyDir.appendingPathComponent("ledger.json")
        try encoded.write(to: targetFile)
        try encoded.write(to: legacyFile)
        try setModificationDate(Date(timeIntervalSince1970: 1_700_000_000), for: targetFile)
        try setModificationDate(Date(timeIntervalSince1970: 1_700_000_600), for: legacyFile)

        migrateLegacyStoreFiles(from: legacyDir, to: groupDir)

        #expect(!FileManager.default.fileExists(atPath: legacyFile.path))
        #expect(try FileStore(directory: groupDir).load().balances[.rev]?.cents == 42_000)
        #expect(try backupFiles(in: groupDir, for: "ledger.json").isEmpty)
    }

    @Test func olderOrSameAgeLegacyIsDeletedWithoutOverwritingGroup() throws {
        let legacyDir = try makeTempDir()
        let groupDir = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: legacyDir)
            try? FileManager.default.removeItem(at: groupDir)
        }

        let olderDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newerDate = Date(timeIntervalSince1970: 1_700_000_600)

        var oldLedger = Ledger()
        oldLedger.setBalance(.rev, cents: 10_000, now: olderDate)
        try FileStore(directory: legacyDir).save(oldLedger.state)
        var newLedger = Ledger()
        newLedger.setBalance(.rev, cents: 99_900, now: newerDate)
        try FileStore(directory: groupDir).save(newLedger.state)
        try setModificationDate(olderDate, for: legacyDir.appendingPathComponent("ledger.json"))
        try setModificationDate(newerDate, for: groupDir.appendingPathComponent("ledger.json"))

        // Misma fecha exacta también cuenta como <= y limpia el origen sin sobrescribir.
        let oldMove = PendingMove(from: .rev, target: .own(.ima), amountCents: 1_000, createdAt: olderDate)
        let groupMove = PendingMove(from: .ima, target: .own(.rev), amountCents: 2_000, createdAt: newerDate)
        try PendingMovesStore(directory: legacyDir).save([oldMove])
        try PendingMovesStore(directory: groupDir).save([groupMove])
        try setModificationDate(newerDate, for: legacyDir.appendingPathComponent("pending-moves.json"))
        try setModificationDate(newerDate, for: groupDir.appendingPathComponent("pending-moves.json"))

        migrateLegacyStoreFiles(from: legacyDir, to: groupDir)

        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: legacyDir.appendingPathComponent("ledger.json").path))
        #expect(!fm.fileExists(atPath: legacyDir.appendingPathComponent("pending-moves.json").path))
        #expect(try FileStore(directory: groupDir).load().balances[.rev]?.cents == 99_900)
        #expect(PendingMovesStore(directory: groupDir).load() == [groupMove])
        #expect(try backupFiles(in: groupDir, for: "ledger.json").isEmpty)
        #expect(try backupFiles(in: groupDir, for: "pending-moves.json").isEmpty)
    }

    @Test func newerCorruptLegacyDoesNotOverwriteValidTargetAndIsNotDeleted() throws {
        let legacyDir = try makeTempDir()
        let groupDir = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: legacyDir)
            try? FileManager.default.removeItem(at: groupDir)
        }

        let olderDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newerDate = Date(timeIntervalSince1970: 1_700_000_600)

        var validLedger = Ledger()
        validLedger.setBalance(.rev, cents: 54_321, now: olderDate)
        try FileStore(directory: groupDir).save(validLedger.state)
        let targetLedger = groupDir.appendingPathComponent("ledger.json")
        let legacyLedger = legacyDir.appendingPathComponent("ledger.json")
        try Data("{corrupt-newer".utf8).write(to: legacyLedger)
        try setModificationDate(olderDate, for: targetLedger)
        try setModificationDate(newerDate, for: legacyLedger)

        let validMove = PendingMove(from: .rev, target: .own(.ima), amountCents: 9_900, createdAt: olderDate)
        try PendingMovesStore(directory: groupDir).save([validMove])
        let targetMoves = groupDir.appendingPathComponent("pending-moves.json")
        let legacyMoves = legacyDir.appendingPathComponent("pending-moves.json")
        try Data("not-a-json-array".utf8).write(to: legacyMoves)
        try setModificationDate(olderDate, for: targetMoves)
        try setModificationDate(newerDate, for: legacyMoves)

        migrateLegacyStoreFiles(from: legacyDir, to: groupDir)

        let fm = FileManager.default
        // Destino válido intacto.
        #expect(try FileStore(directory: groupDir).load().balances[.rev]?.cents == 54_321)
        #expect(PendingMovesStore(directory: groupDir).load() == [validMove])
        // Origen corrupto más nuevo NO se borra ni se crean respaldos.
        #expect(fm.fileExists(atPath: legacyLedger.path))
        #expect(try Data(contentsOf: legacyLedger) == Data("{corrupt-newer".utf8))
        #expect(fm.fileExists(atPath: legacyMoves.path))
        #expect(try Data(contentsOf: legacyMoves) == Data("not-a-json-array".utf8))
        #expect(try backupFiles(in: groupDir, for: "ledger.json").isEmpty)
        #expect(try backupFiles(in: groupDir, for: "pending-moves.json").isEmpty)
    }
}
