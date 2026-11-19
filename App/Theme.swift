import SwiftUI
import MiBancoCore

extension Color {
    /// "#RRGGBB" -> Color. Valor inválido = negro.
    init(hex: String) {
        let v = UInt64(hex.drop(while: { $0 == "#" }), radix: 16) ?? 0
        self.init(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }
}

extension BankID {
    /// Color de marca del banco (solo para la barra de la notificación ampliada; la app usa logos y materiales).
    var color: Color { Color(hex: hexColor) }
    /// Nombre corto para tres columnas ("Trade Rep.").
    var shortName: String { self == .tr ? "Trade Rep." : displayName }
    /// Material de su tarjeta.
    var material: CardMaterial {
        switch self {
        case .rev: .revolut
        case .ima: .imagin
        case .tr: .tradeRepublic
        }
    }
}

/// Degradado de 160° de una tarjeta (Titanio): arriba a la izquierda ~8 % más claro. No brilla.
struct CardMaterial: Sendable, Equatable {
    let top: Color
    let middle: Color
    let bottom: Color

    static let all = CardMaterial(top: Color(hex: "#38383B"), middle: Color(hex: "#262628"), bottom: Color(hex: "#1A1A1C"))
    static let revolut = CardMaterial(top: Color(hex: "#30353C"), middle: Color(hex: "#1F2226"), bottom: Color(hex: "#15171A"))
    static let imagin = CardMaterial(top: Color(hex: "#243532"), middle: Color(hex: "#172422"), bottom: Color(hex: "#0F1817"))
    static let tradeRepublic = CardMaterial(top: Color(hex: "#3A3026"), middle: Color(hex: "#271F19"), bottom: Color(hex: "#1A1511"))

    /// 160° en CSS ≈ de arriba-izquierda (algo inclinado) hacia abajo-derecha.
    var gradient: LinearGradient {
        LinearGradient(
            stops: [.init(color: top, location: 0), .init(color: middle, location: 0.4), .init(color: bottom, location: 1)],
            startPoint: UnitPoint(x: 0.33, y: 0), endPoint: UnitPoint(x: 0.67, y: 1))
    }
}

/// Tokens de Titanio, compartidos por la app, la notificación ampliada y la Live Activity.
/// Lienzo negro puro; la elevación se hace con luminosidad, nunca con sombras. El color solo aparece en los logos,
/// en el verde de lo que entra y en el ámbar de lo que avisa. Contraste sobre #000: label 21, label2 8,2, label3 6,4.
enum Theme {
    // MARK: Superficies
    static let canvas = Color.black
    /// Grupos de Avisos y Ajustes.
    static let grouped = Color(hex: "#141416")
    /// Indicador del segmentado sin cristal, fichas con monograma, fondo de pulsación.
    static let raised = Color(hex: "#1C1C1E")
    /// Fondo de la fila recién llegada (se apaga en 1,6 s).
    static let fresh = Color(hex: "#151517")

    // MARK: Texto
    static let label = Color.white
    /// Subtítulos, claves de la hoja. 8,2:1 sobre negro.
    static let label2 = Color(hex: "#A1A1A6")
    /// Metadatos de fila y cabeceras. 6,4:1 sobre negro.
    static let label3 = Color(hex: "#8E8E93")
    /// Texto secundario dentro de las tarjetas (≥ 6,2:1 sobre su parte más clara).
    static let card2 = Color(hex: "#BDBDC2")
    /// card2 con Aumentar contraste.
    static let card2High = Color(hex: "#D1D1D6")
    /// Iconos pasivos y chevrons: solo gráficos, nunca texto.
    static let passive = Color(hex: "#636366")
    /// Barras del gráfico que no son hoy.
    static let barIdle = Color(hex: "#4A4A4E")
    /// Monograma dentro de las fichas sin logo.
    static let monogram = Color(hex: "#C7C7CC")
    static let separator = Color.white.opacity(0.10)

    // MARK: Semánticos
    /// Lo único verde: el dinero que entra.
    static let income = Color(hex: "#30D158")
    /// Solo avisos: "No es mío", subidas de precio, advertencias.
    static let warning = Color(hex: "#FFB340")

    /// Retícula de 4 pt.
    enum Space {
        static let hairline: CGFloat = 2
        static let tight: CGFloat = 4
        static let small: CGFloat = 8
        static let row: CGFloat = 12
        static let gutter: CGFloat = 20
        static let section: CGFloat = 28
    }

