import AppIntents
import MiBancoCore

struct RegisterWalletIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Registrar pago con Cartera"
    static let openAppWhenRun = false

    @Parameter(title: "Banco") var bank: BankOption
    @Parameter(title: "Importe") var amount: String
    @Parameter(title: "Comercio") var merchant: String?

    func perform() async throws -> some IntentResult {
        let input = sanitizeIngestInput(.wallet(bank: bank.id, amount: amount, merchant: merchant))
        try await IngestRunner.run(input)
        return .result()
    }
}
