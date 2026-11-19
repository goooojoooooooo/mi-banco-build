import SwiftUI

/// Botón que se hunde al tocar (no al soltar): escala 0,97 al instante, vuelve en 0,3 s.
/// Con Reducir movimiento, solo baja la opacidad.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
            .animation(configuration.isPressed ? Theme.Motion.pressIn : Theme.Motion.pressOut, value: configuration.isPressed)
    }
}

/// Fila a todo lo ancho: al tocar, fondo #141416 y escala 0,985 al instante; vuelve en 0,3 s. Sin háptica.
struct RowPressStyle: ButtonStyle {
    var background = Theme.grouped
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .background(background.opacity(configuration.isPressed ? 1 : 0))
            .animation(configuration.isPressed ? Theme.Motion.pressIn : Theme.Motion.pressOut, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

extension ButtonStyle where Self == RowPressStyle {
    static var row: RowPressStyle { RowPressStyle() }
}
