import SwiftUI
import UIKit

/// Hoja de compartir del sistema para un fichero o un texto (p. ej. compartir IBAN). Vive dentro de la única
/// hoja de la app (`RootSheet.share`), así que se cierra con el bloqueo y al salir de primer plano.
struct ShareSheet: UIViewControllerRepresentable {
    let item: ShareItem
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let items: [Any] = switch item.payload {
        case .file(let url): [url]
        case .text(let text): [text]
        }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if case .text = item.payload {
            controller.excludedActivityTypes = [.copyToPasteboard]
        }
        controller.completionWithItemsHandler = { _, _, _, _ in onFinish() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
