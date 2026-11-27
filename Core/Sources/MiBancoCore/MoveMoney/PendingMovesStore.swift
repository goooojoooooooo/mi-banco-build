import Foundation

/// Fallo al leer o proteger `pending-moves.json` (M-11).
/// Distingue claramente «el archivo no existe» (lista vacía normal) de «existe pero no se puede leer o está corrupto».
public enum PendingMovesStoreError: Error, Equatable, Sendable {
    case unreadable
    case corrupt
}

/// `pending-moves.json` en el almacén protegido (junto al libro y la cartera): escritura atómica,
/// protección de fichero `.completeFileProtectionUntilFirstUserAuthentication` y coordinación en Darwin.
/// Política de seguridad ante archivos ilegibles o corruptos (M-11):
/// - `load()` devuelve `[]` SIN borrar ni tocar el archivo;
/// - `loadThrowing()` devuelve `[]` solo si el archivo no existe, y lanza `.unreadable` o `.corrupt` si existe y falla;
/// - `save(_:)`, `add(_:)`, `remove(_:)` y `migrateLegacy(...)` comprueban el archivo existente antes de escribir
///   y rechazan sobrescribirlo o borrarlo si es ilegible o corrupto, evitando perder datos previos.
public final class PendingMovesStore: Sendable {
    public static let fileName = "pending-moves.json"
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    /// Lectura segura para interfaz: si el archivo no existe, no se puede leer o está corrupto devuelve `[]`
    /// sin borrar ni modificar el archivo en disco.
    public func load() -> [PendingMove] {
        (try? loadThrowing()) ?? []
    }

    /// Lectura estricta que distingue ausencia real (`ENOENT` / `NSFileReadNoSuchFileError` → `[]`)
    /// de un error de lectura (`.unreadable`) o JSON inválido (`.corrupt`).
    public func loadThrowing() throws -> [PendingMove] {
        #if canImport(Darwin)
        var result: Result<[PendingMove], Error>?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: fileURL, options: [], error: &coordinationError) { url in
            result = Result { try Self.readThrowingUnlocked(from: url) }
        }
        if coordinationError != nil { throw PendingMovesStoreError.unreadable }
        return try result!.get()
        #else
        return try Self.readThrowingUnlocked(from: fileURL)
        #endif
    }

    public func save(_ moves: [PendingMove]) throws {
        try coordinatedWrite { url in
            try self.writeUnlocked(moves, to: url)
        }
    }

    /// Añade o sustituye un traspaso pendiente en una sola operación coordinada.
    /// Si el archivo existente es ilegible o corrupto, lanza error sin tocarlo ni perderlo.
    public func add(_ move: PendingMove) throws {
        try coordinatedWrite { url in
            var list = try Self.readThrowingUnlocked(from: url)
            list.removeAll { $0.id == move.id }
            list.insert(move, at: 0)
            try self.writeVerifiedUnlocked(list, to: url)
        }
    }

    /// Quita un traspaso pendiente en una sola operación coordinada.
    /// Si el archivo existente es ilegible o corrupto, lanza error sin tocarlo ni perderlo.
    public func remove(_ id: UUID) throws {
        try coordinatedWrite { url in
            var list = try Self.readThrowingUnlocked(from: url)
            list.removeAll { $0.id == id }
            try self.writeVerifiedUnlocked(list, to: url)
        }
    }

    /// Migra una vez los traspasos guardados en `UserDefaults.standard` al archivo protegido.
    /// Solo borra la clave antigua tras comprobar que el archivo se escribió y se puede leer.
    /// Si el archivo ya existe pero es ilegible/corrupto, o si falla la escritura, conserva intactos tanto
    /// el archivo como la clave heredada y devuelve los traspasos sin perder nada.
    @discardableResult
    public func migrateLegacy(readLegacy: () -> Data?, clearLegacy: () -> Void) -> [PendingMove] {
        guard let legacyData = readLegacy() else { return load() }
        let legacyMoves = decodePendingMoves(legacyData)
        let existing: [PendingMove]
        do {
            existing = try loadThrowing()
        } catch {
            return legacyMoves
        }
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
            let verified = try loadThrowing()
            guard verified.map(\.id) == merged.map(\.id) else { return merged }
            clearLegacy()
            return verified
        } catch {
            return merged
        }
    }

    private func coordinatedWrite(_ body: (URL) throws -> Void) throws {
        #if canImport(Darwin)
        var result: Result<Void, Error>?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordinationError) { url in
            result = Result { try body(url) }
        }
        if coordinationError != nil { throw PendingMovesStoreError.unreadable }
        try result!.get()
        #else
        try body(fileURL)
        #endif
    }

    private static func readThrowingUnlocked(from url: URL) throws -> [PendingMove] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            if isNoSuchFileError(error) { return [] }
            throw PendingMovesStoreError.unreadable
        }
        do {
            return try decodePendingMovesThrowing(data)
        } catch {
            throw PendingMovesStoreError.corrupt
        }
    }

    private static func matchesNoSuchFile(_ error: Error) -> Bool {
        if let cocoa = error as? CocoaError, cocoa.code == .fileReadNoSuchFile { return true }
        if let posix = error as? POSIXError, posix.code == .ENOENT { return true }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == CocoaError.Code.fileReadNoSuchFile.rawValue { return true }
        if ns.domain == NSPOSIXErrorDomain && ns.code == Int(POSIXError.Code.ENOENT.rawValue) { return true }
        return false
    }

    private static func isNoSuchFileError(_ error: Error) -> Bool {
        if matchesNoSuchFile(error) { return true }
        if let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? Error {
            return matchesNoSuchFile(underlying)
        }
        return false
    }

    private func writeUnlocked(_ moves: [PendingMove], to url: URL) throws {
        // Rechaza pisar o borrar un archivo existente que sea ilegible o corrupto (M-11).
        _ = try Self.readThrowingUnlocked(from: url)
        try writeVerifiedUnlocked(moves, to: url)
    }

    private func writeVerifiedUnlocked(_ moves: [PendingMove], to url: URL) throws {
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
