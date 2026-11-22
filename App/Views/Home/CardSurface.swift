import SwiftUI

/// El material de una tarjeta (nunca cristal): degradado casi negro del banco y, encima, cuatro capas muy contenidas.
/// 1. Canto mecanizado de 1 pt (blanco 30 % → 3 % → 14 %) cuyo ángulo gira con la posición en el carrusel.
/// 2. Brillo diagonal (7,5 % en su franja más intensa) que se desplaza con la posición.
/// 3. Cepillado de 1 px al 1,6 %.
/// 4. Sombra interior abajo, para dar peso.
/// Las capas 1 y 2 se mueven con `visualEffect` (posición en el carrusel), así que arrastrar no vuelve a evaluar
/// ningún `body`. Con Reducir movimiento se quedan quietas.
struct CardSurface: View {
    let material: CardMaterial
    var moves = true

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous) }

    var body: some View {
        shape
            .fill(material.gradient)
            .overlay { BrushedGrain().clipShape(shape) }
            .overlay { sheen.clipShape(shape) }
            .overlay {
                LinearGradient(stops: [.init(color: .clear, location: 0.55), .init(color: .black.opacity(0.22), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .clipShape(shape)
            }
            .overlay { edge }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Franja a 112° sobre un lienzo 2,6 veces más ancho que la tarjeta, como `background-size: 260%`.
    private var sheen: some View {
        let moves = moves
        return LinearGradient(
            stops: [
                .init(color: .white.opacity(0), location: 0.32),
                .init(color: .white.opacity(0.075), location: 0.46),
                .init(color: .white.opacity(0.025), location: 0.54),
                .init(color: .white.opacity(0), location: 0.66),
            ],
            startPoint: UnitPoint(x: 0, y: 0.3), endPoint: UnitPoint(x: 1, y: 0.7))
            .scaleEffect(x: 2.6, y: 1)
            .visualEffect { content, proxy in
                let width = proxy.size.width
                let distance = moves ? CardSurface.distance(proxy) : 0
                return content.offset(x: width * (-0.16 + 0.6 * distance))
            }
    }

    private var edge: some View {
        let moves = moves
        return LinearGradient(
            stops: [
                .init(color: .white.opacity(0.30), location: 0),
                .init(color: .white.opacity(0.06), location: 0.28),
                .init(color: .white.opacity(0.03), location: 0.62),
                .init(color: .white.opacity(0.14), location: 1),
            ],
            startPoint: .top, endPoint: .bottom)
            .scaleEffect(1.8)
            .visualEffect { content, proxy in
                let distance = moves ? CardSurface.distance(proxy) : 0
                return content.rotationEffect(.degrees(Double(-15 - 25 * distance)))
            }
            .mask { shape.strokeBorder(lineWidth: 1) }
    }

    /// Cuántas tarjetas separan esta del sitio de reposo (0 = centrada, 1 = la siguiente a la derecha).
    nonisolated static func distance(_ proxy: GeometryProxy) -> CGFloat {
        let frame = proxy.frame(in: .scrollView(axis: .horizontal))
        let step = proxy.size.width + CarouselMetrics.spacing
        return step > 0 ? (frame.minX - CarouselMetrics.inset) / step : 0
    }
}

/// Cepillado casi invisible: una línea vertical de 1 px cada 3 px. Se dibuja una vez por tamaño.
/// U77: en el hilo principal (`rendersAsynchronously: false`). Con `true`, SwiftUI ejecuta este cierre en
/// `com.apple.SwiftUI.AsyncRenderer`, y en Swift 6 hereda `@MainActor` del `body`: es el sospechoso del cierre intermitente al
/// arrancar (ejecución 44972452792). Coste: el grano se dibuja en el hilo principal (unas decenas de rectángulos por tarjeta).
private struct BrushedGrain: View {
    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            var path = Path()
            var x: CGFloat = 0
            while x < size.width {
                path.addRect(CGRect(x: x, y: 0, width: 1, height: size.height))
                x += 3
            }
            context.fill(path, with: .color(.white.opacity(0.016)))
        }
    }
}
