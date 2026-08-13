import AVFoundation
import Foundation
import os

enum SpeechDiagnosticKind: String, Equatable, Sendable {
    case sessionConfigured
    case sessionActivated
    case sessionDeactivated
    case audioBuffer
    case partialTranscript
    case interruptionBegan
    case interruptionEnded
    case routeChanged
    case recognitionTaskEnded
    case noBufferTimeout
    case pipStarted
    case pipStopped
    case appBackgrounded
    case appForegrounded
    case fallbackToFixedSpeed
    case voiceAlignment
    case error
}

struct SpeechDiagnosticEvent: Identifiable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let kind: SpeechDiagnosticKind
    let details: [String: String]

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        kind: SpeechDiagnosticKind,
        details: [String: String] = [:]
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.details = details
    }
}

@MainActor
final class SpeechDiagnostics: ObservableObject {
    static let shared = SpeechDiagnostics()

    @Published private(set) var events: [SpeechDiagnosticEvent] = []
    private let logger = Logger(subsystem: "com.gigadrill.cuecard", category: "SpeechDiagnostics")

    func record(_ kind: SpeechDiagnosticKind, details: [String: String] = [:]) {
        let event = SpeechDiagnosticEvent(kind: kind, details: details)
        events.append(event)
        if events.count > 300 {
            events.removeFirst(events.count - 300)
        }

        let fields = details
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        logger.info("event=\(kind.rawValue, privacy: .public) \(fields, privacy: .public)")
#if DEBUG
        print("[SpeechDiagnostics] event=\(kind.rawValue) \(fields)")
#endif
    }

    func reset() {
        events.removeAll(keepingCapacity: true)
    }
}

enum SpeechAudioSessionEvent: Equatable, Sendable {
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    case routeChanged(reason: String)
}

@MainActor
final class SpeechAudioSessionCoordinator {
    var onEvent: ((SpeechAudioSessionEvent) -> Void)?

    private let session: AVAudioSession
    private let diagnostics: SpeechDiagnostics
    private var notificationTokens: [NSObjectProtocol] = []

    init(
        session: AVAudioSession = .sharedInstance(),
        diagnostics: SpeechDiagnostics? = nil
    ) {
        self.session = session
        self.diagnostics = diagnostics ?? .shared
        observeSystemEvents()
    }

    func configureAndActivate() throws {
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers])
        diagnostics.record(.sessionConfigured, details: [
            "category": AVAudioSession.Category.playAndRecord.rawValue,
            "mode": AVAudioSession.Mode.measurement.rawValue,
            "mixWithOthers": "true"
        ])

        try session.setActive(true)
        diagnostics.record(.sessionActivated)
    }

    func deactivate() {
        guard session.category == .playAndRecord else { return }
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
            diagnostics.record(.sessionDeactivated)
        } catch {
            diagnostics.record(.error, details: [
                "source": "audio_session_deactivate",
                "message": error.localizedDescription
            ])
        }
    }

    private func observeSystemEvents() {
        let center = NotificationCenter.default
        notificationTokens.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: session,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    self?.handleInterruption(notification)
                }
            }
        )
        notificationTokens.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: session,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    self?.handleRouteChange(notification)
                }
            }
        )
    }

    private func handleInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }

        switch type {
        case .began:
            diagnostics.record(.interruptionBegan)
            onEvent?(.interruptionBegan)
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
            diagnostics.record(.interruptionEnded, details: ["shouldResume": String(shouldResume)])
            onEvent?(.interruptionEnded(shouldResume: shouldResume))
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
        let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason)
        let reasonText = reason.map { String(describing: $0) } ?? "unknown_\(rawReason)"
        diagnostics.record(.routeChanged, details: ["reason": reasonText])
        onEvent?(.routeChanged(reason: reasonText))
    }

    deinit {
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

final class AudioBufferPulseMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var lastBufferDate = Date.distantPast
    private var lastDiagnosticDate = Date.distantPast

    func reset(at date: Date = Date()) {
        lock.lock()
        lastBufferDate = date
        lastDiagnosticDate = .distantPast
        lock.unlock()
    }

    func recordBuffer(at date: Date = Date(), diagnosticInterval: TimeInterval = 1) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        lastBufferDate = date
        guard date.timeIntervalSince(lastDiagnosticDate) >= diagnosticInterval else { return false }
        lastDiagnosticDate = date
        return true
    }

    func secondsSinceLastBuffer(at date: Date = Date()) -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return date.timeIntervalSince(lastBufferDate)
    }
}