    enum Radius {
        /// Hoja de detalle: concéntrica con el dispositivo (56 − 8).
        static let sheet: CGFloat = 48
        static let card: CGFloat = 24
        static let group: CGFloat = 22
        static let logo: CGFloat = 10
        static let logoLarge: CGFloat = 15
        static let field: CGFloat = 10
        /// Barra de la notificación ampliada.
        static let river: CGFloat = 16
    }

    /// Todo el movimiento en un sitio. Muelles para objetos (sin rebote en el texto), curvas de desaceleración para cifras.
    /// Con Reducir movimiento, cada vista sustituye el movimiento por un fundido (`reduceMotion ? fade : motion`).
    enum Motion {
        /// Encajar la tarjeta del carrusel (programático: segmentado, llegada).
        static let cardSettle = Animation.spring(response: 0.46, dampingFraction: 0.74)
        /// Lista que sigue a la tarjeta: fundido de 150 ms.
        static let listFade = Animation.easeOut(duration: 0.15)
        /// Cifras que ruedan al cambiar: desaceleración tipo quartic ease-out, 1,1 s.
        static let roll = Animation.timingCurve(0.25, 1, 0.5, 1, duration: 1.1)
        /// Cifras que cuentan desde 0 la primera vez que se ven.
        static let countUp = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 1.0)
        /// La fila nueva crece y se asienta, sin rebote.
        static let rowSettle = Animation.smooth(duration: 0.42)
        /// Fondo de la fila nueva: se queda y se apaga.
        static let freshHold: Duration = .milliseconds(900)
        static let freshFade = Animation.easeOut(duration: 1.6)
        /// Pulsar: entra al instante (sin animación), sale en 0,3 s.
        static let pressIn = Animation.linear(duration: 0.01)
        static let pressOut = Animation.easeOut(duration: 0.3)
        /// Hoja de detalle y su contenido.
        static let sheet = Animation.spring(response: 0.42, dampingFraction: 0.86)
        /// Ojo: desenfoque + opacidad en 0,35 s.
        static let privacy = Animation.easeOut(duration: 0.35)
        /// Volteo de la tarjeta.
        static let flip = Animation.spring(duration: 0.55, bounce: 0.18)
        /// Montaje de Inicio por capas y entrada escalonada de filas.
        static let assemble = Animation.spring(duration: 0.5, bounce: 0.15)
        static let staggerStep: Double = 0.06
        /// Piezas que entran escalonadas (capas + ~8 filas); el resto aparece ya colocado.
        static let staggerLimit = 12
        /// Trazo de la marca de la app al arrancar o en el bloqueo.
        static let markDraw = Animation.easeInOut(duration: 0.55)
        /// Cambios pequeños de estado (búsqueda, botones que se transforman).
        static let quick = Animation.snappy(duration: 0.25)
        static let morph = Animation.spring(duration: 0.4, bounce: 0.2)
        /// Quitar el bloqueo (solo la salida; la entrada nunca se anima).
        static let unlock = Animation.smooth(duration: 0.3)
        /// Llegada: lo que espera el saldo nuevo para que antes se vea la tarjeta deslizarse.
        static let arrivalLead: Duration = .milliseconds(560)

        // Notificación ampliada (Parte 2 la rediseña; se conservan sus tiempos).
        static let river = Animation.spring(duration: 0.7, bounce: 0.1)
        static let pulseAttack = Animation.easeOut(duration: 0.16)
        static let pulseRelease = Animation.easeOut(duration: 0.65)
        static let alertPreRoll: Duration = .milliseconds(350)
        static let alertLand = Animation.spring(duration: 0.65, bounce: 0.1)
    }

    /// Papeles de texto con estilos del sistema (SF Pro, Dynamic Type, cifras tabulares).
    /// La app usa `.titan(_:)` (tamaños exactos de la especificación); esto lo usan las extensiones.
    enum TextRole {
        case caption, footnote, subheadline, callout, body

        var style: Font.TextStyle {
            switch self {
            case .caption: .caption
            case .footnote: .footnote
            case .subheadline: .subheadline
            case .callout: .callout
            case .body: .body
            }
        }
    }

    static func font(_ role: TextRole, weight: Font.Weight = .regular) -> Font {
        .system(role.style, weight: weight).monospacedDigit()
    }

    /// Tamaño fijo con la fuente del sistema y cifras tabulares (Live Activity y notificación ampliada).
    static func font(size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
}
