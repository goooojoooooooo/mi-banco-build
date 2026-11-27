import Foundation

/// Reglas de nombres y limpieza para la caché de logos descargados (`Caches/Logos`),
/// de modo que el nombre del comercio nunca quede en claro en el sistema de archivos.
public enum LogoCachePolicy {
    public static let hashedPrefix = "h_"
    public static let defaultDownloadsEnabled = false
    public static let maxDownloadBytes = 256_000

    /// Construye el nombre base (`h_<sha256-hex>`) a partir del resumen hexadecimal SHA-256.
    public static func fileName(forHashHex hex: String) -> String {
        hashedPrefix + hex.lowercased()
    }

    /// Comprueba si un nombre de archivo de caché sigue el formato moderno con hash (`h_<64 hex>.png|.none`).
    public static func isHashedCacheFile(_ fileName: String) -> Bool {
        let stem: Substring
        if fileName.hasSuffix(".png") {
            stem = fileName.dropLast(4)
        } else if fileName.hasSuffix(".none") {
            stem = fileName.dropLast(5)
        } else {
            return false
        }
        guard stem.hasPrefix(hashedPrefix) else { return false }
        let hex = stem.dropFirst(hashedPrefix.count)
        guard hex.count == 64 else { return false }
        return hex.unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 0x30 && scalar.value <= 0x39) || (scalar.value >= 0x61 && scalar.value <= 0x66)
        }
    }

    /// Devuelve los archivos `.png`/`.none` antiguos (con nombres en claro o formato previo) que deben borrarse.
    public static func legacyFilesToRemove(in fileNames: [String]) -> [String] {
        fileNames.filter { name in
            (name.hasSuffix(".png") || name.hasSuffix(".none")) && !isHashedCacheFile(name)
        }
    }
}
