import Foundation
import UIKit
import UniformTypeIdentifiers
import MiBancoCore

/// Único punto de copia al portapapeles de toda la app: solo local y con caducidad de 3 minutos.
@MainActor
enum Pasteboard {
    static func copy(_ text: String) {
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: text]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(clipboardLifetime)]
        )
    }
}
