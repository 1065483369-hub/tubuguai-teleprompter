import XCTest
@testable import Prompter

final class ScriptPolisherTests: XCTestCase {
    func testBasicCleanupKeepsNumbersAndProductFacts() {
        let source = "本产品售价 199 元，具有以下特点。\n\n此外，支持 30 天试用。"
        let result = ScriptPolisher.basicCleanup(source, scene: .selling)
        XCTAssertTrue(result.contains("199 元"))
        XCTAssertTrue(result.contains("30 天试用"))
        XCTAssertFalse(result.contains("\n\n"))
        XCTAssertFalse(result.contains("限时优惠"))
    }

    func testKnowledgeSceneSimplifiesKnownWrittenTransition() {
        let result = ScriptPolisher.basicCleanup("具体而言，这个方法有两步。", scene: .knowledge)
        XCTAssertEqual(result, "具体说，这个方法有两步。")
    }

    func testPlayfulSceneDoesNotInventAStory() {
        let result = ScriptPolisher.basicCleanup("接下来，打开设置。", scene: .playful)
        XCTAssertEqual(result, "然后，打开设置。")
    }

    func testNoRecognizedExpressionLeavesWordsIntact() {
        let source = "这段稿子已经很顺口。"
        XCTAssertEqual(ScriptPolisher.basicCleanup(source, scene: .natural), source)
    }
}
