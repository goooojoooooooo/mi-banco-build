import SwiftUI

/// Botón que se hunde al tocar (no al soltar): escala 0,97 al instante, vuelve en 0,3 s.
/// Con Reducir movimiento (de `\.motion`: también el forzado al grabar), solo baja la opacidad. La vuelta sigue la
/// cámara lenta de las grabaciones.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    @Environment(\.motion) private var motion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !motion.reduce ? scale : 1)
            .opacity(configuration.isPressed && motion.reduce ? 0.7 : 1)
            .animation(configuration.isPressed ? Theme.Motion.pressIn : motion.pressOut, value: configuration.isPressed)
    }
}

/// Fila a todo lo ancho: al tocar, fondo #141416 y escala 0,985 al instante; vuelve en 0,3 s. Sin háptica.
struct RowPressStyle: ButtonStyle {
    var background = Theme.grouped
    @Environment(\.motion) private var motion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !motion.reduce ? 0.985 : 1)
            .background(background.opacity(configuration.isPressed ? 1 : 0))
            .animation(configuration.isPressed ? Theme.Motion.pressIn : motion.pressOut, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

extension ButtonStyle where Self == RowPressStyle {
    static var row: RowPressStyle { RowPressStyle() }
}
