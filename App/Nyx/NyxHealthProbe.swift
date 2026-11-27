import Foundation
import UserNotifications
import MiBancoCore

/// Lee el estado real de salud de la app en iOS (permiso de notificaciones y caducidad del perfil firmado).
/// Todo local, sin red y sin registros.
enum NyxHealthProbe {
    static func current() async -> NyxAppHealth {
        #if DEBUG
        if DemoMode.isActive {
            return DemoMode.nyxHealth
        }
        #endif
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let allowed: Bool? = switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: true
        case .denied: false
        case .notDetermined: nil
        @unknown default: nil
        }
        return NyxAppHealth(
            notificationsAllowed: allowed,
            appExpiresAt: embeddedProvisioningExpiry()
        )
    }

    /// Fecha `ExpirationDate` del perfil `embedded.mobileprovision` del paquete, o nil si falta o no se puede leer.
    static func embeddedProvisioningExpiry() -> Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return provisioningExpiry(fromEmbeddedProfile: data)
    }
}
