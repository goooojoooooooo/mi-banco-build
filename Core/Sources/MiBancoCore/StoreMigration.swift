import Foundation

/// Migra un fichero del almacén desde la carpeta heredada (`Application Support`) al contenedor del App Group
/// y elimina el origen huérfano SOLO cuando el destino existe y se puede leer y validar correctamente.
/// Si el destino ya existe (p. ej. de una versión anterior que copiaba sin borrar), valida el destino antes
/// de limpiar el huérfano y nunca sobrescribe el destino ni borra nada si algo falla.
@discardableResult
public func migrateStoreFileIfNeeded(
    from legacyDirectory: URL,
    to targetDirectory: URL,
    fileName: String,
    validate: (Data) -> Bool
) -> Bool {
    guard legacyDirectory.standardizedFileURL != targetDirectory.standardizedFileURL else { return false }
    let fm = FileManager.default
    let legacy = legacyDirectory.appendingPathComponent(fileName)
    let target = targetDirectory.appendingPathComponent(fileName)
    guard fm.fileExists(atPath: legacy.path) else { return false }

    if fm.fileExists(atPath: target.path) {
        guard let targetData = try? Data(contentsOf: target), validate(targetData) else { return false }
        try? fm.removeItem(at: legacy)
        return true
    }

    guard let legacyData = try? Data(contentsOf: legacy), validate(legacyData) else { return false }
    do {
        try fm.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        var options: Data.WritingOptions = [.atomic]
        #if canImport(Darwin)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try legacyData.write(to: target, options: options)
        let readBack = try Data(contentsOf: target)
        guard readBack == legacyData, validate(readBack) else { return false }
        try? fm.removeItem(at: legacy)
        return true
    } catch {
        return false
    }
}

/// Migra y limpia los ficheros del almacén principal que pudieran quedar huérfanos en la carpeta privada de la app.
public func migrateLegacyStoreFiles(from legacyDirectory: URL, to targetDirectory: URL) {
    migrateStoreFileIfNeeded(from: legacyDirectory, to: targetDirectory, fileName: "ledger.json") { data in
        (try? JSONDecoder().decode(LedgerState.self, from: data)) != nil
    }
    migrateStoreFileIfNeeded(from: legacyDirectory, to: targetDirectory, fileName: "portfolio.json") { data in
        (try? JSONDecoder().decode(Portfolio.self, from: data)) != nil
    }
    migrateStoreFileIfNeeded(from: legacyDirectory, to: targetDirectory, fileName: "assistant-preferences.json") { data in
        (try? JSONDecoder().decode(AssistantPreferences.self, from: data)) != nil
    }
    migrateStoreFileIfNeeded(from: legacyDirectory, to: targetDirectory, fileName: "pending-moves.json") { data in
        (try? JSONSerialization.jsonObject(with: data)) is [Any]
    }
}
