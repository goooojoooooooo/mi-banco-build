import AVFoundation
import Foundation
import Observation

/// Lectura en voz alta del resumen o de una respuesta de Onyx (tarea 10, A5).
/// Usa la mejor voz `es-ES` instalada (premium > enhanced > defecto), atenúa otro audio (`.duckOthers`) y libera la
/// sesión al terminar. Se detiene sin falta al cerrar la hoja, bloquear o salir de primer plano.
@MainActor @Observable
final class BriefingSpeaker {
    enum Target: Equatable, Sendable {
        case briefing
        case answer
    }

    private(set) var activeTarget: Target?
    var isSpeaking: Bool { activeTarget != nil }

    private let synthesizer = AVSpeechSynthesizer()
    private let delegateProxy: DelegateProxy
    private var generation = 0
    private var demoTimer: Task<Void, Never>?

    init() {
        let proxy = DelegateProxy()
        self.delegateProxy = proxy
        synthesizer.delegate = proxy
    }

    func toggle(_ text: String, target: Target = .briefing) {
        if activeTarget == target {
            stop()
            return
        }
        speak(text, target: target)
    }

    func speak(_ text: String, target: Target = .briefing) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            stop()
            return
        }
        stop()
        generation += 1
        let token = generation
        activeTarget = target

        #if DEBUG
        if DemoMode.isActive {
            // En el simulador de CI no hay salida de audio fiable: simulamos una lectura activa hasta «Parar» o cierre.
            demoTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(60))
                guard let self, !Task.isCancelled, self.generation == token else { return }
                self.activeTarget = nil
            }
            return
        }
        #endif

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = Self.preferredVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        delegateProxy.onComplete = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.activeTarget = nil
                self.deactivateAudioSession()
            }
        }
        synthesizer.speak(utterance)
    }

    func stop() {
        generation += 1
        demoTimer?.cancel()
        demoTimer = nil
        let wasSpeaking = activeTarget != nil || synthesizer.isSpeaking
        activeTarget = nil
        delegateProxy.onComplete = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        #if DEBUG
        if DemoMode.isActive { return }
        #endif
        if wasSpeaking {
            deactivateAudioSession()
        }
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private static func preferredVoice() -> AVSpeechSynthesisVoice? {
        let spanish = AVSpeechSynthesisVoice.speechVoices().filter {
            let lang = $0.language.lowercased()
            return lang == "es-es" || lang == "es_es"
        }
        if let premium = spanish.first(where: { $0.quality == .premium }) { return premium }
        if let enhanced = spanish.first(where: { $0.quality == .enhanced }) { return enhanced }
        return spanish.first ?? AVSpeechSynthesisVoice(language: "es-ES")
    }
}

/// Puente no aislado para los callbacks de `AVSpeechSynthesizerDelegate` en Swift 6.
private final class DelegateProxy: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?

    var onComplete: (@Sendable () -> Void)? {
        get { lock.withLock { handler } }
        set { lock.withLock { handler = newValue } }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onComplete?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onComplete?()
    }
}
