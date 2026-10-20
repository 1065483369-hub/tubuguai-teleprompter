import XCTest

/// 完整链路守卫。
///
/// 用户原话：「没有任何返回键了，也没有录制键」。
/// 起因是我加字号按钮时把六个位置占满，返回/录制/翻转/停止的代码都还在，
/// 但没有任何按钮能触发 —— 功能等于不存在。
/// 这组测试断言每个必需操作都有可点入口，防止再被挤掉。
final class JourneyTests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    /// 每个用例都用全新进程。三个用例共享 App 实例会互相污染 ——
    /// 前一个点过按钮留下的 presented 状态会让后一个 present 被静默忽略。
    private func freshApp(script: String) -> XCUIApplication {
        let app = XCUIApplication()
        // 不在 launch 前调 terminate() —— 会让 XCUIApplication 进入
        // 奇怪状态，后续 present 观察不到。launch 本身就会重启进程。
        app.launchEnvironment["UITEST_SCRIPT"] = script
        app.launchEnvironment["UITEST_AUTOSTART"] = "1"
        app.launchEnvironment["UITEST_NOCAM"] = "1"
        app.launch()
        return app
    }

    private func shot(_ app: XCUIApplication, _ n: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = n; a.lifetime = .keepAlways; add(a)
    }

    /// HUD 3.5 秒无操作会淡出，点之前先唤回。
    /// 这也顺带验证了唤回手势本身可用。
    private func tapHUD(_ app: XCUIApplication, _ id: String) -> Bool {
        // 先唤回 HUD 再点。顺序很重要：点正文会重置隐藏计时，
        // 之后按钮才稳定可点。（探针验证过这个序列可靠。）
        app.textViews["prompterText"].tap()
        usleep(700_000)
        for _ in 0..<3 {
            let b = app.buttons[id]
            if b.exists, b.isHittable {
                b.tap()
                return true
            }
            app.textViews["prompterText"].tap()
            usleep(700_000)
        }
        return false
    }

    /// 提词页必须能做完念稿全程需要的每件事。
    func testPrompterHasEveryEssentialControl() {
        let app = freshApp(script: "你好，今天天气很好。\n那么我们接下来聊聊提词器的实现原理。")
        sleep(5)
        shot(app, "01-提词页-两行HUD")

        // 每一项都是走完链路必需的。缺一个就有死路。
        let essentials: [(String, String)] = [
            ("hud.‹ 返回",     "返回改稿 —— 没有它进了提词页就出不来"),
            ("hud.● 录制",   "录制 —— 相机开着却录不了等于功能不存在"),
            ("hud.翻转",     "翻转摄像头"),
            ("hud.浮窗",     "开浮窗"),
            ("hud.暂停",     "暂停/继续 —— 说错一句不该从头重念"),
            ("hud.↑ 上一句", "回上一句"),
            ("hud.↓ 下一句", "跳下一句"),
            ("hud.A−",       "缩小字号"),
            ("hud.A+",       "放大字号"),
        ]
        for (id, why) in essentials {
            // 先唤回 HUD，否则淡出后一律 not hittable
            if !app.buttons[id].isHittable { app.textViews["prompterText"].tap(); usleep(600_000) }
            let b = app.buttons[id]
            XCTAssertTrue(b.exists, "缺少「\(id)」：\(why)")
            XCTAssertTrue(b.isHittable, "「\(id)」存在但点不到：\(why)")
        }
    }

    /// 返回改稿这条路必须真的走得通 —— 而不只是按钮存在。
    func testCanReturnToEditorAndBack() {
        let app = freshApp(script: "你好，今天天气很好。")
        sleep(5)

        XCTAssertTrue(app.buttons["hud.‹ 返回"].waitForExistence(timeout: 8), "应有返回入口")
        XCTAssertTrue(tapHUD(app, "hud.‹ 返回"), "应能点到「返回」回上一级")
        // 用 waitForExistence 等，别用固定 sleep —— present 动画时长不确定
        XCTAssertTrue(app.buttons["scriptEntry"].waitForExistence(timeout: 10),
                      "点「稿子」应回到设置页")
        XCTAssertTrue(app.buttons["startButton"].waitForExistence(timeout: 5),
                      "设置页应有开始按钮")
        shot(app, "02-返回设置页")

        // 再点开始能重新进提词页 —— 闭环
        app.buttons["startButton"].tap()
        XCTAssertTrue(app.buttons["hud.暂停"].waitForExistence(timeout: 8),
                      "应能重新进入提词页")
        shot(app, "03-闭环回到提词页")
    }

    /// HUD 自动隐藏后必须能唤回，否则按钮消失就等于没有。
    func testHUDCanBeRecalledAfterAutoHide() {
        let app = freshApp(script: "你好，今天天气很好。那么我们继续讲下去。")
        sleep(5)

        let pause = app.buttons["hud.暂停"]
        XCTAssertTrue(pause.waitForExistence(timeout: 6))
        // HUD 3.5 秒无操作淡出
        sleep(6)
        shot(app, "04-HUD已隐藏")

        // 轻点正文唤回
        app.textViews["prompterText"].tap()
        sleep(1)
        XCTAssertTrue(pause.isHittable, "轻点正文应唤回 HUD")
        shot(app, "05-HUD已唤回")
    }
}
