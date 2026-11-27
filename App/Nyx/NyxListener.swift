import AVFoundation
import Foundation
import Observation
import Speech

/// Transcripción de voz en español estrictamente en el iPhone para «Pregúntame algo…» (diseño §6.9).
/// Nunca envía audio a la red (`requiresOnDeviceRecognition = true`), nunca guarda audio en disco y desaparece si el
/// dispositivo no admite transcripción local (`isAvailable == false`).
@MainActor @Observable
final class NyxListener {
    private static let spanishLocale = Locale(identifier: "es-ES")

    private(set) var isListening = false
    private(set) var transcript = ""
    private(set) var permissionDenied = false

    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var tapInstalled = false
    @ObservationIgnored private var updateHandler: (@MainActor (String) -> Void)?
    @ObservationIgnored private var finishHandler: (@MainActor (String) -> Void)?

    /// true solo si este iPhone puede transcribir español sin red.
    static var isAvailable: Bool {
        #if DEBUG
        if DemoMode.isActive {
            return !DemoMode.nyxSpeechUnavailable
        }
        #endif
        guard let recognizer = SFSpeechRecognizer(locale: spanishLocale) else { return false }
        return recognizer.supportsOnDeviceRecognition
    }

    func toggle(
        onUpdate: @escaping @MainActor (String) -> Void,
        onFinish: @escaping @MainActor (String) -> Void
    ) {
        if isListening {
            finishAndDeliver()
            return
        }
        Task { @MainActor [weak self] in
            await self?.start(onUpdate: onUpdate, onFinish: onFinish)
        }
    }

    func stop() {
        updateHandler = nil
        finishHandler = nil
        teardownEngine()
        isListening = false
    }

    private func finishAndDeliver() {
        let finalText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let handler = finishHandler
        updateHandler = nil
        finishHandler = nil
        teardownEngine()
        isListening = false
        if !finalText.isEmpty {
            handler?(finalText)
        }
    }

    private func start(
        onUpdate: @escaping @MainActor (String) -> Void,
        onFinish: @escaping @MainActor (String) -> Void
    ) async {
        permissionDenied = false
        transcript = ""
        updateHandler = onUpdate
        finishHandler = onFinish

        #if DEBUG
        if DemoMode.isActive {
            guard Self.isAvailable else { return }
            isListening = true
            return
        }
        #endif

        guard let recognizer = SFSpeechRecognizer(locale: Self.spanishLocale),
              recognizer.supportsOnDeviceRecognition else {
            updateHandler = nil
            finishHandler = nil
            return
        }

        let micAllowed = await AVAudioApplication.requestRecordPermission()
        guard micAllowed else {
            permissionDenied = true
            updateHandler = nil
            finishHandler = nil
            return
        }
        let speechStatus = await Self.requestSpeechAuthorization()
        guard speechStatus == .authorized else {
            permissionDenied = true
            updateHandler = nil
            finishHandler = nil
            return
        }

        teardownEngine()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: [.notifyOthersOnDeactivation])
        } catch {
            updateHandler = nil
            finishHandler = nil
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        Self.installAudioTap(on: inputNode, format: format, requestBox: SpeechRequestBox(request))
        tapInstalled = true

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            teardownEngine()
            updateHandler = nil
            finishHandler = nil
            return
        }

        isListening = true
        recognitionTask = Self.startRecognitionTask(recognizer: recognizer, request: request) { [weak self] text, isFinal, hadError in
            Task { @MainActor [weak self] in
                guard let self, self.isListening else { return }
                if let text {
                    self.transcript = text
                    self.updateHandler?(text)
                }
                if isFinal || hadError {
                    self.finishAndDeliver()
                }
            }
        }
    }

    private func teardownEngine() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        #if DEBUG
        if DemoMode.isActive { return }
        #endif
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private nonisolated static func installAudioTap(
        on inputNode: AVAudioInputNode,
        format: AVAudioFormat,
        requestBox: SpeechRequestBox
    ) {
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            requestBox.append(buffer)
        }
    }

    private nonisolated static func startRecognitionTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        onEvent: @escaping @Sendable (String?, Bool, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            onEvent(result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil)
        }
    }

    private nonisolated static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}

/// Caja `Sendable` mínima para reenviar búferes de audio desde el hilo de captura al reconocedor en dispositivo.
private final class SpeechRequestBox: @unchecked Sendable {
    private weak var request: SFSpeechAudioBufferRecognitionRequest?

    init(_ request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }
}
