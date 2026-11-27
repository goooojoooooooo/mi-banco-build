import AppIntents
import MiBancoCore

/// Acción rápida de un solo parámetro para la automatización de notificaciones en iOS 27:
/// recibe la notificación completa, deduce el banco y reparte título y cuerpo en Core (`parseQuickNotice`)
/// antes de pasar el resultado a `IngestRunner`.
struct PassNoticeIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Pasar aviso a Onyx"
    static let description = IntentDescription("Registra un aviso bancario en Onyx sin rellenar campos a mano.")
    static let openAppWhenRun = false

    @Parameter(title: "Notificación") var notification: String

    static var parameterSummary: some ParameterSummary {
        Summary("Pasar \(\.$notification) a Onyx")
    }

    func perform() async throws -> some IntentResult {
        guard let input = parseQuickNotice(notification) else {
            return .result()
        }
        try await IngestRunner.run(input)
        return .result()
    }
}
