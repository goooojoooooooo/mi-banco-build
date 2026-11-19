import SwiftUI
import Observation

/// Medidas que cambian en cada fotograma (posición del carrusel, desplazamiento de la lista).
/// Viven aquí, fuera del entorno y del `body` de Inicio: solo las leen modificadores pequeños
/// (indicador del segmentado, paralaje), así que desplazarse no vuelve a evaluar las tarjetas ni las filas.
@MainActor @Observable
final class HomeMotion {
    /// 0 = «Todo», 1 = Revolut… con decimales mientras se arrastra.
    var carouselPosition: CGFloat = 0
    /// Se ha tirado más allá del primer o el último tope (una háptica ligera por vez).
    var carouselOverscrolled = false
    /// Puntos desplazados hacia arriba desde el reposo (0 arriba del todo).
    var listOffset: CGFloat = 0
}

/// Constantes del carrusel: tarjetas de 376 pt en 440 (32 de margen, se ven los vecinos) y 10 entre ellas.
enum CarouselMetrics {
    static let inset: CGFloat = 32
    static let spacing: CGFloat = 10
    static let minHeight: CGFloat = 236
}

/// El título "Tu dinero" se compacta un poco al bajar la lista.
struct TitleCompression: ViewModifier {
    let motion: HomeMotion
    let enabled: Bool

    func body(content: Content) -> some View {
        let t = enabled ? min(max(motion.listOffset / 160, 0), 1) : 0
        content.scaleEffect(1 - 0.14 * t, anchor: .leading)
    }
}

/// El carrusel se queda algo atrás (paralaje), se encoge y se apaga mientras la lista sube por encima.
struct CarouselParallax: ViewModifier {
    let motion: HomeMotion
    let enabled: Bool

    func body(content: Content) -> some View {
        let y = enabled ? max(motion.listOffset, 0) : 0
        content
            .offset(y: y * 0.32)
            .scaleEffect(1 - min(y / 1_400, 0.06), anchor: .top)
            .opacity(1 - min(y / 420, 0.45))
    }
}

/// Degradado negro bajo la barra superior: solo aparece cuando hay contenido pasando por debajo.
struct TopEdgeFade: View {
    let motion: HomeMotion

    var body: some View {
        LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.55), .init(color: .black.opacity(0), location: 1)],
                       startPoint: .top, endPoint: .bottom)
            .opacity(motion.listOffset > 8 ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: motion.listOffset > 8)
            .allowsHitTesting(false)
    }
}
