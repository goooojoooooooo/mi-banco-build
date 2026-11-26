import Foundation

/// `nyx-memory.json` en la misma carpeta que el libro (`SharedStore`: App Group o carpeta de la app).
/// Mismo patrón que `AssistantPreferencesStore`: escritura atómica, protección de fichero y coordinación en Darwin.
/// No entra en la copia de seguridad de Onyx y nunca registra nada.
public final class NyxMemoryStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private var fileURL: URL { directory.appendingPathComponent("nyx-memory.json") }

    public func load() throws -> NyxMemory {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return NyxMemory() }
        return try JSONDecoder().decode(NyxMemory.self, from: Data(contentsOf: fileURL))
    }

    /// Lee la memoria o devuelve una memoria vacía si falta o está dañada (nunca bloquea a Nyx).
    public func loadRecovering() -> NyxMemory {
        (try? load()) ?? NyxMemory()
    }

    public func save(_ m: NyxMemory) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var options: Data.WritingOptions = [.atomic]
        #if canImport(Darwin)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try JSONEncoder().encode(m).write(to: fileURL, options: options)
    }

    /// Lee, aplica y guarda; en Darwin dentro de un `NSFileCoordinator`.
    public func update<T>(_ body: (inout NyxMemory) -> T) throws -> T {
        #if canImport(Darwin)
        var result: Result<T, Error>?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: fileURL, options: .forMerging, error: &coordinationError) { _ in
            result = Result { try self.apply(body) }
        }
        if let coordinationError { throw coordinationError }
        return try result!.get()
        #else
        return try apply(body)
        #endif
    }

    /// Borra `nyx-memory.json` («Olvidar lo que he aprendido»). Si ya no existe, no falla.
    public func delete() throws {
        #if canImport(Darwin)
        var result: Result<Void, Error>?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: fileURL, options: .forDeleting, error: &coordinationError) { url in
            result = Result { try self.removeIfPresent(at: url) }
        }
        if let coordinationError { throw coordinationError }
        try result!.get()
        #else
        try removeIfPresent(at: fileURL)
        #endif
    }

    private func apply<T>(_ body: (inout NyxMemory) -> T) throws -> T {
        var memory: NyxMemory
        do {
            memory = try load()
        } catch is DecodingError {
            // Un archivo corrupto o truncado nunca bloquea la vigilancia; los errores reales de E/S sí suben.
            memory = NyxMemory()
        }
        let value = body(&memory)
        try save(memory)
        return value
    }

    private func removeIfPresent(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }
}
