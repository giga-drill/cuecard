import XCTest
@testable import CueCard

final class MandarinScriptAlignerTests: XCTestCase {
    func testNormalizerUnifiesPunctuationWidthCaseAndTraditionalChinese() {
        XCTAssertEqual(
            MandarinTextNormalizer.normalizedText("臺灣，你好！ＷＯＲＬＤ １２３"),
            "台湾你好world123"
        )
        XCTAssertEqual(
            MandarinTextNormalizer.normalizedText("开始[note 微笑]继续"),
            "开始继续"
        )
    }

    func testNormalReadingAdvancesToRecognizedPosition() {
        let aligner = MandarinScriptAligner(script: "大家好今天我们来讨论如何拍摄一段自然流畅的视频")

        let alignment = aligner.align(recognitionText: "大家好今天我们来讨论")

        XCTAssertNotNil(alignment)
        XCTAssertGreaterThanOrEqual(alignment?.tokenIndex ?? 0, 10)
        XCTAssertLessThan(alignment?.progress ?? 1, 0.7)
    }

    func testRepeatedPartialResultDoesNotAdvanceAgainDuringPause() {
        let aligner = MandarinScriptAligner(script: "大家好今天我们开始介绍这个产品的主要功能")
        let first = aligner.align(recognitionText: "大家好今天我们开始")
        let repeated = aligner.align(recognitionText: "大家好今天我们开始")

        XCTAssertNotNil(first)
        XCTAssertNil(repeated)
    }

    func testSingleCharacterMistakeStillFindsLocalPosition() {
        let aligner = MandarinScriptAligner(script: "今天我们介绍一个非常实用的悬浮提词工具")

        let alignment = aligner.align(recognitionText: "今天我们介绍一个非常食用的悬浮")

        XCTAssertNotNil(alignment)
        XCTAssertGreaterThan(alignment?.confidence ?? 0, 0.6)
    }

    func testSkippingOneSentenceCanRecoverForward() {
        let aligner = MandarinScriptAligner(script: "第一段介绍产品背景。第二段说明准备工作。第三段开始正式演示功能。")
        _ = aligner.align(recognitionText: "第一段介绍产品背景")

        let skipped = aligner.align(recognitionText: "第三段开始正式演示功能")

        XCTAssertNotNil(skipped)
        XCTAssertGreaterThan(skipped?.progress ?? 0, 0.55)
    }

    func testRepeatingPreviousPhraseCanMoveBackOnlyLocally() {
        let aligner = MandarinScriptAligner(script: "先打开相机然后调整画面接着开始录制最后检查声音")
        _ = aligner.align(recognitionText: "先打开相机然后调整画面接着开始录制")

        let repeated = aligner.align(recognitionText: "然后调整画面")

        XCTAssertNotNil(repeated)
        XCTAssertLessThan(abs((repeated?.tokenIndex ?? 0) - 10), 20)
    }

    func testShortCommonPhraseCannotTriggerFarJump() {
        let aligner = MandarinScriptAligner(
            script: "今天我们介绍开场内容然后继续解释很多细节最后今天我们介绍结束内容"
        )

        let alignment = aligner.align(recognitionText: "今天我们")

        XCTAssertNotNil(alignment)
        XCTAssertLessThanOrEqual(alignment?.tokenIndex ?? .max, 24)
    }

    func testPinyinOnlySimilarityCannotCauseFarJump() {
        let aligner = MandarinScriptAligner(
            script: "现在开始介绍功能中间还有许多详细说明最后才会提到线在开始"
        )

        let alignment = aligner.align(recognitionText: "现在开始")

        XCTAssertNotNil(alignment)
        XCTAssertLessThanOrEqual(alignment?.tokenIndex ?? .max, 24)
    }
}
