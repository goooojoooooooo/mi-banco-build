import SwiftUI

/// La ola del icono (path SVG "M4 16c3-6 5-6 8-2s5 4 8-2" en una caja de 24).
struct WaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let ox = rect.midX - 12 * s
        let oy = rect.midY - 12 * s
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        var path = Path()
        path.move(to: p(4, 16))
        path.addCurve(to: p(12, 14), control1: p(7, 10), control2: p(9, 10))
        path.addCurve(to: p(20, 12), control1: p(15, 18), control2: p(17, 18))
        return path
    }
}
