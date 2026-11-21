import SwiftUI
import MiBancoCore

/// Ajustes › Asistente (A4): un interruptor por cada uno de los seis temas de «Te puede interesar».
/// Se guarda solo en este iPhone (`AssistantPreferencesStore`); nunca sale del dispositivo ni entra en copias de seguridad.
struct AssistantSettingsSection: View {
    let briefing: BriefingModel

    static let scrollID = "settings-assistant-section"

    var body: some View {
        Section {
            ForEach(AssistantTopic.allCases) { topic in
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
        } header: {
            SettingsHeader("Asistente")
                .id(Self.scrollID)
        } footer: {
            SettingsFooter("Elige qué temas puede enseñarte Onyx en «Te puede interesar». Todo se calcula en tu iPhone; tus preguntas no se guardan.")
        }
    }

    private func binding(for topic: AssistantTopic) -> Binding<Bool> {
        Binding(
            get: { briefing.isTopicEnabled(topic) },
            set: { enabled in
                briefing.setTopicEnabled(enabled, for: topic)
            }
        )
    }
}
