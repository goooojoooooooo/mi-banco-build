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
    /// Si en el disco ya está lo que dejaría la restauración, no se sustituye la copia de seguridad (R40).
    /// Si el `ledger.json` actual no se puede decodificar, la copia previa es igualmente una copia del fichero tal cual
    /// y la restauración no necesita leerlo: restaurar funciona justo cuando más falta hace.
    func restoreKeepingCopy(_ state: LedgerState, copyName: String,
                            makeCopy: (FileStore, String) throws -> Void = { try $0.copyCurrent(to: $1) }) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try coordinatedWrite {
            let current = try? load()
            var ledger = Ledger(state: current ?? LedgerState())
            ledger.restore(state)
            // Si lo que hay en el disco ya es lo que dejaría esta restauración (el caso: «No se pudo terminar…», cerrar y elegir
            // el mismo fichero), la copia de seguridad que existe es la de ANTES de la primera restauración y no se pisa con
            // una copia de lo que ya es la copia restaurada. Un libro ilegible nunca cuenta como igual: se copia tal cual.
            let alreadyRestored = current != nil && current == ledger.state
            if !alreadyRestored {
                do { try makeCopy(self, copyName) } catch { throw RestoreError.safetyCopyFailed }
            }
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
