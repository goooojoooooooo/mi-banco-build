import SwiftUI

/// Las pantallas empujadas de Gasto montan sus piezas escalonadas la primera vez que se ven (no al volver atrás).
/// Con Reducir movimiento, todo aparece ya colocado.
private struct AssemblesOnFirstAppear: ViewModifier {
    @State private var entrance = Entrance()
    @State private var played = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .environment(\.entrance, entrance)
            .onAppear {
                guard !played, !reduceMotion else { return }
                played = true
                let token = entrance.token + 1
                entrance = Entrance(token: token, active: true, scope: .assembly)
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    if entrance.token == token { entrance.active = false }
                }
            }
    }
}

extension View {
    func assemblesOnFirstAppear() -> some View { modifier(AssemblesOnFirstAppear()) }
}
