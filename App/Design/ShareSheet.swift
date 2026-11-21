import SwiftUI
import UIKit

/// Hoja de compartir del sistema para un fichero. Vive dentro de la única hoja de la app (`RootSheet.share`),
/// así que se cierra con el bloqueo y al salir de primer plano. El fichero temporal se borra al desaparecer.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onFinish() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
