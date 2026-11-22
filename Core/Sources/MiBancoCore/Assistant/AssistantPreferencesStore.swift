import Foundation

/// `assistant-preferences.json` en la carpeta indicada (contenedor del App Group; entra en las copias del iPhone).
/// Guarda temas, pesos e ids de tarjeta (con nombres de comercio normalizados), sin importes (U61).
/// Mismo patrón que `PortfolioStore` y `FileStore`: escritura atómica, protección de fichero y coordinación en Darwin.
public final class AssistantPreferencesStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private var fileURL: URL { directory.appendingPathComponent("assistant-preferences.json") }

    public func load() throws -> AssistantPreferences {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return AssistantPreferences() }
        return try JSONDecoder().decode(AssistantPreferences.self, from: Data(contentsOf: fileURL))
    }

    /// Lee las preferencias o devuelve las de fábrica si el archivo no existe o está dañado (no bloquea el asistente).
    public func loadRecovering() -> AssistantPreferences {
        (try? load()) ?? AssistantPreferences()
    }

    public func save(_ preferences: AssistantPreferences) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var options: Data.WritingOptions = [.atomic]
        #if canImport(Darwin)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try JSONEncoder().encode(preferences).write(to: fileURL, options: options)
    }

    /// Lee, aplica y guarda; en Darwin dentro de un `NSFileCoordinator`.
    public func update<T>(_ body: (inout AssistantPreferences) -> T) throws -> T {
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

    private func apply<T>(_ body: (inout AssistantPreferences) -> T) throws -> T {
        var preferences: AssistantPreferences
        do {
            preferences = try load()
        } catch is DecodingError {
            // Un archivo corrupto o truncado no puede bloquear para siempre «Me interesa» / Ajustes; los errores reales de E/S sí suben.
            preferences = AssistantPreferences()
        }
        let value = body(&preferences)
        try save(preferences)
        return value
    }
}
