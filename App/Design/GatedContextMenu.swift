import SwiftUI

/// Menú contextual que no sobrevive al bloqueo ni a salir de primer plano (R26). El menú y su vista previa los dibuja
/// el sistema por encima de la raíz de la app, donde `RootView` no puede cerrarlos: mientras la app no esté activa o esté
/// bloqueada (estado VIVO de `PresentationGate`), la fila se reconstruye SIN el menú. Al cambiar la rama cambia la
/// identidad de la vista y el sistema desmonta el menú abierto y su vista previa. SOLO el bloqueo cambia la identidad (R33):
/// el ojo del modo privado no reconstruye las filas. Con el modo privado, la vista previa es solo el nombre: nunca un importe.
private struct GatedContextMenu<Items: View>: ViewModifier {
    let privateTitle: String
    let items: Items

    @Environment(\.presentationGate) private var gate
    @Environment(AppPreferences.self) private var preferences

    func body(content: Content) -> some View {
        if gate?.canPresent == false {
            content
        } else {
            // Una sola rama para el menú: el ojo del modo privado NO cambia la identidad de la fila (no se rehace, no hay dos
            // copias ni se pierde su estado, y el difuminado de cada importe sigue siendo el diseñado). Lo que cambia con el
            // modo privado es solo lo que se dibuja en la vista previa, que se elige dentro del mismo `contextMenu`.
            content.contextMenu {
                items
            } preview: {
                if preferences.privateMode {
                    Text(privateTitle)
                        .titan(.row)
                        .foregroundStyle(Theme.label)
                        .padding(20)
                        .background(Theme.canvas)
                } else {
                    content
                }
            }
        }
    }
}

extension View {
    /// `privateTitle`: lo que se ve en la vista previa del menú con el modo privado (sin importes).
    func gatedContextMenu<Items: View>(privateTitle: String, @ViewBuilder items: () -> Items) -> some View {
        modifier(GatedContextMenu(privateTitle: privateTitle, items: items()))
    }
}
