import Speech
import XCTest
@testable import CueCard

final class MandarinSpeechRecognitionServiceTests: XCTestCase {
    func testLocaleIsFixedToMainlandMandarin() {
        XCTAssertEqual(MandarinSpeechRecognitionService.localeIdentifier, "zh-CN")
    }

    @MainActor
    func testRecognitionRequestForcesOnDevicePartialResults() {
        let request = MandarinSpeechRecognitionService.makeRecognitionRequest()

        XCTAssertTrue(request.requiresOnDeviceRecognition)
        XCTAssertTrue(request.shouldReportPartialResults)
        XCTAssertTrue(request.addsPunctuation)
    }

    func testOnlyReadyStateCanStart() {
        XCTAssertTrue(MandarinSpeechRecognitionState.ready.canStart)
        XCTAssertFalse(MandarinSpeechRecognitionState.idle.canStart)
        XCTAssertFalse(MandarinSpeechRecognitionState.listening.canStart)
        XCTAssertFalse(
            MandarinSpeechRecognitionState
                .unavailable(.onDeviceRecognitionUnsupported)
                .canStart
        )
    }
}
