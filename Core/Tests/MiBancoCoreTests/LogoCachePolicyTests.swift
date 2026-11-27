import Foundation
import Testing
@testable import MiBancoCore

@Suite struct LogoCachePolicyTests {
    @Test func hashedFileNameUsesPrefixAndLowercaseHex() {
        let hex = String(repeating: "A1", count: 32)
        let name = LogoCachePolicy.fileName(forHashHex: hex)
        #expect(name == "h_" + String(repeating: "a1", count: 32))
        #expect(!name.contains("mercadona"))
        #expect(LogoCachePolicy.isHashedCacheFile(name + ".png"))
        #expect(LogoCachePolicy.isHashedCacheFile(name + ".none"))
    }

    @Test func identifiesOnlyPlaintextLegacyFilesForRemoval() {
        let validHex = String(repeating: "0f", count: 32)
        let files = [
            "casa-lola.png",
            "mercadona.none",
            "bar-manolo.png",
            "h_\(validHex).png",
            "h_\(validHex).none",
            "h_short.png",
            ".DS_Store",
        ]
        let toRemove = LogoCachePolicy.legacyFilesToRemove(in: files)
        #expect(toRemove == ["casa-lola.png", "mercadona.none", "bar-manolo.png", "h_short.png"])
    }

    @Test func logoDownloadsAreOptInByDefaultWithCappedSize() async throws {
        #expect(LogoCachePolicy.defaultDownloadsEnabled == false)
        #expect(LogoCachePolicy.maxDownloadBytes == 256_000)

        let stream = AsyncStream<UInt8> { cont in
            for _ in 0..<(LogoCachePolicy.maxDownloadBytes + 1) { cont.yield(0x41) }
            cont.finish()
        }
        await #expect(throws: CappedDownloadError.tooLarge) {
            _ = try await collectCapped(stream, expectedLength: -1, limit: LogoCachePolicy.maxDownloadBytes)
        }
    }
}
