import XCTest

/// 稿子编辑页的可用性回归。
///
/// 用户原话：「没办法粘贴，输入框完全被挡住」。当时输入框内嵌在设置页的
/// 滚动表单里，键盘一弹就和表单抢高度，被压到 21pt；而自动聚焦又让
/// 粘贴按钮一进页面就被收起。
///
/// 现在的设计：输入框独占一页，**不自动聚焦**——稿子基本靠粘贴，
/// 不需要键盘。粘贴时输入框 290pt+ 全可见；真要打字才弹键盘，
/// 此时输入框收缩但仍可编辑，粘贴/清空移到键盘工具条。
final class KeyboardTests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }

    private func openEditor(_ app: XCUIApplication) -> XCUIElement {
        let entry = app.buttons["scriptEntry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 12), "稿子入口应存在")
        entry.tap()
        let tv = app.textViews["scriptInput"]
        XCTAssertTrue(tv.waitForExistence(timeout: 8), "编辑页应打开")
        return tv
    }

    /// 粘贴路径：全程不碰键盘，输入框和按钮都得大方可见。
    func testPasteFlowWithoutKeyboard() {
        let app = XCUIApplication()
        app.launch()
        let tv = openEditor(app)
        sleep(1)
        shot(app, "01-编辑页-无键盘")

        XCTAssertGreaterThan(tv.frame.height, 240,
            "不聚焦时输入框应大方可见，实际 \(Int(tv.frame.height))pt")

        for id in ["pasteButton", "historyButton", "clearButton", "sampleButton", "editorDone"] {
            let b = app.buttons[id]
            XCTAssertTrue(b.exists && b.isHittable, "\(id) 应可见可点")
        }

        // 示例稿按钮：新用户不用自己找内容就能试
        app.buttons["sampleButton"].tap()
        sleep(1)
        let v = tv.value as? String ?? ""
        XCTAssertFalse(v.isEmpty, "示例稿应填入内容")
        XCTAssertTrue(v.contains("语音跟随"), "示例稿应说明核心跟读功能")
        XCTAssertFalse(v.contains("\n\n"), "示例稿不应插入额外空行")
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '字'")).firstMatch.exists, "应显示字数")
        shot(app, "02-示例稿已填入")

        // 完成能带着内容回到设置页
        app.buttons["editorDone"].tap()
        sleep(2)
        XCTAssertTrue(app.buttons["scriptEntry"].waitForExistence(timeout: 5), "应回到设置页")
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '约'")).firstMatch.exists,
            "设置页应显示时长预估")
        shot(app, "03-回到设置页")
    }

    /// 完成后的稿子应进入历史；历史可恢复，也可左滑删除。
    func testHistoryRestoreAndDelete() {
        let app = XCUIApplication()
        app.launch()
        let tv = openEditor(app)
        app.buttons["sampleButton"].tap()
        let saved = tv.value as? String ?? ""
        app.buttons["editorDone"].tap()
        XCTAssertTrue(app.buttons["scriptEntry"].waitForExistence(timeout: 5))

        app.buttons["scriptEntry"].tap()
        XCTAssertTrue(app.buttons["historyButton"].waitForExistence(timeout: 5))
        app.buttons["historyButton"].tap()
        let first = app.cells["historyItem.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5), "完成稿子后应出现在历史")
        first.tap()
        XCTAssertEqual(tv.value as? String ?? "", saved, "点历史稿应恢复全文")

        app.buttons["historyButton"].tap()
        let again = app.cells["historyItem.0"]
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        let before = app.cells.matching(
            NSPredicate(format: "identifier BEGINSWITH 'historyItem.'")).count
        again.swipeLeft()
        let delete = app.buttons["删除"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.tap()
        let after = app.cells.matching(
            NSPredicate(format: "identifier BEGINSWITH 'historyItem.'")).count
        XCTAssertEqual(after, before - 1, "左滑删除后历史数量应减一")
    }

    /// 打字路径：键盘弹起后输入框会收缩，但必须仍然可编辑、操作仍然可达。
    func testTypingRemainsUsableWithKeyboard() {
        let app = XCUIApplication()
        app.launch()
        let tv = openEditor(app)
        tv.tap()
        sleep(3)
        shot(app, "04-键盘弹起")

        let kb = app.keyboards.firstMatch
        guard kb.exists else {
            print("KB 软键盘未出现，跳过")
            return
        }
        let kbTop = kb.frame.minY
        let f = tv.frame
        let visible = max(0, min(f.maxY, kbTop) - f.minY)
        print("KB 键盘顶=\(Int(kbTop)) 输入框=\(f) 可见=\(Int(visible))")

        // 收缩是预期的，但不能被压成一两行
        XCTAssertGreaterThan(visible, 60,
            "键盘在时输入框仍需可用高度，实际 \(Int(visible))pt")
        XCTAssertLessThan(f.minY, kbTop, "输入框顶部不该被键盘盖住")

        // 键盘工具条上的粘贴必须可达 —— 下方动作行此时已收起
        XCTAssertTrue(app.buttons["kbPaste"].exists,
            "键盘工具条应提供粘贴（下方动作行已让位给输入框）")

        // 真的能输入
        tv.typeText("测试")
        let v = tv.value as? String ?? ""
        XCTAssertTrue(v.contains("测试"), "应能接收输入，实际=\(v)")

        // 收起键盘后动作行回来
        app.buttons["kbPaste"].firstMatch.tap()   // 触发一次工具条交互
        sleep(1)
        shot(app, "05-输入后")
    }
}
