import XCTest
@testable import FloatCue

final class TeleprompterScrollModeTests: XCTestCase {
    func testListeningEnablesVoiceFollowing() {
        var state = TeleprompterScrollModeState()
        state.apply(.listening)

        XCTAssertEqual(state.mode, .voiceFollowing)
        XCTAssertNil(state.fallbackReason)
    }

    func testEveryUnavailableStateFallsBackToFixedSpeed() {
        let cases: [(SpeechRecognitionUnavailability, VoiceFollowFallbackReason)] = [
            (.microphonePermissionDenied, .permissionDenied),
            (.speechPermissionDenied, .permissionDenied),
            (.recognizerUnavailable, .recognizerUnavailable),
            (.onDeviceRecognitionUnsupported, .onDeviceRecognitionUnavailable),
            (.invalidAudioInput, .invalidAudioInput)
        ]

        for (unavailability, expectedReason) in cases {
            var state = TeleprompterScrollModeState()
            state.apply(.listening)
            state.apply(.unavailable(unavailability))

            XCTAssertEqual(state.mode, .fixedSpeed)
            XCTAssertEqual(state.fallbackReason, expectedReason)
        }
    }

    func testInterruptionAndBufferTimeoutFallBackImmediately() {
        var interrupted = TeleprompterScrollModeState()
        interrupted.apply(.listening)
        interrupted.apply(.failed("audio_session_interrupted"))
        XCTAssertEqual(interrupted.mode, .fixedSpeed)
        XCTAssertEqual(interrupted.fallbackReason, .audioInterrupted)

        var timedOut = TeleprompterScrollModeState()
        timedOut.apply(.listening)
        timedOut.apply(.failed("audio_buffer_timeout"))
        XCTAssertEqual(timedOut.mode, .fixedSpeed)
        XCTAssertEqual(timedOut.fallbackReason, .noAudioBuffers)
    }

    func testRecognitionEndFallsBackAfterListening() {
        var state = TeleprompterScrollModeState()
        state.apply(.listening)
        state.apply(.ready)

        XCTAssertEqual(state.mode, .fixedSpeed)
        XCTAssertEqual(state.fallbackReason, .recognitionEnded)
    }

    @MainActor
    func testModeChangesPreservePiPProgressAndPlayback() {
        let manager = TeleprompterPiPManager.shared
        manager.updateState(elapsedTime: 37, isPlaying: true, currentWordIndex: 11)

        manager.updateScrollMode(.voiceFollowing)
        manager.updateScrollMode(.fixedSpeed)

        XCTAssertEqual(manager.elapsedTime, 37)
        XCTAssertTrue(manager.isPlaying)
        manager.cleanup()
    }
}
