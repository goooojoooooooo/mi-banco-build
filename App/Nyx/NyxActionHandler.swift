import Foundation
import UIKit
import MiBancoCore

/// Punto de entrada al abrir la hoja de Nyx (resumen diario, Pregúntame, lista o mensaje concreto).
enum NyxSheetEntry: Equatable, Hashable, Sendable {
    case dailyUpdate
    case ask
    case seen
    case message(String)
}

/// Petición para abrir Presupuestos enfocado en una categoría con el límite sugerido rellenado (diseño §6.8).
struct BudgetPrefillRequest: Equatable, Hashable, Sendable {
    let category: SpendingCategory
    let suggestedCents: Int?
    let token = UUID()
}

/// Acción reversible aplicada dentro de la hoja de Nyx (ventana de «Deshacer» de 5 s).
enum NyxInlineUndoOutcome: Equatable {
    case dismissed(entryID: String, previousStatus: NyxEntryStatus)
    case markedNotMine(entryID: String, movementID: UUID, previousStatus: NyxEntryStatus)
    case mutedMerchant(entryID: String, merchant: String, previousStatus: NyxEntryStatus)
    case turnedOffAlert(entryID: String, previousSettings: AlertSettings, previousStatus: NyxEntryStatus)
}

struct NyxUndoState: Equatable {
    let entryID: String
    let confirmationText: String
    let outcome: NyxInlineUndoOutcome
}

extension NyxDelivery {
    /// Pie pequeño de cada entrada en «Lo que he visto» (diseño §6.7). Sin dígitos.
    var spanishFooter: String {
        switch self {
        case .notification: "Te avisé"
        case .silentNotification: "Te avisé sin sonido"
        case .banner: "Te lo dije en la app"
        case .list: "Solo lo apunté"
        case .viaAvisos: "Te avisó Avisos"
        }
    }
}

/// Helpers de ejecución de acciones de Nyx (abrir apps externas, clasificación de acciones en línea y avisos).
enum NyxActionHandler {
    static let sideStoreURL = URL(string: "sidestore://")
    static let sideStoreFallbackMessage = "Abre SideStore y renueva \(AppIdentity.displayName) desde ahí."

    static func isInline(_ action: NyxAction) -> Bool {
        switch action {
        case .muteMerchant, .markNotMine, .turnOffAlert:
            true
        default:
            false
        }
    }

    @MainActor
    static func openBankApp(_ bank: BankID) async -> String? {
        guard let url = BankApps.url(for: bank), UIApplication.shared.canOpenURL(url) else {
            return "No se pudo abrir \(bank.displayName)."
        }
        let opened = await UIApplication.shared.open(url)
        return opened ? nil : "No se pudo abrir \(bank.displayName)."
    }

    @MainActor
    static func openNotificationSettings() async {
        let primary = URL(string: UIApplication.openNotificationSettingsURLString)
        let fallback = URL(string: UIApplication.openSettingsURLString)
        if let primary, await UIApplication.shared.open(primary) {
            return
        }
        if let fallback {
            _ = await UIApplication.shared.open(fallback)
        }
    }

    @MainActor
    static func openSideStore() async -> String? {
        guard let url = sideStoreURL, UIApplication.shared.canOpenURL(url) else {
            return sideStoreFallbackMessage
        }
        let opened = await UIApplication.shared.open(url)
        return opened ? nil : sideStoreFallbackMessage
    }

    /// Devuelve el título visible de cada acción disponible respetando el ojo cerrado y variantes («Ver el ingreso»).
    static func titles(for available: [NyxAction], in message: NyxMessage, hidden: Bool) -> [String] {
        let allTitles = nyxActionTitles(message, hidden: hidden)
        return available.map { action in
            if let index = message.actions.firstIndex(of: action), index < allTitles.count {
                return allTitles[index]
            }
            return nyxActionTitle(action, hidden: hidden)
        }
    }
}
