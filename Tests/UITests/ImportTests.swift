import XCTest

/// 导入按钮必须可见可点。四个按钮挤在一行，容易被压掉。
final class ImportTests: XCTestCase {
    func testEditorActionsAllReachable() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["scriptEntry"].waitForExistence(timeout: 12))
        app.buttons["scriptEntry"].tap()
        XCTAssertTrue(app.textViews["scriptInput"].waitForExistence(timeout: 8))
        sleep(1)
        for id in ["pasteButton", "importButton", "clearButton", "sampleButton"] {
            let b = app.buttons[id]
            XCTAssertTrue(b.exists, "\(id) 应存在")
            XCTAssertTrue(b.isHittable, "\(id) 应可点（四按钮一行别被挤掉）")
            print("BTN \(id) frame=\(b.frame)")
        }
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = "editor-4-actions"; a.lifetime = .keepAlways; add(a)
    }
}
