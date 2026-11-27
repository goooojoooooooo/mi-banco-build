import AppIntents
import MiBancoCore

struct RegisterNoticeIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Registrar aviso"
    static let openAppWhenRun = false

    @Parameter(title: "Banco") var bank: BankOption
    @Parameter(title: "Título") var noticeTitle: String?
    @Parameter(title: "Subtítulo") var noticeSubtitle: String?
    @Parameter(title: "Cuerpo") var noticeBody: String?

    func perform() async throws -> some IntentResult {
        let input = sanitizeIngestInput(
            .notification(bank: bank.id, title: noticeTitle, subtitle: noticeSubtitle, body: noticeBody)
        )
        try await IngestRunner.run(input)
        return .result()
    }
}
