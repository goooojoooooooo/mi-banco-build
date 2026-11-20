import Foundation

public final class FileStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private var fileURL: URL { directory.appendingPathComponent("ledger.json") }

    public func load() throws -> LedgerState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return LedgerState() }
        return try JSONDecoder().decode(LedgerState.self, from: Data(contentsOf: fileURL))
    }

    public func save(_ s: LedgerState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var options: Data.WritingOptions = [.atomic]
        #if canImport(Darwin)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try JSONEncoder().encode(s).write(to: fileURL, options: options)
    }

    /// Copia `ledger.json`, si existe, a `fileName` en la misma carpeta, sustituyendo la copia anterior.
    /// Copia primero a un nombre temporal y solo después sustituye: si la copia falla, la anterior queda intacta.
    public func copyCurrent(to fileName: String) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return }
        let target = directory.appendingPathComponent(fileName)
        let temp = directory.appendingPathComponent(".\(fileName).\(UUID().uuidString).tmp")
        do {
            try fm.copyItem(at: fileURL, to: temp)
            if fm.fileExists(atPath: target.path) {
                _ = try fm.replaceItemAt(target, withItemAt: temp)
            } else {
                try fm.moveItem(at: temp, to: target)
            }
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
    }

    /// Lee, aplica y guarda; en Darwin dentro de un NSFileCoordinator (app y extensiones comparten el fichero).
    public func update<T>(_ body: (inout Ledger) -> T) throws -> T {
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

    private func apply<T>(_ body: (inout Ledger) -> T) throws -> T {
        var ledger = Ledger(state: try load())
        let value = body(&ledger)
        try save(ledger.state)
        return value
    }
}
