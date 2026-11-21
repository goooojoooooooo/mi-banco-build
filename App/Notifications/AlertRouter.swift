import Foundation
import Observation

/// Adónde lleva un aviso tocado. Se lee del `userInfo` (claves `route` y `movementID`, que pone la app al publicarlo).
struct AlertRoute: Equatable, Sendable {
    enum Destination: Equatable, Sendable { case home, alerts, briefing }
    let destination: Destination
    /// Si el aviso habla de un movimiento, se abre su hoja.
    let movementID: UUID?
    /// Cada toque es una petición nueva aunque repita destino.
    let token = UUID()

    static func == (a: AlertRoute, b: AlertRoute) -> Bool { a.token == b.token }

    init(destination: Destination, movementID: UUID?) {
        self.destination = destination
        self.movementID = movementID
    }

    /// Avisos de movimiento (`MOVEMENT`): Inicio con su hoja. Aviso de la mañana (`BRIEFING`): Inicio (y regla normal del
    /// resumen). Avisos de ideas y programados (`INSIGHT`): la pestaña Avisos.
    init(userInfo: [AnyHashable: Any]) {
        let id = (userInfo[Keys.movementID] as? String).flatMap(UUID.init(uuidString:))
        let route = userInfo[Keys.route] as? String
        let destination: Destination
        switch route {
        case Keys.movementRoute: destination = .home
        case Keys.briefingRoute: destination = .briefing
        default: destination = .alerts
        }
        self.init(destination: destination, movementID: id)
    }

    enum Keys {
        static let route = "route"
        static let movementID = "movementID"
        static let insightID = "insightID"
        static let movementRoute = "movement"
        static let insightRoute = "insight"
        static let briefingRoute = "briefing"
    }
}

/// Petición pendiente de abrir algo desde un aviso. La escribe `ForegroundPresenter` (delegado de notificaciones)
/// y la consume `RootView` en cuanto la app está desbloqueada.
@MainActor @Observable
final class AlertRouter {
    static let shared = AlertRouter()
    var pending: AlertRoute?

    private init() {}

    func open(_ route: AlertRoute) {
        pending = route
    }
}

/// Avisos de atención (ámbar) que ya se han visto en la pestaña: la insignia cuenta los demás.
/// Se guardan en UserDefaults (como mucho 200 ids); en la demo, solo en memoria.
@MainActor @Observable
final class SeenInsights {
    private static let key = "seenWarningInsightIDs"
    private static let limit = 200
    private(set) var ids: [String]

    init() {
        #if DEBUG
        if DemoMode.isActive {
            ids = []
            return
        }
        #endif
        ids = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
    }

    func unseenCount(of warnings: [String]) -> Int {
        guard !warnings.isEmpty else { return 0 }
        let seen = Set(ids)
        return warnings.filter { !seen.contains($0) }.count
    }

    func markSeen(_ warnings: [String]) {
        let seen = Set(ids)
        let new = warnings.filter { !seen.contains($0) }
        guard !new.isEmpty else { return }
        ids = Array((ids + new).suffix(Self.limit))
        #if DEBUG
        if DemoMode.isActive { return }
        #endif
        UserDefaults.standard.set(ids, forKey: Self.key)
    }
}
