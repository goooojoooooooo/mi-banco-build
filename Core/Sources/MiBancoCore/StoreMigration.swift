import Foundation

/// Etiqueta del archivo de respaldo protegido que se crea junto al destino cuando el origen heredado
/// en `Application Support` es más nuevo y distinto que el destino del App Group (I-1: cero pérdida de datos).
public let storeMigrationRescueBackupTag = ".antes-de-rescate-"

/// Migra un fichero del almacén desde la carpeta heredada (`Application Support`) al contenedor del App Group
/// y elimina el origen huérfano SOLO cuando no puede perderse ningún dato:
/// - Si el destino no existe: copia atómicamente con protección, verifica lectura y validación, y borra el origen.
/// - Si el destino ya existe y es válido:
///   - si origen y destino son idénticos byte a byte, borra el origen;
///   - si el origen es igual de antiguo o más viejo (`<=`) que el destino, borra el origen sin pisar el destino;
///   - si el origen es más nuevo y distinto y pasa la validación, aparta el destino antiguo sin borrarlo en un
///     archivo de respaldo protegido (`<nombre>.antes-de-rescate-<timestamp>.bak`), promueve atómicamente el origen
///     al destino, verifica lectura/validación de ambos y solo entonces borra el origen;
///   - si el origen es más nuevo pero está corrupto (o si el destino está corrupto o faltan fechas), no sobrescribe
///     el destino ni borra el origen.
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
        return reconcileExistingTarget(
            legacy: legacy,
            target: target,
            targetDirectory: targetDirectory,
            fileName: fileName,
            validate: validate
        )
    }

    guard let legacyData = try? Data(contentsOf: legacy), validate(legacyData) else { return false }
    guard writeProtectedAndVerify(legacyData, to: target, directory: targetDirectory, validate: validate) else {
        return false
    }
    try? fm.removeItem(at: legacy)
    return true
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
        (try? decodePendingMovesThrowing(data)) != nil
    }
}

private func reconcileExistingTarget(
    legacy: URL,
    target: URL,
    targetDirectory: URL,
    fileName: String,
    validate: (Data) -> Bool
) -> Bool {
    let fm = FileManager.default
    guard let targetData = try? Data(contentsOf: target), validate(targetData) else { return false }
    guard let legacyData = try? Data(contentsOf: legacy) else { return false }

    if legacyData == targetData {
        try? fm.removeItem(at: legacy)
        return true
    }

    guard let legacyDate = fileModificationDate(of: legacy),
          let targetDate = fileModificationDate(of: target) else {
        return false
    }

    if legacyDate <= targetDate {
        try? fm.removeItem(at: legacy)
        return true
    }

    // El origen en Application Support es más nuevo y distinto: si está corrupto no pisamos destino ni borramos origen.
    guard validate(legacyData) else { return false }

    // Apartamos el destino antiguo en un respaldo protegido verificado antes de promover el más nuevo.
    let backupURL = rescueBackupURL(in: targetDirectory, fileName: fileName, targetDate: targetDate)
    guard writeProtectedAndVerify(targetData, to: backupURL, directory: targetDirectory, validate: validate) else {
        return false
    }
    guard writeProtectedAndVerify(legacyData, to: target, directory: targetDirectory, validate: validate) else {
        return false
    }
    try? fm.removeItem(at: legacy)
    return true
}

private func writeProtectedAndVerify(
    _ data: Data,
    to destination: URL,
    directory: URL,
    validate: (Data) -> Bool
) -> Bool {
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var options: Data.WritingOptions = [.atomic]
        #if canImport(Darwin)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try data.write(to: destination, options: options)
        let readBack = try Data(contentsOf: destination)
        return readBack == data && validate(readBack)
    } catch {
        return false
    }
}

private func fileModificationDate(of url: URL) -> Date? {
    (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
}

private func rescueBackupURL(in directory: URL, fileName: String, targetDate: Date) -> URL {
    let stamp = rescueUTCTimestamp(targetDate)
    let fm = FileManager.default
    var candidate = directory.appendingPathComponent("\(fileName)\(storeMigrationRescueBackupTag)\(stamp).bak")
    var suffix = 2
    while fm.fileExists(atPath: candidate.path) {
        candidate = directory.appendingPathComponent("\(fileName)\(storeMigrationRescueBackupTag)\(stamp)-\(suffix).bak")
        suffix += 1
    }
    return candidate
}

private func rescueUTCTimestamp(_ date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    func two(_ n: Int?) -> String {
        let v = n ?? 0
        return v < 10 ? "0\(v)" : "\(v)"
    }
    let year = max(0, c.year ?? 1970)
    let yearText = year < 10 ? "000\(year)" : year < 100 ? "00\(year)" : year < 1000 ? "0\(year)" : "\(year)"
    return "\(yearText)\(two(c.month))\(two(c.day))-\(two(c.hour))\(two(c.minute))\(two(c.second))"
}
