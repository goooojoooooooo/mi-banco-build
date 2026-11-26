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
}
