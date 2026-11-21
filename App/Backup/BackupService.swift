import Foundation
import MiBancoCore

/// Lo que se enseña en la hoja de restaurar: la copia ya decodificada y cuántos movimientos hay ahora.
struct RestorePreview: Identifiable, Sendable {
    let id = UUID()
    let file: BackupFile
    let currentCount: Int
    /// Es la copia que la app guardó antes de la última restauración ("Volver a lo de antes"), no un fichero elegido.
    var isPrevious = false
}

/// Un fichero temporal listo para la hoja de compartir.
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// Copias y CSV: ficheros temporales con protección completa, que se borran al cerrar la hoja de compartir
/// (y se barren al arrancar por si la app se cerró con una hoja abierta). Es dinero: nada queda en claro por ahí.
enum BackupService {
    private static let maxBackupBytes = 64 * 1024 * 1024

    private static var folder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Exportaciones", isDirectory: true)
    }

    static func exportBackup(_ state: LedgerState, portfolio: Portfolio? = nil, now: Date) throws -> URL {
        let data = try encodeBackup(state, portfolio: portfolio, exportedAt: now)
        return try write(data, named: backupFileName(exportedAt: now, calendar: .current))
    }

    static func exportCSV(_ state: LedgerState, now: Date) throws -> URL {
        let data = movementsCSVData(state, now: now, calendar: .current)
        return try write(data, named: movementsCSVFileName(exportedAt: now, calendar: .current))
    }

    /// Lee y valida el fichero elegido sin tocar nada. Lanza `BackupError` si no es una copia (o es de una versión más nueva).
    static func preview(_ url: URL, current: LedgerState) throws -> RestorePreview {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // Sin tamaño conocido tampoco se lee: un fichero sin `fileSize` no se cuela como si fuera de 0 bytes.
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maxBackupBytes else {
            throw BackupError.notABackup
        }
        let file = try decodeBackup(Data(contentsOf: url))
        return RestorePreview(file: file, currentCount: current.movements.count)
    }

    /// Borra un fichero temporal exportado y su subcarpeta (solo si está dentro de la carpeta de exportaciones).
    static func remove(_ url: URL) {
        let own = url.deletingLastPathComponent()
        guard own.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: own)
    }

    /// Borra todo lo que quedara de exportaciones anteriores. Solo al arrancar: cada exportación vive en su propia
    /// subcarpeta y se borra al cerrar su hoja, así que dos exportaciones seguidas no se pisan.
    static func sweep() {
        try? FileManager.default.removeItem(at: folder)
    }

    private static func write(_ data: Data, named name: String) throws -> URL {
        let own = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: own, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        let url = own.appendingPathComponent(name)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}
