import SwiftUI

/// La marca de la app en Titanio: una pieza del material «Todo» con su canto mecanizado y la ola en blanco.
/// `drawn` (0…1) traza la ola; al arrancar y en el bloqueo se dibuja sobre negro.
struct AppMark: View {
    var size: CGFloat = 64
    var drawn: CGFloat = 1

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
        shape
            .fill(CardMaterial.all.gradient)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0.05), .white.opacity(0.14)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1)
            }
            .overlay {
                WaveShape()
                    .trim(from: 0, to: drawn)
                    .stroke(.white, style: StrokeStyle(lineWidth: size * 0.065, lineCap: .round, lineJoin: .round))
                    .padding(size * 0.2)
            }
            .frame(width: size, height: size)
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

/// Un ✓ que se dibuja en 0,35 s cuando aparece (con Reducir movimiento, aparece entero).
struct DrawnCheck: View {
    var lineWidth: CGFloat = 2.2
    var color: Color = Theme.label
    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CheckShape()
            .trim(from: 0, to: progress)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .onAppear {
                if reduceMotion {
                    progress = 1
                } else {
                    withAnimation(.easeOut(duration: 0.35).delay(0.05)) { progress = 1 }
                }
            }
            .accessibilityHidden(true)
    }
}
