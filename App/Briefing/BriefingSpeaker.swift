import AVFoundation
import Foundation
import Observation
import MiBancoCore

/// Lectura en voz alta del resumen o de una respuesta de Onyx (tarea 10, A5).
/// Usa la mejor voz `es-ES` instalada (premium > enhanced > defecto), atenúa otro audio (`.duckOthers`) y libera la
/// sesión al terminar. Se detiene sin falta al cerrar la hoja, bloquear o salir de primer plano.
@MainActor @Observable
final class BriefingSpeaker {
    enum Target: Equatable, Sendable {
        case briefing
    }

    private(set) var activeTarget: Target?
    var isSpeaking: Bool { activeTarget != nil }
    /// B2: la línea del resumen que suena ahora (su `BriefingLine.id`; la frase principal es "headline"), según el
    /// progreso REAL de la voz (`willSpeakRangeOfSpeechString`). nil cuando no suena ninguna línea (el saludo, entre
    /// frases o callada). Con el modo privado no hay líneas (la voz no lee ninguna).
    private(set) var currentLine: String?
    private var lines: [SpokenBriefing.Line] = []

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

    /// B2: lo mismo con el texto que sabe dónde está cada línea, para resaltar la que suena.
    func toggle(_ spoken: SpokenBriefing, target: Target = .briefing) {
        if activeTarget == target {
            stop()
            return
        }
        speak(spoken.text, target: target, lines: spoken.lines)
    }

    func speak(_ text: String, target: Target = .briefing, lines: [SpokenBriefing.Line] = []) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            stop()
            return
        }
        stop(deactivateSession: false)
        generation += 1
        let token = generation
        activeTarget = target
        // Los rangos son del texto entero; si se recorta por delante, se corrigen (en la práctica no hay nada que
        // recortar: el texto empieza por el saludo).
        let shift = text.utf16.count - text.drop(while: { $0.isWhitespace }).utf16.count
        self.lines = lines.map { .init(id: $0.id, range: ($0.range.lowerBound - shift)..<($0.range.upperBound - shift)) }

        #if DEBUG
        if DemoMode.isActive {
            // En el simulador de CI no hay salida de audio fiable: simulamos una lectura activa hasta «Parar» o cierre,
            // y que la voz va pasando por las líneas (1,6 s cada una, a la cámara lenta de las grabaciones) para poder
            // grabar y probar el resalte. En el iPhone manda el progreso real de la voz.
            let steps = self.lines
            demoTimer = Task { [weak self] in
                for line in steps {
                    guard let self, !Task.isCancelled, self.generation == token else { return }
                    self.currentLine = line.id
                    try? await Task.sleep(for: .seconds(1.6 * DemoMode.motionScale))
                }
                try? await Task.sleep(for: .seconds(60))
                guard let self, !Task.isCancelled, self.generation == token else { return }
                self.currentLine = nil
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

        delegateProxy.setHandler(for: utterance) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.activeTarget = nil
                self.currentLine = nil
                self.deactivateAudioSession()
            }
        } progress: { [weak self] location in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                let now = self.lines.first { $0.range.contains(location) }?.id
                if now != self.currentLine { self.currentLine = now }
            }
        }
        synthesizer.speak(utterance)
    }

    func stop(deactivateSession: Bool = true) {
        generation += 1
        demoTimer?.cancel()
        demoTimer = nil
        let wasActive = activeTarget != nil || synthesizer.isSpeaking || synthesizer.isPaused
        activeTarget = nil
        currentLine = nil
        delegateProxy.clear()
        // Llamamos siempre que hubiera una lectura solicitada o en curso: evita la ventana de arranque antes de `isSpeaking`.
        if wasActive {
            synthesizer.stopSpeaking(at: .immediate)
        }
        #if DEBUG
        if DemoMode.isActive { return }
        #endif
        if deactivateSession && wasActive {
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
/// Comprueba la identidad exacta de la `AVSpeechUtterance` para que un `didCancel` rezagado de una lectura anterior
/// jamás apague una lectura nueva.
private final class DelegateProxy: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var entry: (utteranceID: ObjectIdentifier, handler: @Sendable () -> Void, progress: @Sendable (Int) -> Void)?

    func setHandler(for utterance: AVSpeechUtterance, handler: @escaping @Sendable () -> Void,
                    progress: @escaping @Sendable (Int) -> Void) {
        let id = ObjectIdentifier(utterance)
        lock.withLock { entry = (id, handler, progress) }
    }

    func clear() {
        lock.withLock { entry = nil }
    }

    /// B2: el motor va a decir este rango del texto (UTF-16): es el progreso real de la lectura.
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange,
                           utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        let progress: (@Sendable (Int) -> Void)? = lock.withLock {
            guard let current = entry, current.utteranceID == id else { return nil }
            return current.progress
        }
        progress?(characterRange.location)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        invokeIfMatching(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        invokeIfMatching(utterance)
    }

    private func invokeIfMatching(_ utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        let matched: (@Sendable () -> Void)? = lock.withLock {
            guard let current = entry, current.utteranceID == id else { return nil }
            entry = nil
            return current.handler
        }
        matched?()
    }
}
