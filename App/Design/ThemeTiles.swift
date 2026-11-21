import SwiftUI

extension Theme {
    /// Ficha de icono de 30 pt de las filas de Ajustes (`OptionLabel` y las filas de copia de seguridad).
    static let iconTile = Color(hex: "#232325")
    /// Glifo del icono dentro de esa ficha (no es el contraste de la tarjeta de cuenta, aunque hoy coincidan los valores).
    static let iconGlyph = Color(hex: "#D1D1D6")
    /// Fondo de un campo de texto con el foco en Ajustes.
    static let fieldFill = Color(hex: "#2A2A2D")
    /// Chip y fichas sin elegir de la categoría en la hoja del movimiento (blanco al 10 %).
    static let chipFill = Color.white.opacity(0.10)
    /// Ficha elegida (blanca) y lo que va encima de ella (negro).
    static let tileSelected = Color.white
    static let onTileSelected = Color.black
}
