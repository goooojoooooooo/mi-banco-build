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

    @Test func corruptFileLoadsEmptyWithoutDeletingAndBlocksOverwrite() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent(PendingMovesStore.fileName)
        let corruptBytes = Data("{not-valid-pending-moves".utf8)
        try corruptBytes.write(to: fileURL)

        let store = PendingMovesStore(directory: dir)
        #expect(store.load().isEmpty)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(try Data(contentsOf: fileURL) == corruptBytes)
        #expect(throws: PendingMovesStoreError.corrupt) {
            _ = try store.loadThrowing()
        }

        let newMove = sampleMove(amount: 42_000)
        #expect(throws: PendingMovesStoreError.corrupt) {
            try store.add(newMove)
        }
        #expect(try Data(contentsOf: fileURL) == corruptBytes)

        #expect(throws: PendingMovesStoreError.corrupt) {
            try store.remove(newMove.id)
        }
        #expect(try Data(contentsOf: fileURL) == corruptBytes)

        #expect(throws: PendingMovesStoreError.corrupt) {
            try store.save([newMove])
        }
        #expect(try Data(contentsOf: fileURL) == corruptBytes)

        #expect(throws: PendingMovesStoreError.corrupt) {
            try store.save([])
        }
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(try Data(contentsOf: fileURL) == corruptBytes)

        // Si el destino está corrupto, migrateLegacy tampoco debe machacarlo ni borrar la clave heredada.
        var legacyData: Data? = try JSONEncoder().encode([newMove])
        var cleared = false
        _ = store.migrateLegacy(
            readLegacy: { legacyData },
            clearLegacy: {
                cleared = true
                legacyData = nil
            }
        )
        #expect(!cleared)
        #expect(legacyData != nil)
        #expect(try Data(contentsOf: fileURL) == corruptBytes)
    }

    @Test func unreadableFileLoadsEmptyWithoutDeletingAndBlocksOverwrite() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Un directorio donde debería haber un fichero provoca un error de lectura real distinto de ENOENT incluso como root.
        let fileURL = dir.appendingPathComponent(PendingMovesStore.fileName)
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)

        let store = PendingMovesStore(directory: dir)
        #expect(store.load().isEmpty)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(throws: PendingMovesStoreError.unreadable) {
            _ = try store.loadThrowing()
        }

        let newMove = sampleMove(amount: 15_000)
        #expect(throws: PendingMovesStoreError.unreadable) {
            try store.add(newMove)
        }
        #expect(throws: PendingMovesStoreError.unreadable) {
            try store.save([newMove])
        }
        #expect(throws: PendingMovesStoreError.unreadable) {
            try store.save([])
        }
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func missingFileDistinguishesFromCorruptAndAllowsAddAndRemove() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = PendingMovesStore(directory: dir)
        #expect(try store.loadThrowing().isEmpty)

        let first = sampleMove(amount: 12_000)
        let second = sampleMove(amount: 34_000)
        try store.add(first)
        try store.add(second)
        #expect(try store.loadThrowing() == [second, first])

        try store.remove(second.id)
        #expect(try store.loadThrowing() == [first])

        try store.remove(first.id)
        #expect(try store.loadThrowing().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent(PendingMovesStore.fileName).path))
    }

    @Test func clearLegacyIfPersistedKeepsKeyWhileLegacyMovesAreNotInFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PendingMovesStore(directory: dir)
        let legacyMove = sampleMove(amount: 1_000)
        let other = sampleMove(amount: 2_000)
        let legacyData = try JSONEncoder().encode([legacyMove])
        try store.add(other)

        var cleared = 0
        store.clearLegacyIfPersisted(readLegacy: { legacyData }, clearLegacy: { cleared += 1 })
        #expect(cleared == 0)

        // Quitar el propio traspaso heredado también permite limpiar la clave (ya no debe resucitar).
        store.clearLegacyIfPersisted(ignoring: legacyMove.id, readLegacy: { legacyData }, clearLegacy: { cleared += 1 })
        #expect(cleared == 1)

        try store.add(legacyMove)
        store.clearLegacyIfPersisted(readLegacy: { legacyData }, clearLegacy: { cleared += 1 })
        #expect(cleared == 2)
    }

    @Test func clearLegacyIfPersistedKeepsKeyWhenFileIsCorrupt() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("corrupt".utf8).write(to: dir.appendingPathComponent(PendingMovesStore.fileName))
        let legacyData = try JSONEncoder().encode([sampleMove()])
        var cleared = 0
        PendingMovesStore(directory: dir).clearLegacyIfPersisted(readLegacy: { legacyData }, clearLegacy: { cleared += 1 })
        #expect(cleared == 0)
    }
}
