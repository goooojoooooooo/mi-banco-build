import SwiftUI

/// Envuelve Ajustes en un `ScrollViewReader` para desplazar hasta una sección concreta
/// (desde la tarjeta de inversiones o en capturas de demo `-MiBancoDemoBackup` / `-MiBancoDemoInvestmentsSettings`).
struct SettingsScrollHost<Content: View>: View {
    @Binding var scrollRequest: String?
    @ViewBuilder let content: Content

    var body: some View {
        ScrollViewReader { proxy in
            content
                .onChange(of: scrollRequest) { _, target in
                    guard let target else { return }
                    scrollRequest = nil
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(target, anchor: .center)
                        }
                    }
                }
                #if DEBUG
                .task {
                    guard DemoMode.isActive else { return }
                    if DemoMode.scrollsToBackup {
                        try? await Task.sleep(for: .milliseconds(600))
                        proxy.scrollTo(BackupSection.scrollID, anchor: .center)
                    } else if DemoMode.scrollsToInvestments {
                        try? await Task.sleep(for: .milliseconds(600))
                        proxy.scrollTo(InvestmentsSection.scrollID, anchor: .center)
                    }
                }
                #endif
        }
    }
}
