import SwiftUI

/// Botón de cristal que reacciona: se hunde a 0,88 con el muelle `pressIn` y, al soltar, rebota con `release` mientras
/// se aclara un instante. El cristal queda en el fondo del botón, nunca como cristal interactivo en la etiqueta.
/// Con Reducir movimiento no hay escala: solo baja la opacidad. La etiqueta pone su `.contentShape` (≥ 44 pt).
struct GlassPressStyle: ButtonStyle {
    @Environment(\.motion) private var motion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !motion.reduce ? 0.88 : 1)
            .brightness(configuration.isPressed && !motion.reduce ? 0.12 : 0)
            .opacity(configuration.isPressed && motion.reduce ? 0.7 : 1)
            .animation(configuration.isPressed ? motion.animation(.pressIn) : motion.animation(.release),
                       value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GlassPressStyle {
    static var glassPress: GlassPressStyle { GlassPressStyle() }
}
