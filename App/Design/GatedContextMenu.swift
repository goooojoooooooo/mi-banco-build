import SwiftUI

/// Menú contextual que no sobrevive al bloqueo ni a salir de primer plano (R26). El menú y su vista previa los dibuja
/// el sistema por encima de la raíz de la app, donde `RootView` no puede cerrarlos: mientras la app no esté activa o esté
/// bloqueada (estado VIVO de `PresentationGate`), la fila se reconstruye SIN el menú. Al cambiar la rama cambia la
/// identidad de la vista y el sistema desmonta el menú abierto y su vista previa. SOLO el bloqueo cambia la identidad (R33):
/// el ojo del modo privado no reconstruye las filas. Con el modo privado, la vista previa es solo el nombre: nunca un importe.
private struct GatedContextMenu<Items: View, Preview: View>: ViewModifier {
    let privateTitle: String
    let items: Items
    let preview: Preview

    @Environment(\.presentationGate) private var gate
    @Environment(AppPreferences.self) private var preferences

    func body(content: Content) -> some View {
        if gate?.canPresent == false {
            content
        } else {
            // Una sola rama para el menú: el ojo del modo privado NO cambia la identidad de la fila (no se rehace, no hay dos
            // copias ni se pierde su estado, y el difuminado de cada importe sigue siendo el diseñado). Lo que cambia con el
            // modo privado es solo lo que se dibuja en la vista previa, que se elige dentro del mismo `contextMenu`.
            // Con el ojo abierto se dibuja una vista real (R37), nunca `content` (en SwiftUI no pinta nada en la vista previa).
            content.contextMenu {
                items
            } preview: {
                if preferences.privateMode {
                    Text(privateTitle)
                        .titan(.row)
                        .foregroundStyle(Theme.label)
                        .padding(20)
                        .background(Theme.canvas)
                        .accessibilityIdentifier("menu.vistaPreviaPrivada")
                } else {
                    preview
                        .environment(preferences)
                        .padding(.horizontal, Theme.Space.gutter)
                        .padding(.vertical, 12)
                        .frame(minWidth: 280, minHeight: 64, alignment: .leading)
                        .background(Theme.canvas)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("menu.vistaPrevia")
                }
            }
        }
    }
}

extension View {
    /// `privateTitle`: lo que se ve en la vista previa del menú con el modo privado (sin importes).
    /// `preview`: vista previa real con el ojo abierto (nunca el marcador `content`, R37).
    func gatedContextMenu<Items: View, Preview: View>(
        privateTitle: String,
        @ViewBuilder items: () -> Items,
        @ViewBuilder preview: () -> Preview
    ) -> some View {
        modifier(GatedContextMenu(privateTitle: privateTitle, items: items(), preview: preview()))
    }
}
