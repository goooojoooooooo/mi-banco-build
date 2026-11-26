import SwiftUI

/// Colores de la marca (los del prototipo de movimiento): cuerpo negro, canto de titanio y ola de titanio.
enum MarkPalette {
    /// Cuerpo: #18181B arriba, #070708 al 55 %, negro abajo.
    static let body = LinearGradient(
        stops: [.init(color: Color(hex: "#18181B"), location: 0),
                .init(color: Color(hex: "#070708"), location: 0.55),
                .init(color: .black, location: 1)],
        startPoint: .top, endPoint: .bottom)

    /// Canto fino de luz: blanco 85 % -> plata 30 % -> gris 18 % -> claro 65 %, en diagonal.
    static let edge = LinearGradient(
        stops: [.init(color: Color.white.opacity(0.85), location: 0),
                .init(color: Color(hex: "#A9ADB3").opacity(0.30), location: 0.32),
                .init(color: Color(hex: "#6B6F75").opacity(0.18), location: 0.68),
                .init(color: Color(hex: "#E9EBEE").opacity(0.65), location: 1)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Ola de titanio. Los puntos son relativos a la caja de 24 de `WaveShape`, ajustados a la caja real de la ola
    /// (x 4…20, y ≈ 11,2…16,8): equivale al degradado (0,0) → (1; 0,35) de su caja en el prototipo.
    static let wave = LinearGradient(
        gradient: waveGradient, startPoint: waveStart, endPoint: waveEnd)

    /// Los colores y los extremos de la ola por separado: las piezas del arranque la dibujan en un `Canvas`.
    static var waveGradient: Gradient {
        Gradient(stops: [
            .init(color: Color(hex: "#FFFFFF"), location: 0),
            .init(color: Color(hex: "#D7DADF"), location: 0.45),
            .init(color: Color(hex: "#9DA2AA"), location: 0.75),
            .init(color: Color(hex: "#F3F4F6"), location: 1)])
    }
    static let waveStart = UnitPoint(x: 4 / 24, y: 11.2 / 24)
    static let waveEnd = UnitPoint(x: 20 / 24, y: 13.16 / 24)
}

/// La marca de la app: pieza negra con su canto de titanio y la ola. Todos los parámetros van de 0 a 1:
/// `drawn` traza la ola, `edge` traza el canto, `glow` es la opacidad del halo de la ola, `sheen` es la posición del
/// brillo que la cruza (nil = sin brillo) y `head` pone la cabeza de luz en la punta del trazo mientras se dibuja.
/// Con los valores por defecto es la marca terminada. Se compone en una sola capa (`drawingGroup`).
struct AppMark: View {
    var size: CGFloat = 64
    var drawn: CGFloat = 1
    var edge: CGFloat = 1
    var glow: CGFloat = 0
    var sheen: CGFloat? = nil
    var head = false
    /// El cuerpo de la pieza llegando (arranque en piezas): su opacidad y su escala. El canto y la ola no cambian.
    var bodyOpacity: CGFloat = 1
    var bodyScale: CGFloat = 1

    var body: some View {
        // Todo se mide en la caja de 120 del prototipo.
        let u = size / 120
        let shape = RoundedRectangle(cornerRadius: 31 * u, style: .continuous)
        let waveBox = CGRect(x: 21.6 * u, y: 15.2 * u, width: 76.8 * u, height: 76.8 * u)
        let progress = min(max(drawn, 0), 1)

        ZStack(alignment: .topLeading) {
            shape.fill(MarkPalette.body)
                .opacity(min(max(bodyOpacity, 0), 1))
                .scaleEffect(bodyScale)
            RoundedRectangle(cornerRadius: 30.4 * u, style: .continuous)
                .inset(by: 0.65 * u)
                .trim(from: 0, to: min(max(edge, 0), 1))
                .stroke(MarkPalette.edge, style: StrokeStyle(lineWidth: 1.3 * u, lineCap: .round))
            if glow > 0 {
                // Copia desenfocada de la ola: el desenfoque es fijo, solo cambia su opacidad.
                WaveShape()
                    .trim(from: 0, to: progress)
                    .stroke(.white, style: StrokeStyle(lineWidth: 2.6 * 3.2 * u, lineCap: .round, lineJoin: .round))
                    .frame(width: waveBox.width, height: waveBox.height)
                    .blur(radius: size * 0.03)
                    .opacity(min(glow, 1))
                    .offset(x: waveBox.minX, y: waveBox.minY)
            }
            WaveShape()
                .trim(from: 0, to: progress)
                .stroke(MarkPalette.wave, style: StrokeStyle(lineWidth: 1.9 * 3.2 * u, lineCap: .round, lineJoin: .round))
                .frame(width: waveBox.width, height: waveBox.height)
                .offset(x: waveBox.minX, y: waveBox.minY)
            if head, progress > 0, progress < 1 {
                let tip = WaveShape().path(in: CGRect(origin: .zero, size: waveBox.size))
                    .trimmedPath(from: 0, to: progress).currentPoint ?? .zero
                // Aparece en el primer 8 % del trazo y se apaga en el último 12 %.
                let visible = progress < 0.08 ? progress / 0.08 : (progress > 0.88 ? (1 - progress) / 0.12 : 1)
                ZStack {
                    Circle().fill(.white).frame(width: 3.2 * 3.2 * u, height: 3.2 * 3.2 * u).blur(radius: size * 0.03)
                    Circle().fill(.white).frame(width: 1.4 * 3.2 * u, height: 1.4 * 3.2 * u)
                }
                .opacity(visible)
                .position(x: waveBox.minX + tip.x, y: waveBox.minY + tip.y)
            }
            if let sheen {
                // Banda blanca de 22° (0 → 32 % → 0) que cruza la pieza; recortada a su forma.
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(LinearGradient(colors: [.white.opacity(0), .white.opacity(0.32), .white.opacity(0)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: 34 * u, height: 200 * u)
                        .position(x: (-103 + 250 * min(max(sheen, 0), 1)) * u, y: 60 * u)
                }
                .frame(width: size, height: size)
                .rotationEffect(.degrees(22))
                .clipShape(shape)
            }
        }
        .frame(width: size, height: size, alignment: .topLeading)
        .drawingGroup()
        .accessibilityHidden(true)
    }
}

/// ✓ que se traza (guardar un saldo, enviar el aviso de prueba, borrar).
struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.53))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.76))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.84, y: rect.minY + rect.height * 0.26))
        return path
    }
}

/// Un ✓ que se dibuja en 0,35 s cuando aparece (con Reducir movimiento, aparece entero). Lee `\.motion`: obedece la
/// intensidad, Reducir movimiento (también el forzado al grabar) y la cámara lenta.
struct DrawnCheck: View {
    var lineWidth: CGFloat = 2.2
    var color: Color = Theme.label
    @State private var progress: CGFloat = 0
    @Environment(\.motion) private var motion

    var body: some View {
        CheckShape()
            .trim(from: 0, to: progress)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .onAppear {
                if motion.reduce {
                    progress = 1
                } else {
                    withAnimation(.easeOut(duration: motion.seconds(0.35)).delay(motion.seconds(0.05))) { progress = 1 }
                }
            }
            .accessibilityHidden(true)
    }
}
