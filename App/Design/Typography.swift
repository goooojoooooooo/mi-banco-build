import SwiftUI

/// Escala tipográfica de Titanio: SF Pro (fuente del sistema), cifras tabulares, y cada tamaño escala con
/// Dynamic Type respecto a su estilo de texto. Se aplica con `.titan(_:)`.
enum TitanFont {
    /// 34 bold: título grande (Avisos, Ajustes).
    case largeTitle
    /// 30 bold: "Tu dinero".
    case homeTitle
    /// 24 semibold: resumen de 7 días.
    case week
    /// 20 semibold: comercio en la hoja.
    case sheetTitle
    /// 17 semibold: nombre de la tarjeta, total al pie de una tarjeta.
    case cardTitle
    /// 17 medium: comercio e importe de una fila.
    case row
    /// 16 semibold: saldo de cada banco en la tarjeta «Todo».
    case cardBalance
    /// 16 medium: opción de una lista agrupada.
    case option
    /// 16 regular: cuerpo.
    case body
    /// 15 regular: textos de apoyo.
    case callout
    /// 14 regular: subtítulo de fila, frase del ritmo.
    case subtitle
    /// 13 regular: metadatos, pies.
    case meta
    /// 13 semibold: cabeceras de sección.
    case header
    /// 12 regular / medium: lo más pequeño (etiquetas de barras, "estimado").
    case caption
    case captionStrong

    var size: CGFloat {
        switch self {
        case .largeTitle: 34
        case .homeTitle: 30
        case .week: 24
        case .sheetTitle: 20
        case .cardTitle, .row: 17
        case .cardBalance, .option, .body: 16
        case .callout: 15
        case .subtitle: 14
        case .meta, .header: 13
        case .caption, .captionStrong: 12
        }
    }

    var weight: Font.Weight {
        switch self {
        case .largeTitle, .homeTitle: .bold
        case .week, .sheetTitle, .cardTitle, .cardBalance, .header: .semibold
        case .row, .option, .captionStrong: .medium
        case .body, .callout, .subtitle, .meta, .caption: .regular
        }
    }

    var textStyle: Font.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .homeTitle: .title
        case .week: .title2
        case .sheetTitle: .title3
        case .cardTitle, .row: .body
        case .cardBalance, .option, .body: .callout
        case .callout: .callout
        case .subtitle: .subheadline
        case .meta, .header: .footnote
        case .caption, .captionStrong: .caption
        }
    }

    /// Interletraje en puntos (−0,01 em en filas, −0,02 em en títulos).
    var tracking: CGFloat {
        switch self {
        case .largeTitle, .homeTitle, .week: -size * 0.02
        case .sheetTitle, .cardTitle, .row, .cardBalance, .option: -size * 0.01
        default: 0
        }
    }
}

private struct TitanFontModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let style: TitanFont

    init(_ style: TitanFont) {
        self.style = style
        _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.textStyle)
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: style.weight))
            .tracking(style.tracking * size / style.size)
            .monospacedDigit()
    }
}

extension View {
    func titan(_ style: TitanFont) -> some View { modifier(TitanFontModifier(style)) }
}
