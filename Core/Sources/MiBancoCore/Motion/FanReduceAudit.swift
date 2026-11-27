import Foundation

/// Medición pura de opacidades dibujadas durante la apertura del abanico con Reducir movimiento (m-7 punto 9):
/// - `minVisiblePermille`: mínimo de `max(opacidadInicio, opacidadAbanico)` en tantos por mil (0 = fotograma en negro total).
/// - `overlapFrames`: cuántos fotogramas muestreados tienen a la vez Inicio y el abanico por encima del umbral de solape.
public struct FanReduceAudit: Equatable, Sendable {
    public enum Layer: Sendable {
        case backdrop
        case fan
    }

    /// Umbral a partir del cual dos capas superpuestas se leen a la vez (20 %).
    public static let overlapThreshold = 0.20

    /// Opacidad dibujada de Inicio (1 − opacidad del telón negro) y del abanico.
    public private(set) var homeOpacity: Double = 1
    public private(set) var fanOpacity: Double = 0
    /// Mínimo de `max(homeOpacity, fanOpacity)` en tantos por mil (0…1000).
    public private(set) var minVisiblePermille: Int = 1_000
    /// Fotogramas en los que tanto Inicio como el abanico han estado ≥ `overlapThreshold`.
    public private(set) var overlapFrames: Int = 0
    /// Total de muestras válidas registradas durante el paso.
    public private(set) var samples: Int = 0

    public init() {}

    public mutating func record(layer: Layer, opacity: Double) {
        guard opacity.isFinite else { return }
        let clamped = min(max(opacity, 0), 1)
        switch layer {
        case .backdrop:
            homeOpacity = 1 - clamped
        case .fan:
            fanOpacity = clamped
        }
        samples += 1
        let visible = max(homeOpacity, fanOpacity)
        minVisiblePermille = min(minVisiblePermille, Int((visible * 1_000).rounded()))
        if homeOpacity >= Self.overlapThreshold && fanOpacity >= Self.overlapThreshold {
            overlapFrames += 1
        }
    }
}
