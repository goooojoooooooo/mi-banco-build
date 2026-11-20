import SwiftUI

/// Envuelve Ajustes en un `ScrollViewReader`. Solo hace algo en la demo (`-MiBancoDemoBackup`): desplaza Ajustes
/// hasta "Copia de seguridad" para la captura. Vive aquí para no tocar el cuerpo de `SettingsView`.
struct SettingsScrollHost<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollViewReader { proxy in
            content
                #if DEBUG
                .task {
                    guard DemoMode.isActive, DemoMode.scrollsToBackup else { return }
                    try? await Task.sleep(for: .milliseconds(600))
                    proxy.scrollTo(BackupSection.scrollID, anchor: .center)
                }
                #endif
        }
    }
}
