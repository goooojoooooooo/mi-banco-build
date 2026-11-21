import Foundation

/// `portfolio.json` en la carpeta indicada; mismo patrón que `FileStore` (escritura atómica, protección de fichero y
/// coordinación en Darwin).
public final class PortfolioStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private var fileURL: URL { directory.appendingPathComponent("portfolio.json") }

    private func copyURL(named name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    public func load() throws -> Portfolio {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return Portfolio() }
        return try JSONDecoder().decode(Portfolio.self, from: Data(contentsOf: fileURL))
    }

    public func save(_ p: Portfolio) throws {
        try write(p, to: fileURL)
    }

    /// Guarda una copia de seguridad de la cartera (p. ej. antes de restaurar) con la misma protección de fichero.
    public func saveCopy(_ p: Portfolio, named name: String) throws {
        let target = copyURL(named: name)
        #if canImport(Darwin)
        var result: Result<Void, Error>?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordinationError) { url in
            result = Result { try self.write(p, to: url) }
        }
        if let coordinationError { throw coordinationError }
        try result!.get()
        #else
        try write(p, to: target)
        #endif
    }

    /// Lee una copia previa guardada con `saveCopy`; nil si no existe o no se puede decodificar.
    public func loadCopy(named name: String) -> Portfolio? {
        let target = copyURL(named: name)
        guard FileManager.default.fileExists(atPath: target.path),
              let data = try? Data(contentsOf: target) else { return nil }
        return try? JSONDecoder().decode(Portfolio.self, from: data)
    }

    private func write(_ p: Portfolio, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var options: Data.WritingOptions = [.atomic]
        #if canImport(Darwin)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try JSONEncoder().encode(p).write(to: url, options: options)
    }

    /// Lee, aplica y guarda; en Darwin dentro de un NSFileCoordinator.
    public func update<T>(_ body: (inout Portfolio) -> T) throws -> T {
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

    private func apply<T>(_ body: (inout Portfolio) -> T) throws -> T {
        var portfolio = try load()
        let value = body(&portfolio)
        try save(portfolio)
        return value
    }
}
