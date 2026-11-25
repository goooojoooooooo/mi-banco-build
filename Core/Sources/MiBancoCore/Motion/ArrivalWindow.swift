import Foundation

/// Cuánto vale el anuncio de una llegada mientras se espera a que el libro publique su movimiento. El modelo anuncia la
/// llegada y publica el estado un instante después (≈ 0,56 s); si en ese plazo el movimiento no aparece (por ejemplo, un
/// aviso que sustituye a otro y no cambia el número de movimientos), la llegada caduca: un cambio posterior del libro
/// que no tiene nada que ver (borrar un aviso, la siguiente consulta) no puede enseñar minutos después la insignia vieja.
public enum ArrivalWindow {
    /// El plazo a velocidad real, en segundos.
    public static let lifetime: TimeInterval = 2

    /// Si una llegada anunciada en `announcedAt` puede aterrizar ahora. `timeMultiplier` es la cámara lenta de las
    /// grabaciones (1 en la app): el plazo se alarga con ella, como el resto del movimiento.
    public static func isOpen(announcedAt: Date, now: Date, timeMultiplier: Double = 1) -> Bool {
        let elapsed = now.timeIntervalSince(announcedAt)
        return elapsed >= 0 && elapsed < lifetime * max(timeMultiplier, 1)
    }
}
