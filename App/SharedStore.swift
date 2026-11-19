import Foundation
import MiBancoCore

/// Un único sitio donde se decide la carpeta del libro mayor (app e intents).
enum SharedStore {
    enum Location: Sendable { case appGroup, appFolder }

    static let baseGroupID = "group.com.mibanco.shared"

    /// Se resuelve una vez por proceso, en el primer uso (la app o un intent, lo que llegue antes).
    private static let resolved: (directory: URL, location: Location) = resolve()

    static var location: Location { resolved.location }

    static func make() -> FileStore {
        FileStore(directory: resolved.directory)
    }

    /// Prueba los grupos posibles en orden y se queda con el primero que el sistema concede.
    /// Si ninguno existe, usa la carpeta privada de la app a propósito: en el Plan 1 solo la app lee el libro.
    private static func resolve() -> (directory: URL, location: Location) {
        let info = Bundle.main.infoDictionary ?? [:]
        let fileManager = FileManager.default
        for id in candidateGroupIDs(infoDictionary: info, teamID: embeddedTeamID()) {
            if let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: id) {
                migrateIfNeeded(to: url)
                return (url, .appGroup)
            }
        }
        return (URL.applicationSupportDirectory, .appFolder)
    }

    /// Todos los `ALTAppGroups` (el primero, el que elige Core), el id base y el id base con el Team ID.
    static func candidateGroupIDs(infoDictionary: [String: Any], teamID: String?) -> [String] {
        var ids = [resolveAppGroupID(infoDictionary: infoDictionary, fallback: baseGroupID)]
        ids += (infoDictionary["ALTAppGroups"] as? [String]) ?? []
        ids.append(baseGroupID)
        if let teamID, !teamID.isEmpty { ids.append("\(baseGroupID).\(teamID)") }
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    /// Team ID del perfil con el que se firmó la app (`TeamIdentifier` del plist dentro de `embedded.mobileprovision`).
    private static func embeddedTeamID() -> String? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data.subdata(in: start.lowerBound..<end.upperBound), format: nil) as? [String: Any],
              let teams = plist["TeamIdentifier"] as? [String] else { return nil }
        return teams.first
    }

    /// Una sola vez: si el grupo no tiene libro pero la carpeta privada sí, se copia. Nunca se pisa un libro del grupo.
    private static func migrateIfNeeded(to groupDirectory: URL) {
        let fileManager = FileManager.default
        let target = groupDirectory.appendingPathComponent("ledger.json")
        let legacy = URL.applicationSupportDirectory.appendingPathComponent("ledger.json")
        guard !fileManager.fileExists(atPath: target.path), fileManager.fileExists(atPath: legacy.path) else { return }
        try? fileManager.copyItem(at: legacy, to: target)
    }
}
