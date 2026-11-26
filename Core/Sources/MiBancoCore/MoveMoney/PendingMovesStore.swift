import Foundation

/// `pending-moves.json` en el almacén protegido (junto al libro y la cartera): escritura atómica,
/// protección de fichero `.completeFileProtectionUntilFirstUserAuthentication` y coordinación en Darwin.
public final class PendingMovesStore: Sendable {
    public static let fileName = "pending-moves.json"
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    public func load() -> [PendingMove] {
        #if canImport(Darwin)
        var loaded: [PendingMove] = []
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: fileURL, options: [], error: &coordinationError) { url in
            loaded = Self.readUnlocked(from: url)
        }
        return loaded
        #else
        return Self.readUnlocked(from: fileURL)
        #endif
    }

    public func save(_ moves: [PendingMove]) throws {
        #if canImport(Darwin)
        var result: Result<Void, Error>?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordinationError) { url in
            result = Result { try self.writeUnlocked(moves, to: url) }
        }
        if let coordinationError { throw coordinationError }
        try result!.get()
        #else
        try writeUnlocked(moves, to: fileURL)
        #endif
    }

    /// Migra una vez los traspasos guardados en `UserDefaults.standard` al archivo protegido.
    /// Solo borra la clave antigua tras comprobar que el archivo se escribió y se puede leer.
    /// Si falla la escritura, conserva la clave antigua y devuelve los traspasos sin perder nada.
    @discardableResult
    public func migrateLegacy(readLegacy: () -> Data?, clearLegacy: () -> Void) -> [PendingMove] {
        guard let legacyData = readLegacy() else { return load() }
        let legacyMoves = decodePendingMoves(legacyData)
        let existing = load()
        var seen = Set(existing.map(\.id))
        var merged = existing
        for move in legacyMoves where seen.insert(move.id).inserted {
            merged.append(move)
        }
        if merged.isEmpty {
            clearLegacy()
            return []
        }
        do {
            try save(merged)
            let verified = load()
            guard verified.map(\.id) == merged.map(\.id) else { return merged }
            clearLegacy()
            return verified
        } catch {
            return merged
        }
    }

    private static func readUnlocked(from url: URL) -> [PendingMove] {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        return decodePendingMoves(data)
    }

    private func writeUnlocked(_ moves: [PendingMove], to url: URL) throws {
        let fm = FileManager.default
        if moves.isEmpty {
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
            return
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var options: Data.WritingOptions = [.atomic]
        #if canImport(Darwin)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try JSONEncoder().encode(moves).write(to: url, options: options)
    }
}
