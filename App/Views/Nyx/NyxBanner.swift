import SwiftUI
import MiBancoCore

/// Aviso de Nyx dentro de la app (diseño §6.10, §6.12 y §6.13):
/// vive en la ranura de aviso de `RootView` (`ShellState.shownBanner`), nunca encima del bloqueo ni fuera de primer plano.
/// Cae con el muelle `release` de `\.motion`, permanece 6 s o hasta que se toca o se desliza hacia arriba.
/// Con Reducir movimiento: cero recorrido y fundido de 0,2 s. Con el ojo cerrado: cero dígitos, «€» ni «%».
struct NyxBanner: View {
    let message: NyxMessage
    let hidden: Bool
    let primaryActionTitle: String?
    let onOpen: () -> Void
    let onAction: () -> Void
    let onDismiss: () -> Void
    let onFinished: () -> Void

    @Environment(\.motion) private var motion
    @State private var shown = false
    @State private var dragOffset: CGFloat = 0
    @State private var dismissedByUser = false

    private let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

    private var displayTitle: String {
        hidden ? nyxNotificationText(message, hidden: true).title : message.title
    }

    private var displayBody: String {
        nyxDisplayText(message, hidden: hidden)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: openFromBanner) {
                HStack(alignment: .top, spacing: 12) {
                    AppMark(size: 30)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayTitle)
                            .titan(.option)
                            .foregroundStyle(Theme.label)
                            .fixedSize(horizontal: false, vertical: true)
                            .contentTransition(.identity)
                            .privacySensitive()

                        Text(displayBody)
                            .titan(.meta)
                            .foregroundStyle(Theme.label2)
                            .fixedSize(horizontal: false, vertical: true)
                            .contentTransition(.identity)
                            .privacySensitive()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
                .frame(minHeight: 44)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("\(displayTitle). \(displayBody)")
            .accessibilityIdentifier("nyx-banner-open")

            if let primaryActionTitle {
                Button(action: triggerPrimaryAction) {
                    Text(primaryActionTitle)
                        .titan(.captionStrong)
                        .foregroundStyle(Theme.canvas)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Theme.label, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(primaryActionTitle)
                .accessibilityIdentifier("nyx-banner-action")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: shape)
        .overlay(shape.strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        .padding(.horizontal, 10)
        .offset(y: motion.reduce ? 0 : (shown ? min(0, dragOffset) : -160))
        .opacity(motion.reduce ? (shown ? 1 : 0) : (shown ? 1 : 0))
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    guard !motion.reduce else { return }
                    if value.translation.height < 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height < -24 || value.predictedEndTranslation.height < -48 {
                        dismissBySwipe()
                    } else {
                        withAnimation(motion.reduce ? nil : motion.animation(.snap)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .task { await run() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nyx-banner")
    }

    private func openFromBanner() {
        dismissedByUser = true
        onOpen()
    }

    private func triggerPrimaryAction() {
        dismissedByUser = true
        onAction()
    }

    private func dismissBySwipe() {
        guard !dismissedByUser else { return }
        dismissedByUser = true
        if motion.reduce {
            withAnimation(.easeOut(duration: 0.2)) { shown = false }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.2))
                onDismiss()
            }
        } else {
            withAnimation(.easeIn(duration: motion.pause(0.22))) { shown = false }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(motion.pause(0.22)))
                onDismiss()
            }
        }
    }

    private func run() async {
        AccessibilityNotification.Announcement("\(displayTitle). \(displayBody)").post()
        if motion.reduce {
            withAnimation(.easeOut(duration: 0.2)) { shown = true }
            try? await Task.sleep(for: .seconds(motion.pause(6.0)))
            guard !Task.isCancelled, !dismissedByUser else { return }
            withAnimation(.easeOut(duration: 0.2)) { shown = false }
            try? await Task.sleep(for: .seconds(0.2))
            guard !Task.isCancelled, !dismissedByUser else { return }
            onFinished()
            return
        }
        withAnimation(motion.animation(.release)) { shown = true }
        try? await Task.sleep(for: .seconds(motion.pause(6.0)))
        guard !Task.isCancelled, !dismissedByUser else { return }
        withAnimation(.easeIn(duration: motion.pause(0.32))) { shown = false }
        try? await Task.sleep(for: .seconds(motion.pause(0.32)))
        guard !Task.isCancelled, !dismissedByUser else { return }
        onFinished()
    }
}
