import SwiftUI

/// Los tiempos del arranque del prototipo para la marca, en milisegundos (nivel Equilibrado): 0–560 se traza el canto;
/// 90–730 la ola con cabeza de luz y halo; 760–1280 el halo se apaga; 600–1030 la cruza un brillo.
struct MarkTimeline: Equatable {
    var drawn: CGFloat
    var edge: CGFloat
    var glow: CGFloat
    var sheen: CGFloat?
    var head: Bool

    static let totalMilliseconds = 1_280.0

    static func at(_ ms: Double) -> MarkTimeline {
        let edge = easeOut.value(clamp(ms / 560))
        let k = clamp((ms - 90) / 640)
        let drawn = draw.value(k)
        var glow = 0.0
        if ms < 730 {
            glow = 0.85 * min(1, k * 2)
        } else if ms >= 760 {
            glow = 0.85 * (1 - easeOut.value(clamp((ms - 760) / 520)))
        } else {
            glow = 0.85
        }
        let s = clamp((ms - 600) / 430)
        return MarkTimeline(
            drawn: CGFloat(drawn), edge: CGFloat(edge), glow: CGFloat(glow),
            sheen: s > 0 && s < 1 ? CGFloat(inOut.value(s)) : nil,
            head: k > 0 && k < 1)
    }

    private static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    private static let easeOut = CubicBezier(0.22, 1, 0.36, 1)
    private static let draw = CubicBezier(0.45, 0.05, 0.2, 1)
    private static let inOut = CubicBezier(0.77, 0, 0.175, 1)
}

/// Curva cúbica de Bézier como las de CSS (el prototipo usa estas).
struct CubicBezier: Equatable {
    let x1, y1, x2, y2: Double

    init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
    }

    func value(_ t: Double) -> Double {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        func coordinate(_ u: Double, _ a: Double, _ b: Double) -> Double {
            3 * (1 - u) * (1 - u) * u * a + 3 * (1 - u) * u * u * b + u * u * u
        }
        // Se busca el parámetro u con x(u) = t por bisección.
        var lo = 0.0, hi = 1.0, u = t
        for _ in 0..<24 {
            u = (lo + hi) / 2
            if coordinate(u, x1, x2) < t { lo = u } else { hi = u }
        }
        return coordinate(u, y1, y2)
    }
}

/// La marca dibujándose con luz (la del arranque): canto, ola con cabeza de luz y halo, y un brillo que la cruza.
/// Cada vez que `replay` cambia vuelve a empezar. Con Reducir movimiento aparece ya dibujada con un fundido.
/// Una sola `TimelineView` (en pausa al terminar) sobre `AppMark`, que va en una sola capa.
struct MarkReveal: View {
    var size: CGFloat = 108
    var replay = 0

    @Environment(\.motion) private var motion
    @State private var start = Date()
    @State private var finished = false
    @State private var shown = false

    var body: some View {
        Group {
            if motion.reduce {
                AppMark(size: size)
                    .opacity(shown ? 1 : 0)
            } else {
                TimelineView(.animation(paused: finished)) { context in
                    let ms = finished
                        ? MarkTimeline.totalMilliseconds
                        : context.date.timeIntervalSince(start) * 1000 / max(motion.seconds(1), 0.01)
                    let state = MarkTimeline.at(ms)
                    AppMark(
                        size: size, drawn: state.drawn, edge: state.edge,
                        glow: motion.richEffects ? state.glow : 0,
                        sheen: motion.richEffects ? state.sheen : nil, head: motion.richEffects && state.head)
                }
            }
        }
        .task(id: replay) {
            start = Date()
            finished = false
            if motion.reduce {
                shown = false
                withAnimation(motion.fade) { shown = true }
                return
            }
            try? await Task.sleep(for: .seconds(motion.seconds(MarkTimeline.totalMilliseconds / 1000) + 0.1))
            guard !Task.isCancelled else { return }
            finished = true
        }
    }
}
