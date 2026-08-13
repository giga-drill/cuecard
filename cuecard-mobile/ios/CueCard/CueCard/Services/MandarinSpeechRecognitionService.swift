import AVFoundation
import Foundation
import Speech

enum SpeechRecognitionUnavailability: Equatable, Sendable {
    case microphonePermissionDenied
    case speechPermissionDenied
    case recognizerUnavailable
    case onDeviceRecognitionUnsupported
    case invalidAudioInput
}

enum MandarinSpeechRecognitionState: Equatable, Sendable {
    case idle
    case requestingPermissions
    case ready
    case listening
    case unavailable(SpeechRecognitionUnavailability)
    case failed(String)

    var canStart: Bool {
        self == .ready
    }
}

@MainActor
final class MandarinSpeechRecognitionService: ObservableObject {
    nonisolated static let localeIdentifier = "zh-CN"

    @Published private(set) var state: MandarinSpeechRecognitionState = .idle
    @Published private(set) var partialTranscript = ""

    var onPartialTranscript: ((String) -> Void)?
    var onStateChange: ((MandarinSpeechRecognitionState) -> Void)?
    var onAudioSessionEvent: ((SpeechAudioSessionEvent) -> Void)?

    private let speechRecognizer: SFSpeechRecognizer?
    private let audioEngine: AVAudioEngine
    private let audioSessionCoordinator: SpeechAudioSessionCoordinator
    private let diagnostics: SpeechDiagnostics
    private let bufferMonitor = AudioBufferPulseMonitor()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var activeRecognitionID: UUID?
    private var hasInstalledInputTap = false
    private var bufferWatchdog: Timer?
    private var hasReportedBufferTimeout = false

    init(
        speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: MandarinSpeechRecognitionService.localeIdentifier)),
        audioEngine: AVAudioEngine = AVAudioEngine(),
        diagnostics: SpeechDiagnostics? = nil,
        audioSessionCoordinator: SpeechAudioSessionCoordinator? = nil
    ) {
        self.speechRecognizer = speechRecognizer
        self.audioEngine = audioEngine
        let resolvedDiagnostics = diagnostics ?? .shared
        self.diagnostics = resolvedDiagnostics
        self.audioSessionCoordinator = audioSessionCoordinator ?? SpeechAudioSessionCoordinator(diagnostics: resolvedDiagnostics)
        self.audioSessionCoordinator.onEvent = { [weak self] event in
            self?.onAudioSessionEvent?(event)
            if event == .interruptionBegan {
                self?.stopRecognition(setReadyWhenPossible: false)
                self?.setState(.failed("audio_session_interrupted"))
            }
        }
    }

    @discardableResult
    func requestPermissionsAndPrepare() async -> Bool {
        setState(.requestingPermissions)

        let speechStatus = await requestSpeechAuthorization()
        guard speechStatus == .authorized else {
            setState(.unavailable(.speechPermissionDenied))
            return false
        }

        let microphoneGranted = await requestMicrophonePermission()
        guard microphoneGranted else {
            setState(.unavailable(.microphonePermissionDenied))
            return false
        }

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            setState(.unavailable(.recognizerUnavailable))
            return false
        }

        guard speechRecognizer.supportsOnDeviceRecognition else {
            setState(.unavailable(.onDeviceRecognitionUnsupported))
            return false
        }

        setState(.ready)
        return true
    }

    @discardableResult
    func startRecognition() async -> Bool {
        stopRecognition(setReadyWhenPossible: false)

        guard await requestPermissionsAndPrepare() else { return false }
        guard let speechRecognizer else {
            setState(.unavailable(.recognizerUnavailable))
            return false
        }

        do {
            try audioSessionCoordinator.configureAndActivate()
        } catch {
            diagnostics.record(.error, details: [
                "source": "audio_session_activate",
                "message": error.localizedDescription
            ])
            setState(.failed(error.localizedDescription))
            return false
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            setState(.unavailable(.invalidAudioInput))
            return false
        }

        let request = Self.makeRecognitionRequest()
        recognitionRequest = request
        partialTranscript = ""

        bufferMonitor.reset()
        hasReportedBufferTimeout = false
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: recordingFormat) { [weak self, weak request] buffer, _ in
            request?.append(buffer)
            if self?.bufferMonitor.recordBuffer() == true {
                let frameLength = buffer.frameLength
                Task { @MainActor [weak self] in
                    self?.diagnostics.record(.audioBuffer, details: [
                        "frames": String(frameLength)
                    ])
                }
            }
        }
        hasInstalledInputTap = true

        let recognitionID = UUID()
        activeRecognitionID = recognitionID
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                guard self.activeRecognitionID == recognitionID else { return }

                if let result {
                    self.receiveTranscript(result.bestTranscription.formattedString)
                    if result.isFinal {
                        self.diagnostics.record(.recognitionTaskEnded, details: ["reason": "final_result"])
                        self.stopRecognition(setReadyWhenPossible: true)
                    }
                }

                if let error {
                    self.diagnostics.record(.recognitionTaskEnded, details: [
                        "reason": "error",
                        "message": error.localizedDescription
                    ])
                    self.stopRecognition(setReadyWhenPossible: false)
                    self.setState(.failed(error.localizedDescription))
                }
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            startBufferWatchdog()
            setState(.listening)
            return true
        } catch {
            stopRecognition(setReadyWhenPossible: false)
            setState(.failed(error.localizedDescription))
            return false
        }
    }

    func stopRecognition() {
        stopRecognition(setReadyWhenPossible: true)
    }

    static func makeRecognitionRequest() -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        return request
    }

    private func receiveTranscript(_ transcript: String) {
        partialTranscript = transcript
        diagnostics.record(.partialTranscript, details: ["characters": String(transcript.count)])
        onPartialTranscript?(transcript)
    }

    private func stopRecognition(setReadyWhenPossible: Bool) {
        activeRecognitionID = nil
        bufferWatchdog?.invalidate()
        bufferWatchdog = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasInstalledInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledInputTap = false
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioSessionCoordinator.deactivate()

        if setReadyWhenPossible,
           speechRecognizer?.isAvailable == true,
           speechRecognizer?.supportsOnDeviceRecognition == true {
            setState(.ready)
        }
    }

    private func startBufferWatchdog() {
        bufferWatchdog?.invalidate()
        bufferWatchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == .listening else { return }
                let silenceDuration = self.bufferMonitor.secondsSinceLastBuffer()
                guard silenceDuration >= 1, !self.hasReportedBufferTimeout else { return }
                self.hasReportedBufferTimeout = true
                self.diagnostics.record(.noBufferTimeout, details: [
                    "seconds": String(format: "%.1f", silenceDuration)
                ])
                self.stopRecognition(setReadyWhenPossible: false)
                self.setState(.failed("audio_buffer_timeout"))
            }
        }
    }

    private func setState(_ newState: MandarinSpeechRecognitionState) {
        guard state != newState else { return }
        state = newState
        onStateChange?(newState)
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let existingStatus = SFSpeechRecognizer.authorizationStatus()
        guard existingStatus == .notDetermined else { return existingStatus }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }
}
