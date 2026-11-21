import SwiftUI

/// Menú contextual que no sobrevive al bloqueo ni a salir de primer plano (R26). El menú y su vista previa los dibuja
/// el sistema por encima de la raíz de la app, donde `RootView` no puede cerrarlos: mientras la app no esté activa o esté
/// bloqueada (estado VIVO de `PresentationGate`), la fila se reconstruye SIN el menú. Al cambiar la rama cambia la
/// identidad de la vista y el sistema desmonta el menú abierto y su vista previa.
/// Con el modo privado, la vista previa que levanta el sistema es solo el nombre: nunca un importe.
private struct GatedContextMenu<Items: View>: ViewModifier {
    let privateTitle: String
    let items: Items

    @Environment(\.presentationGate) private var gate
    @Environment(AppPreferences.self) private var preferences

    func body(content: Content) -> some View {
        if gate?.canPresent == false {
            content
        } else if preferences.privateMode {
            content.contextMenu {
                items
            } preview: {
                Text(privateTitle)
                    .titan(.row)
                    .foregroundStyle(Theme.label)
                    .padding(20)
                    .background(Theme.canvas)
            }
        } else {
            content.contextMenu { items }
        }
    }
}

extension View {
    /// `privateTitle`: lo que se ve en la vista previa del menú con el modo privado (sin importes).
    func gatedContextMenu<Items: View>(privateTitle: String, @ViewBuilder items: () -> Items) -> some View {
        modifier(GatedContextMenu(privateTitle: privateTitle, items: items()))
    }
}
