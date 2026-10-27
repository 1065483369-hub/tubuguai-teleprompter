import XCTest

final class PolishUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testGenerateApplyAndUndo() {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_SCRIPT"] = "本产品具有以下特点。"
        app.launch()

        XCTAssertTrue(app.buttons["scriptEntry"].waitForExistence(timeout: 12))
        app.buttons["scriptEntry"].tap()
        let input = app.textViews["scriptInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["polishButton"].isHittable)
        app.buttons["polishButton"].tap()

        let scenes = app.segmentedControls["polishScene"]
        XCTAssertTrue(scenes.waitForExistence(timeout: 5))
        scenes.buttons["卖货种草"].tap()
        app.buttons["polishGenerate"].tap()

        let result = app.textViews["polishResult"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        let apply = app.buttons["polishApply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: apply)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 15), .completed)
        XCTAssertTrue(apply.isEnabled)
        apply.tap()

        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertNotEqual(input.value as? String, "本产品具有以下特点。")
        let undo = app.buttons["undoPolish"]
        XCTAssertTrue(undo.isHittable)
        undo.tap()
        XCTAssertEqual(input.value as? String, "本产品具有以下特点。")
    }
}
