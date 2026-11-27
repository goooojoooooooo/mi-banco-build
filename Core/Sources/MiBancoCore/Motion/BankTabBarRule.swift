import Foundation

/// Cuándo se esconde la barra de pestañas en la pantalla de un banco, según lo que ha subido la hoja (`progress`, 0 = abajo,
/// 1 = acoplada): se esconde al pasar del 5 % y no vuelve hasta bajar del 2 % (histéresis), así un dedo quieto justo en el
/// umbral no la hace parpadear. Valor puro.
public enum BankTabBarRule {
    public static let hideAbove = 0.05
    public static let showBelow = 0.02

    /// `hiddenNow`: la barra está escondida ahora. Un `progress` no finito cuenta como 0 (abajo).
    public static func hides(progress: Double, hiddenNow: Bool) -> Bool {
        let p = progress.isFinite ? min(1, max(0, progress)) : 0
        return p > (hiddenNow ? showBelow : hideAbove)
    }
}
