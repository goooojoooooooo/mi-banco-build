import Foundation

public enum RestoreError: Error, Equatable, Sendable {
    /// No se pudo guardar la copia de lo que había: la restauración se aborta y no se toca nada.
    case safetyCopyFailed
}

public extension FileStore {
    /// Restaura `state` guardando antes una copia de lo actual, todo dentro de UNA sola actualización coordinada:
    /// nada puede escribir entre la copia y la restauración. Si la copia falla, se aborta (el libro queda como estaba)
    /// y se lanza `RestoreError.safetyCopyFailed`. `makeCopy` existe para poder probar ese fallo.
    func restoreKeepingCopy(_ state: LedgerState, copyName: String,
                            makeCopy: (FileStore, String) throws -> Void = { try $0.copyCurrent(to: $1) }) throws {
        var copyFailed = false
        _ = try update { (ledger: inout Ledger) -> Bool in
            do { try makeCopy(self, copyName) } catch {
                copyFailed = true
                return false
            }
            ledger.restore(state)
            return true
        }
        if copyFailed { throw RestoreError.safetyCopyFailed }
    }
}
