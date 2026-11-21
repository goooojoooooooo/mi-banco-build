import Foundation

public enum RestoreError: Error, Equatable, Sendable {
    /// No se pudo guardar la copia de lo que había: la restauración se aborta y no se toca nada.
    case safetyCopyFailed
    /// La restauración se escribió bien pero no se pudo volver a leer el libro: los datos SÍ cambiaron en el disco.
    case reloadFailed
}

public extension FileStore {
    /// Restaura `state` guardando antes una copia de lo actual, todo dentro de UNA sola escritura coordinada:
    /// nada puede escribir entre la copia y la restauración. Si la copia falla, se aborta (el libro queda como estaba)
    /// y se lanza `RestoreError.safetyCopyFailed`. `makeCopy` existe para poder probar ese fallo.
    /// Si el `ledger.json` actual no se puede decodificar, la copia previa es igualmente una copia del fichero tal cual
    /// y la restauración no necesita leerlo: restaurar funciona justo cuando más falta hace.
    func restoreKeepingCopy(_ state: LedgerState, copyName: String,
                            makeCopy: (FileStore, String) throws -> Void = { try $0.copyCurrent(to: $1) }) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try coordinatedWrite {
            do { try makeCopy(self, copyName) } catch { throw RestoreError.safetyCopyFailed }
            var ledger = Ledger(state: loadOrEmpty())
            ledger.restore(state)
            try save(ledger.state)
        }
    }
}

/// Orden seguro de la copia previa de la cartera al restaurar el libro (U57): solo sustituye la copia previa tras restaurar bien el libro.
public func restorePortfolioSafetyCopyPlan(
    saveTemp: () throws -> Void,
    restoreLedger: () throws -> Void,
    promoteTemp: () throws -> Void,
    removeTemp: () -> Void
) throws {
    try saveTemp()
    do {
        try restoreLedger()
    } catch {
        removeTemp()
        throw error
    }
    do {
        try promoteTemp()
    } catch {
        removeTemp()
        throw error
    }
}
