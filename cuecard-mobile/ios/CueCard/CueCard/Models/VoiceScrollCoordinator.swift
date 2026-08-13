import Foundation

struct VoiceScrollConfiguration: Equatable, Sendable {
    var smoothingFactor = 0.2
    var maximumForwardStep = 0.025
    var maximumBackwardStep = 0.012
    var maximumRollback = 0.05
    var pauseAfter: TimeInterval = 1
    var snapDistance = 0.0005
}

final class VoiceScrollCoordinator {
    private(set) var currentProgress: Double
    private(set) var targetProgress: Double
    private(set) var isSpeaking = false

    private let configuration: VoiceScrollConfiguration
    private var lastSpeechActivity: Date?

    init(
        initialProgress: Double = 0,
        configuration: VoiceScrollConfiguration = .init()
    ) {
        let progress = Self.clamp(initialProgress)
        currentProgress = progress
        targetProgress = progress
        self.configuration = configuration
    }

    func reset(to progress: Double) {
        let progress = Self.clamp(progress)
        currentProgress = progress
        targetProgress = progress
        lastSpeechActivity = nil
        isSpeaking = false
    }

    func noteSpeechActivity(at date: Date = Date()) {
        lastSpeechActivity = date
        isSpeaking = true
    }

    func receive(_ alignment: MandarinAlignment, at date: Date = Date()) {
        noteSpeechActivity(at: date)
        let proposed = Self.clamp(alignment.progress)
        if proposed < currentProgress {
            targetProgress = max(proposed, currentProgress - configuration.maximumRollback)
        } else {
            targetProgress = proposed
        }
    }

    @discardableResult
    func tick(at date: Date = Date()) -> Double {
        guard let lastSpeechActivity else { return currentProgress }
        guard date.timeIntervalSince(lastSpeechActivity) <= configuration.pauseAfter else {
            isSpeaking = false
            return currentProgress
        }

        let delta = targetProgress - currentProgress
        if abs(delta) <= configuration.snapDistance {
            currentProgress = targetProgress
            return currentProgress
        }

        let proposedStep = delta * configuration.smoothingFactor
        let limitedStep = proposedStep >= 0
            ? min(proposedStep, configuration.maximumForwardStep)
            : max(proposedStep, -configuration.maximumBackwardStep)
        currentProgress = Self.clamp(currentProgress + limitedStep)
        return currentProgress
    }

    private static func clamp(_ progress: Double) -> Double {
        min(max(progress, 0), 1)
    }
}
