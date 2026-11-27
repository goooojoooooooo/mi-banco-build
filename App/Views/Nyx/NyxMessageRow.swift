import SwiftUI
import MiBancoCore

/// Una tarjeta de mensaje de Nyx (en «Para tener en cuenta» o en «Lo que he visto»).
/// - Con el ojo cerrado no expone ningún dígito, ni «€», ni «%» ni en pantalla ni en VoiceOver.
/// - Las cifras usan `.contentTransition(.identity)` y `.privacySensitive()`.
/// - En tamaños de accesibilidad, los botones pasan debajo del texto en columna sin recortar.
struct NyxMessageRow: View {
    let entryID: String
    let message: NyxMessage
    var delivery: NyxDelivery? = nil
    let hidden: Bool
    let actions: [NyxAction]
    let actionTitles: [String]
    var undoState: NyxUndoState? = nil
    var showDismiss: Bool = true
    var isHighlighted: Bool = false
    var containerID: String? = nil
    var onAction: (NyxAction) -> Void
    var onDismiss: () -> Void
    var onUndo: () -> Void = {}
    var listenAction: (() -> Void)? = nil
    var isListening: Bool = false

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.motion) private var motion

    private var displayTitle: String {
        hidden ? nyxNotificationText(message, hidden: true).title : message.title
    }

    private var accessibleDescription: String {
        "\(displayTitle). \(nyxDisplayText(message, hidden: hidden))"
    }

    private var accentColor: Color {
        switch message.priority {
        case .urgent: Theme.warning
        case .normal: Theme.label
        case .quiet: Theme.label2
        }
    }

    var body: some View {
        Group {
            if let undo = undoState {
                undoContent(undo)
            } else {
                messageContent
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isHighlighted ? Theme.raised : Theme.grouped,
            in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous)
        )
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous)
                    .stroke(Theme.label3.opacity(0.45), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(undoState?.confirmationText ?? accessibleDescription)
        .accessibilityIdentifier(containerID ?? "nyx-message-\(entryID)")
        .modifier(NyxDismissAccessibilityAction(enabled: showDismiss && undoState == nil, onDismiss: onDismiss))
    }

    private func undoContent(_ undo: NyxUndoState) -> some View {
        HStack(spacing: 12) {
            Text(undo.confirmationText)
                .titan(.callout)
                .foregroundStyle(Theme.label2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onUndo) {
                Text("Deshacer")
                    .titan(.captionStrong)
                    .foregroundStyle(Theme.canvas)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Theme.label, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Deshacer")
            .accessibilityIdentifier("nyx-undo")
        }
    }

    private var messageContent: some View {
        let headerLayout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        let buttonsLayout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))

        return VStack(alignment: .leading, spacing: 10) {
            headerLayout {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)

                    Text(displayTitle)
                        .titan(.cardTitle)
                        .foregroundStyle(Theme.label)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentTransition(.identity)
                        .privacySensitive()
                }

                if let listenAction {
                    Button(action: listenAction) {
                        HStack(spacing: 4) {
                            Image(systemName: isListening ? "stop.fill" : "speaker.wave.2")
                                .font(.system(size: 12, weight: .semibold))
                                .accessibilityHidden(true)
                            Text(isListening ? "Parar" : "Escuchar")
                                .titan(.meta)
                        }
                        .foregroundStyle(Theme.label2)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 44)
                        .background(Theme.raised, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(isListening ? "Parar" : "Escuchar")
                    .accessibilityIdentifier("nyx-listen-focus")
                }
            }

            if hidden {
                Text(nyxDisplayText(message, hidden: true))
                    .titan(.callout)
                    .foregroundStyle(Theme.label2)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.identity)
                    .privacySensitive()
                    .accessibilityLabel(nyxDisplayText(message, hidden: true))
            } else {
                Text(BriefingLineView.attributed(parts: message.open, overrideFirstAmount: nil, baseColor: Theme.label2))
                    .titan(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.identity)
                    .privacySensitive()
                    .accessibilityLabel(nyxDisplayText(message, hidden: false))
            }

            if let delivery {
                Text(delivery.spanishFooter)
                    .titan(.meta)
                    .foregroundStyle(Theme.label3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !actions.isEmpty || showDismiss {
                buttonsLayout {
                    ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                        let title = index < actionTitles.count
                            ? actionTitles[index]
                            : nyxActionTitle(action, hidden: hidden)
                        Button {
                            onAction(action)
                        } label: {
                            Text(title)
                                .titan(.captionStrong)
                                .foregroundStyle(index == 0 ? Theme.canvas : Theme.label)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .frame(minHeight: 44)
                                .background(index == 0 ? Theme.label : Theme.raised, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel(title)
                        .accessibilityIdentifier("nyx-action-\(entryID)-\(index)")
                    }

                    if showDismiss {
                        Button(action: onDismiss) {
                            Text("Descartar")
                                .titan(.captionStrong)
                                .foregroundStyle(Theme.label2)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .frame(minHeight: 44)
                                .background(Theme.raised, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel("Descartar")
                        .accessibilityIdentifier("nyx-dismiss-\(entryID)")
                    }
                }
                .padding(.top, 2)
            }
        }
    }
}

private struct NyxDismissAccessibilityAction: ViewModifier {
    let enabled: Bool
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.accessibilityAction(named: "Descartar", onDismiss)
        } else {
            content
        }
    }
}
