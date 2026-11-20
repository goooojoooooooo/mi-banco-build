import Foundation

/// `portfolio.json` en la carpeta indicada; mismo patrón que `FileStore` (escritura atómica, protección de fichero y
/// coordinación en Darwin).
public final class PortfolioStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private var fileURL: URL { directory.appendingPathComponent("portfolio.json") }

    public func load() throws -> Portfolio {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return Portfolio() }
        return try JSONDecoder().decode(Portfolio.self, from: Data(contentsOf: fileURL))
    }

    public func save(_ p: Portfolio) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var options: Data.WritingOptions = [.atomic]
        #if canImport(Darwin)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try JSONEncoder().encode(p).write(to: fileURL, options: options)
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
