import SwiftUI

/// D1: el importe de la fila tocada vuela hasta su sitio en el detalle. Es el MISMO importe del detalle (con el ojo
/// cerrado, su máscara: no hay copia con cifras), desplazado: en `progress` 0 está donde estaba el de la fila (`delta`
/// desde su sitio, a la escala `startScale`), y en 1, en su sitio. Por el camino describe un arco hacia arriba de
/// `arc` puntos. Solo transforma (desplazamiento y escala): nada de maquetación.
struct ArcFlight: GeometryEffect {
    var progress: CGFloat
    var delta: CGSize
    var arc: CGFloat
    var startScale: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let p = min(max(progress, 0), 1.2)
        let rest = 1 - p
        // El arco sube pronto y se acaba antes de posarse (m-12): con un arco simétrico, cerca del final el importe
        // aún iba unos 17 pt por encima de su sitio y pisaba la línea de la fecha. Máximo ≈ `arc` hacia p ≈ 0,37.
        let k = min(max(p, 0), 1)
        let lift = arc * 2.5 * sin(.pi * k) * (1 - k)
        let scale = 1 + (startScale - 1) * max(rest, 0)
        // Escala alrededor del centro del importe y luego el desplazamiento.
        var t = CGAffineTransform(translationX: size.width / 2, y: size.height / 2)
        t = t.translatedBy(x: delta.width * rest, y: delta.height * rest - lift)
        t = t.scaledBy(x: scale, y: scale)
        t = t.translatedBy(x: -size.width / 2, y: -size.height / 2)
        return ProjectionTransform(t)
    }
}

/// Las cuentas del vuelo: desde dónde (relativo al sitio del importe en la hoja) y a qué escala sale.
enum FlyInGeometry {
    /// `origin` y `slot` en coordenadas de pantalla. nil si no hay de dónde salir o el sitio aún no se conoce.
    static func start(from origin: CGRect?, to slot: CGRect?) -> (delta: CGSize, scale: CGFloat)? {
        guard let origin, let slot, origin.width > 0, origin.height > 0, slot.width > 0, slot.height > 0 else { return nil }
        let delta = CGSize(width: origin.midX - slot.midX, height: origin.midY - slot.midY)
        // El importe de la fila es más pequeño: sale a la altura de la fila (como mucho al doble o la mitad).
        let scale = min(max(origin.height / slot.height, 0.3), 1)
        return (delta, scale)
    }
}
