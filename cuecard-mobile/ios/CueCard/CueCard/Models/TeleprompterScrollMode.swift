import Foundation

enum TeleprompterScrollMode: String, Equatable, Sendable {
    case fixedSpeed
    case voiceFollowing

    var title: String {
        switch self {
        case .fixedSpeed:
            return "Fixed speed"
        case .voiceFollowing:
            return "Voice follow"
        }
    }

    var systemImage: String {
        switch self {
        case .fixedSpeed:
            return "speedometer"
        case .voiceFollowing:
            return "waveform"
        }
    }
}

enum VoiceFollowFallbackReason: Equatable, Sendable {
    case permissionDenied
    case onDeviceRecognitionUnavailable
    case recognizerUnavailable
    case invalidAudioInput
    case audioInterrupted
    case noAudioBuffers
    case recognitionEnded
    case recognitionFailed
}

struct TeleprompterScrollModeState: Equatable, Sendable {
    private(set) var mode: TeleprompterScrollMode = .fixedSpeed
    private(set) var fallbackReason: VoiceFollowFallbackReason?

    mutating func apply(_ speechState: MandarinSpeechRecognitionState) {
        switch speechState {
        case .listening:
            mode = .voiceFollowing
            fallbackReason = nil
        case .unavailable(let reason):
            fallBack(reason: Self.map(reason))
        case .failed(let message):
            fallBack(reason: Self.mapFailure(message))
        case .ready:
            if mode == .voiceFollowing {
                fallBack(reason: .recognitionEnded)
            }
        case .idle, .requestingPermissions:
            break
        }
    }

    mutating func fallBack(reason: VoiceFollowFallbackReason) {
        mode = .fixedSpeed
        fallbackReason = reason
    }

    private static func map(_ reason: SpeechRecognitionUnavailability) -> VoiceFollowFallbackReason {
        switch reason {
        case .microphonePermissionDenied, .speechPermissionDenied:
            return .permissionDenied
        case .onDeviceRecognitionUnsupported:
            return .onDeviceRecognitionUnavailable
        case .recognizerUnavailable:
            return .recognizerUnavailable
        case .invalidAudioInput:
            return .invalidAudioInput
        }
    }

    private static func mapFailure(_ message: String) -> VoiceFollowFallbackReason {
        switch message {
        case "audio_session_interrupted":
            return .audioInterrupted
        case "audio_buffer_timeout":
            return .noAudioBuffers
        default:
            return .recognitionFailed
        }
    }
}
