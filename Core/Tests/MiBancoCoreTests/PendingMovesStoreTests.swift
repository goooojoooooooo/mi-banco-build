import Foundation
import Testing
@testable import MiBancoCore

@Suite struct PendingMovesStoreTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mibanco-moves-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func sampleMove(id: UUID = UUID(), amount: Int = 25_000) -> PendingMove {
        PendingMove(
            id: id,
            from: .rev,
            target: .own(.ima),
            amountCents: amount,
            createdAt: Date(timeIntervalSince1970: 1_795_000_000)
        )
    }

    @Test func saveAndLoadRoundTripAndRemoveWhenEmpty() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = PendingMovesStore(directory: dir)
        #expect(store.load().isEmpty)

        let move = sampleMove()
        try store.save([move])
        #expect(store.load() == [move])
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("pending-moves.json").path))

        try store.save([])
        #expect(store.load().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("pending-moves.json").path))
    }

    @Test func migratesFromLegacyOnceAndClearsOldKeyAfterVerifiedWrite() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = PendingMovesStore(directory: dir)
        let move = sampleMove(amount: 50_000)
        var legacyData: Data? = try JSONEncoder().encode([move])
        var clearedCount = 0

        let first = store.migrateLegacy(
            readLegacy: { legacyData },
            clearLegacy: {
                clearedCount += 1
                legacyData = nil
            }
        )
        #expect(first == [move])
        #expect(clearedCount == 1)
        #expect(legacyData == nil)
        #expect(store.load() == [move])

        // Segunda llamada: sin clave vieja, lee del archivo y no vuelve a borrar nada.
        let second = store.migrateLegacy(
            readLegacy: { legacyData },
            clearLegacy: { clearedCount += 1 }
        )
        #expect(second == [move])
        #expect(clearedCount == 1)
    }

    @Test func mergesLegacyWithExistingFileWithoutDuplicating() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = PendingMovesStore(directory: dir)
        let existing = sampleMove(amount: 10_000)
        let legacyOnly = sampleMove(amount: 20_000)
        try store.save([existing])

        var legacyData: Data? = try JSONEncoder().encode([existing, legacyOnly])
        let merged = store.migrateLegacy(
            readLegacy: { legacyData },
            clearLegacy: { legacyData = nil }
        )
        #expect(merged.map(\.id) == [existing.id, legacyOnly.id])
        #expect(legacyData == nil)
        #expect(store.load().map(\.id) == [existing.id, legacyOnly.id])
    }

    @Test func keepsLegacyKeyIntactWhenWriteFails() throws {
        let blocker = FileManager.default.temporaryDirectory
            .appendingPathComponent("mibanco-moves-blocker-\(UUID().uuidString)")
        try Data("not-a-dir".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }

        let store = PendingMovesStore(directory: blocker)
        let move = sampleMove(amount: 33_000)
        var legacyData: Data? = try JSONEncoder().encode([move])
        var cleared = false

        let result = store.migrateLegacy(
            readLegacy: { legacyData },
            clearLegacy: {
                cleared = true
                legacyData = nil
            }
        )
        #expect(result == [move])
        #expect(!cleared)
        #expect(legacyData != nil)
    }
}
