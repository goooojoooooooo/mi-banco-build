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
        try await IngestRunner.run(.notification(bank: bank.id, title: noticeTitle, subtitle: noticeSubtitle, body: noticeBody))
        return .result()
    }
}
