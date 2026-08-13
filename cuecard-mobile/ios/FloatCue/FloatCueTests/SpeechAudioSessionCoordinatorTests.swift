import AVFoundation
import XCTest
@testable import FloatCue

final class SpeechAudioSessionCoordinatorTests: XCTestCase {
    func testBufferMonitorThrottlesDiagnosticsButTracksLatestBuffer() {
        let monitor = AudioBufferPulseMonitor()
        let start = Date(timeIntervalSince1970: 1_000)
        monitor.reset(at: start)

        XCTAssertTrue(monitor.recordBuffer(at: start, diagnosticInterval: 1))
        XCTAssertFalse(monitor.recordBuffer(at: start.addingTimeInterval(0.2), diagnosticInterval: 1))
        XCTAssertTrue(monitor.recordBuffer(at: start.addingTimeInterval(1.1), diagnosticInterval: 1))
        XCTAssertEqual(
            monitor.secondsSinceLastBuffer(at: start.addingTimeInterval(1.6)),
            0.5,
            accuracy: 0.001
        )
    }

    @MainActor
    func testInterruptionNotificationProducesStructuredEvent() async {
        let diagnostics = SpeechDiagnostics()
        let coordinator = SpeechAudioSessionCoordinator(diagnostics: diagnostics)
        let received = expectation(description: "interruption callback")
        coordinator.onEvent = { event in
            if event == .interruptionBegan {
                received.fulfill()
            }
        }

        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]
        )

        await fulfillment(of: [received], timeout: 1)
        XCTAssertEqual(diagnostics.events.last?.kind, .interruptionBegan)
    }

    @MainActor
    func testRouteChangeNotificationProducesStructuredReason() async {
        let diagnostics = SpeechDiagnostics()
        let coordinator = SpeechAudioSessionCoordinator(diagnostics: diagnostics)
        let received = expectation(description: "route callback")
        coordinator.onEvent = { event in
            if case .routeChanged = event {
                received.fulfill()
            }
        }

        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue]
        )

        await fulfillment(of: [received], timeout: 1)
        XCTAssertEqual(diagnostics.events.last?.kind, .routeChanged)
        XCTAssertNotNil(diagnostics.events.last?.details["reason"])
    }
}
