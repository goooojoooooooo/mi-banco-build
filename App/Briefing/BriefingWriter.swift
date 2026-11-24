import Foundation
import MiBancoCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Contrato con el modelo del dispositivo (J21, J21(d), A2, A6):
/// el modelo NUNCA escribe texto que vea ni oiga el dueño; solo elige una frase del catálogo (índice 1…N) o clasifica
/// una pregunta en una intención conocida con parámetros validados por el Core. Nada sale del iPhone.
protocol BriefingWriter: Sendable {
    func openingChoice(for briefing: Briefing) async -> Int?
    func routeQuestion(_ question: String, now: Date, calendar: Calendar, portfolio: Portfolio?, knownMerchants: Set<String>) async -> AssistantIntent?
}

/// Respaldo determinista sin modelo: el catálogo rota por día y las preguntas van al enrutador por reglas del Core.
struct RuleBriefingWriter: BriefingWriter {
    func openingChoice(for briefing: Briefing) async -> Int? { nil }
    func routeQuestion(_ question: String, now: Date, calendar: Calendar, portfolio: Portfolio?, knownMerchants: Set<String>) async -> AssistantIntent? { nil }
}

func makeDefaultBriefingWriter() -> any BriefingWriter {
    #if DEBUG
    if DemoMode.isActive {
        return RuleBriefingWriter()
    }
    #endif
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
        return ModelBriefingWriter()
    }
    #endif
    return RuleBriefingWriter()
}

#if canImport(FoundationModels)
/// Enlace débil con FoundationModels (iOS 26+). Si Apple Intelligence no está disponible o no responde en 4 s, cae en silencio
/// al respaldo por reglas. Nota: `supportsLocale` está pendiente de verificar en iOS 27 real.
@available(iOS 26.0, *)
struct ModelBriefingWriter: BriefingWriter {
    private static let timeoutSeconds: Double = 4
    private static let spanishLocale = Locale(identifier: "es_ES")

    func openingChoice(for briefing: Briefing) async -> Int? {
        guard isModelReady() else { return nil }
        let count = openingCandidateCount(for: briefing.situation)
        guard count > 0 else { return nil }
        let prompt = briefingModelPrompt(briefing)
        guard let raw = await runPrompt(
            instructions: briefingModelInstructions,
            prompt: prompt,
            temperature: 0.3,
            maxTokens: 16
        ) else {
            return nil
        }
        return MiBancoCore.openingChoice(from: raw, count: count)
    }

    func routeQuestion(_ question: String, now: Date, calendar: Calendar, portfolio: Portfolio?, knownMerchants: Set<String>) async -> AssistantIntent? {
        // Barrera incondicional antes de tocar el modelo (A3, J21(d), N8).
        guard !isAdviceRequest(question, portfolio: portfolio, knownMerchants: knownMerchants) else { return nil }
        guard isModelReady() else { return nil }
        let prompt = assistantRoutingPrompt(question: question, now: now, calendar: calendar)
        guard let raw = await runPrompt(
            instructions: assistantRoutingInstructions,
            prompt: prompt,
            temperature: 0.1,
            maxTokens: 64
        ) else {
            return nil
        }
        return parseAssistantModelRoute(raw, originalQuestion: question, portfolio: portfolio, knownMerchants: knownMerchants)
    }

    private func isModelReady() -> Bool {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return false }
        return model.supportsLocale(Self.spanishLocale)
    }

    private func runPrompt(instructions: String, prompt: String, temperature: Double, maxTokens: Int) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask {
                do {
                    let session = LanguageModelSession(instructions: instructions)
                    let options = GenerationOptions(temperature: temperature, maximumResponseTokens: maxTokens)
                    let response = try await session.respond(to: prompt, options: options)
                    return response.content
                } catch {
                    return nil
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(Self.timeoutSeconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
#endif
