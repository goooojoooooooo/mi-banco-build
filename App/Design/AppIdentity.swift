import Foundation

/// El nombre de la app, en un solo sitio: ninguna vista lo escribe a mano. El cambio de nombre en el paquete
/// (`CFBundleDisplayName`, textos sueltos) es un paso aparte; mientras tanto, esta constante manda dentro de la app.
enum AppIdentity {
    static let displayName = "Onyx"
}
