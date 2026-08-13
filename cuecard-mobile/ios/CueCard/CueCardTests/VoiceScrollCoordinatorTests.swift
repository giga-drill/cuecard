import XCTest
@testable import CueCard

final class VoiceScrollCoordinatorTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 10_000)

    func testNormalAdvanceUsesLimitedSmoothStep() {
        let coordinator = VoiceScrollCoordinator()
        coordinator.receive(alignment(progress: 0.8), at: start)

        let firstTick = coordinator.tick(at: start.addingTimeInterval(0.03))

        XCTAssertGreaterThan(firstTick, 0)
        XCTAssertLessThanOrEqual(firstTick, 0.025)
        XCTAssertLessThan(firstTick, coordinator.targetProgress)
    }

    func testPauseStopsProgressAfterOneSecond() {
        let coordinator = VoiceScrollCoordinator()
        coordinator.receive(alignment(progress: 0.4), at: start)
        let beforePause = coordinator.tick(at: start.addingTimeInterval(0.2))

        let afterPause = coordinator.tick(at: start.addingTimeInterval(1.1))

        XCTAssertEqual(afterPause, beforePause)
        XCTAssertFalse(coordinator.isSpeaking)
    }

    func testNewSpeechResumesAfterPause() {
        let coordinator = VoiceScrollCoordinator()
        coordinator.receive(alignment(progress: 0.3), at: start)
        _ = coordinator.tick(at: start.addingTimeInterval(1.2))

        coordinator.receive(alignment(progress: 0.5), at: start.addingTimeInterval(1.3))
        let resumed = coordinator.tick(at: start.addingTimeInterval(1.31))

        XCTAssertTrue(coordinator.isSpeaking)
        XCTAssertGreaterThan(resumed, 0)
    }

    func testRecognitionCorrectionCannotJumpBackward() {
        let coordinator = VoiceScrollCoordinator(initialProgress: 0.5)
        coordinator.receive(alignment(progress: 0.2), at: start)

        XCTAssertEqual(coordinator.targetProgress, 0.45, accuracy: 0.0001)
        let corrected = coordinator.tick(at: start.addingTimeInterval(0.03))
        XCTAssertGreaterThanOrEqual(corrected, 0.488)
        XCTAssertLessThan(corrected, 0.5)
    }

    func testSmallRollbackIsSmoothed() {
        let coordinator = VoiceScrollCoordinator(initialProgress: 0.5)
        coordinator.receive(alignment(progress: 0.48), at: start)

        let corrected = coordinator.tick(at: start.addingTimeInterval(0.03))

        XCTAssertGreaterThan(corrected, 0.48)
        XCTAssertLessThan(corrected, 0.5)
    }

    private func alignment(progress: Double) -> MandarinAlignment {
        MandarinAlignment(
            tokenIndex: Int(progress * 100),
            progress: progress,
            confidence: 1,
            matchedRange: 0..<4
        )
    }
}
