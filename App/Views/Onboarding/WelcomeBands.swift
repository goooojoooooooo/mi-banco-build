import SwiftUI

/// El barrido de titanio de la primera vez (momento 11 aprobado): tres líneas finas cruzan la pantalla en diagonal, una
/// tras otra (520 ms, 70 ms entre ellas), y después se ensanchan hasta ser bandas tenues de titanio (620 ms, 60 ms entre
/// ellas) que se quedan de fondo. Solo se animan escala y opacidad (cada banda es un rectángulo girado 45°). Se juega una
/// vez, cuando la bienvenida queda a la vista (`active`). Con Reducir movimiento no hay barrido: las bandas tenues aparecen con un fundido. Con Bajo consumo,
/// igual que siempre (no hay brillos ni desenfoques). Es un fondo: no recibe toques ni existe para VoiceOver.
struct WelcomeBands: View {
    /// El barrido empieza cuando esto pasa a ser cierto (la bienvenida ya está a la vista: sin bloqueo ni arranque encima).
    var active = true

    @Environment(\.motion) private var motion
    @State private var traced = false
    @State private var widened = false

    /// Altura del centro de cada línea (fracción del alto) y su orden de salida, como en la maqueta.
    private static let centers: [CGFloat] = [0.50, 0.61, 0.40]
    /// Grosor final de cada banda, medido en perpendicular.
    private static let bandWidth: CGFloat = 150

    var body: some View {
        GeometryReader { geo in
            let length = hypot(geo.size.width + 120, geo.size.width + 120)
            ZStack {
                ForEach(Self.centers.indices, id: \.self) { index in
                    Rectangle()
                        .fill(LinearGradient(colors: [Color(hex: "#F3F4F6"), Color(hex: "#9DA2AA"), Color(hex: "#2A2B2E")],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: length, height: 1)
                        // Se traza de abajo a la izquierda hacia arriba a la derecha.
                        .scaleEffect(x: traced ? 1 : 0, y: 1, anchor: .leading)
                        .animation(traceAnimation(index), value: traced)
                        // Y se ensancha hasta ser una banda tenue.
                        .scaleEffect(x: 1, y: widened ? Self.bandWidth : 1)
                        .animation(widenAnimation(index), value: widened)
                        // La luz baja ANTES de que la banda se ensanche del todo: una banda ancha nunca pasa por el
                        // plateado casi blanco detrás del texto (ojo de diseño 18.3: como mucho ~55 % del brillo de antes).
                        .opacity(widened ? 0.16 : 1)
                        .animation(dimAnimation(index), value: widened)
                        .rotationEffect(.degrees(-45))
                        .position(x: geo.size.width / 2, y: geo.size.height * Self.centers[index])
                }
            }
            .opacity(traced ? 1 : 0)
            .animation(motion.reduce ? motion.fade : nil, value: traced)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { if active { play() } }
        .onChange(of: active) { _, now in if now { play() } }
    }

    private func play() {
        traced = true
        widened = true
    }

    /// Las líneas salen en cuanto la bienvenida queda a la vista, sin pausa vacía (ojo de diseño 18.2).
    private static let traceStart = 0.06
    private static let widenStart = traceStart + 0.56

    private func traceAnimation(_ index: Int) -> Animation? {
        guard !motion.reduce else { return nil }
        return .easeInOut(duration: motion.seconds(0.52)).delay(motion.seconds(Self.traceStart + 0.07 * Double(index)))
    }

    private func widenAnimation(_ index: Int) -> Animation? {
        guard !motion.reduce else { return nil }
        return .easeInOut(duration: motion.seconds(0.62)).delay(motion.seconds(Self.widenStart + 0.06 * Double(index)))
    }

    /// La luz se apaga en la primera mitad del ensanche, frenando: cuando la banda es ancha ya es tenue.
    private func dimAnimation(_ index: Int) -> Animation? {
        guard !motion.reduce else { return nil }
        return .easeOut(duration: motion.seconds(0.34)).delay(motion.seconds(Self.widenStart + 0.06 * Double(index)))
    }
}
