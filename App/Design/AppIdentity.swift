import Foundation
import MiBancoCore

/// El nombre de la app, en un solo sitio: ninguna vista lo escribe a mano. Sale de Core (`appDisplayName`), el mismo que
/// usa la guía de avisos; `CFBundleDisplayName` de los tres objetivos dice lo mismo (lo comprueba `tools/check_gates.sh`).
enum AppIdentity {
    static let displayName = appDisplayName
}
