import SwiftUI
import MiBancoCore

/// Ajustes › Nyx (N13 y A4): proactividad («Cuánto te hablo»), lectura con auriculares, olvidar lo aprendido y los
/// seis temas de «Te puede interesar». Se guarda en el contenedor del App Group (`AssistantPreferencesStore`, sin importes).
struct AssistantSettingsSection: View {
    let briefing: BriefingModel
    var present: (RootSheet) -> Void = { _ in }

    static let scrollID = "settings-assistant-section"
    @State private var errorTick = 0

    var body: some View {
        Group {
            Section {
                Text("Cuánto te hablo")
                    .titan(.captionStrong)
                    .foregroundStyle(Theme.label2)
                    .accessibilityAddTraits(.isHeader)
                    .id(Self.scrollID)
                    .listRowBackground(Theme.grouped)
                    .listRowSeparatorTint(Theme.separator)

                ForEach(NyxTalkLevel.allCases, id: \.self) { level in
                    talkLevelRow(level)
                }
            } header: {
                SettingsHeader(assistantName)
            } footer: {
                SettingsFooter("Los avisos que elegiste en Avisos siguen llegando igual.")
            }

            Section {
                Toggle(isOn: readAloudBinding) {
                    OptionLabel(
                        title: "Leerte la puesta al día al abrir si llevas auriculares",
                        detail: "Nunca por altavoz, AirPlay ni CarPlay",
                        systemImage: "headphones"
                    )
                }
                .toggleStyle(TitanToggleStyle())
                .accessibilityIdentifier("nyx-read-aloud")
                .listRowBackground(Theme.grouped)
                .listRowSeparatorTint(Theme.separator)

                Button {
                    present(.confirmForgetNyx)
                } label: {
                    HStack(spacing: Theme.Space.row) {
                        OptionLabel(
                            title: "Olvidar lo que he aprendido",
                            detail: "Tus movimientos no se tocan",
                            systemImage: "trash"
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.passive)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("nyx-forget")
                .listRowBackground(Theme.grouped)
                .listRowSeparatorTint(Theme.separator)
            }

            Section {
                ForEach(AssistantTopic.allCases) { topic in
                    row(for: topic)
                }
            } header: {
                SettingsHeader("Te puede interesar")
            } footer: {
                SettingsFooter("Elige qué temas puede enseñarte \(assistantName) en «Te puede interesar». Todo se calcula en tu iPhone; tus preguntas no se guardan.")
            }
        }
        .sensoryFeedback(Haptics.error, trigger: errorTick)
    }

    private func talkLevelRow(_ level: NyxTalkLevel) -> some View {
        let selected = briefing.assistantPreferences.nyxTalkLevel == level
        return Button {
            if !briefing.setNyxTalkLevel(level) {
                errorTick += 1
            }
        } label: {
            HStack(spacing: 12) {
                Text(level.displayName)
                    .titan(.option)
                    .foregroundStyle(Theme.label)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.label)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 4)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(level.displayName)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("nyx-talk-\(level.rawValue)")
        .listRowBackground(Theme.grouped)
        .listRowSeparatorTint(Theme.separator)
    }

    private func row(for topic: AssistantTopic) -> some View {
        Toggle(isOn: binding(for: topic)) {
            OptionLabel(
                title: topic.displayName,
                detail: topic.settingsDetail,
                systemImage: topic.symbol
            )
        }
        .toggleStyle(TitanToggleStyle())
        .accessibilityIdentifier("assistant-topic-\(topic.rawValue)")
        .listRowBackground(Theme.grouped)
        .listRowSeparatorTint(Theme.separator)
    }

    private var readAloudBinding: Binding<Bool> {
        Binding(
            get: { briefing.assistantPreferences.nyxReadAloudWithHeadphones },
            set: { enabled in
                if !briefing.setNyxReadAloudWithHeadphones(enabled) {
                    errorTick += 1
                }
            }
        )
    }

    private func binding(for topic: AssistantTopic) -> Binding<Bool> {
        Binding(
            get: { briefing.isTopicEnabled(topic) },
            set: { enabled in
                if !briefing.setTopicEnabled(enabled, for: topic) {
                    errorTick += 1
                }
            }
        )
    }
}
