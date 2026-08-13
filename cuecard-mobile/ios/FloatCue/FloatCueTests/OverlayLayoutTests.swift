import XCTest
@testable import FloatCue

final class OverlayLayoutTests: XCTestCase {
    func testOrientationFollowsNonSquareSize() {
        XCTAssertEqual(OverlayLayout.orientation(for: CGSize(width: 390, height: 844)), .portrait)
        XCTAssertEqual(OverlayLayout.orientation(for: CGSize(width: 844, height: 390)), .landscape)
    }

    func testAmbiguousSizeKeepsPreviousOrientation() {
        XCTAssertEqual(
            OverlayLayout.orientation(for: CGSize(width: 400, height: 400), previous: .landscape),
            .landscape
        )
    }

    func testAspectRatioRotatesWithoutChangingPreset() {
        XCTAssertEqual(
            OverlayLayout.aspectRatio(baseLandscapeRatio: 16.0 / 9.0, orientation: .landscape),
            16.0 / 9.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            OverlayLayout.aspectRatio(baseLandscapeRatio: 16.0 / 9.0, orientation: .portrait),
            9.0 / 16.0,
            accuracy: 0.0001
        )
    }

    func testPreferredSizeStaysInsideScreenBounds() {
        let screen = CGRect(x: 0, y: 0, width: 390, height: 844)
        let portrait = OverlayLayout.preferredContentSize(
            in: screen,
            baseLandscapeRatio: 16.0 / 9.0,
            orientation: .portrait
        )
        let landscape = OverlayLayout.preferredContentSize(
            in: screen,
            baseLandscapeRatio: 16.0 / 9.0,
            orientation: .landscape
        )

        XCTAssertLessThanOrEqual(portrait.width, screen.width)
        XCTAssertLessThanOrEqual(portrait.height, screen.height)
        XCTAssertLessThan(portrait.width, portrait.height)
        XCTAssertGreaterThan(landscape.width, landscape.height)
    }

    @MainActor
    func testOrientationChangePreservesPlaybackState() {
        let manager = TeleprompterPiPManager.shared
        manager.updateState(elapsedTime: 42, isPlaying: true, currentWordIndex: 17)

        manager.updateOverlayOrientation(for: CGSize(width: 844, height: 390))

        XCTAssertEqual(manager.overlayOrientation, .landscape)
        XCTAssertEqual(manager.elapsedTime, 42)
        XCTAssertTrue(manager.isPlaying)
        manager.cleanup()
    }
}
