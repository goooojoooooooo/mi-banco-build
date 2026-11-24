import SwiftUI
import LocalAuthentication

/// Bloqueo: negro, la marca (su ola se traza al aparecer), una línea y el botón de Face ID.
struct LockView: View {
    @Binding var locked: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var authenticating = false
    /// Un intento automático por bloqueo (esta vista solo existe mientras está bloqueado).
    @State private var autoAttempted = false
    @State private var drawn: CGFloat = 0
    @State private var failures = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            AppMark(size: 76, drawn: drawn)
            Text(AppIdentity.displayName)
                .titan(.sheetTitle)
                .foregroundStyle(Theme.label)
                .padding(.top, Theme.Space.gutter)
                .accessibilityAddTraits(.isHeader)
            Text("Tu dinero, solo para ti.")
                .titan(.callout)
                .foregroundStyle(Theme.label2)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
            Spacer()
            Button(action: unlock) {
                Label("Desbloquear", systemImage: "faceid")
                    .titan(.option)
                    .fontWeight(.semibold)
                    .foregroundStyle(.black)
                    .symbolEffect(.bounce, value: failures)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.pressable)
            .disabled(authenticating)
            .padding(.horizontal, Theme.Space.gutter + 8)
            .padding(.bottom, Theme.Space.gutter)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.canvas.ignoresSafeArea())
        .onAppear {
            if reduceMotion {
                drawn = 1
            } else {
                withAnimation(Theme.Motion.markDraw.delay(0.1)) { drawn = 1 }
            }
        }
        .task {
            #if DEBUG
            if DemoMode.holdsLock {
                // Demo: sin Face ID; tras ~4 s, la misma salida que usa el éxito de la autenticación.
                try? await Task.sleep(for: .seconds(DemoMode.lockSeconds))
                unlockWithFade()
                return
            }
            #endif
            await autoAuthenticate()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await autoAuthenticate() } }
        }
    }

    private func unlock() {
        Task { await authenticate() }
    }

    /// Solo en primer plano y una vez por bloqueo; si se cancela, queda el botón.
    private func autoAuthenticate() async {
        #if DEBUG
        if DemoMode.holdsLock { return }
        #endif
        guard scenePhase == .active, !autoAttempted else { return }
        autoAttempted = true
        await authenticate()
    }

    private func authenticate() async {
        guard !authenticating else { return }
        authenticating = true
        defer { authenticating = false }
        let context = LAContext()
        var error: NSError?
        // Sin código en el iPhone no hay con qué autenticar: se deja pasar en vez de dejarte fuera.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            unlockWithFade()
            return
        }
        let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Para que solo tú veas tu dinero")) ?? false
        if ok { unlockWithFade() } else { failures += 1 }
    }

    /// Solo la salida se anima (un fundido breve); con Reducir movimiento, uno aún más corto.
    private func unlockWithFade() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.unlock) { locked = false }
    }
}
