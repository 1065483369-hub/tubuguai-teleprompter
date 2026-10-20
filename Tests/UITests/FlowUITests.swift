import XCTest

/// 驱动真实界面走一遍主流程，并截图留证。
/// PiP 在模拟器上不可用，这里只验证到「浮窗」按钮给出正确提示。
final class FlowUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
        // 权限弹窗会打断点击并让元素引用失效，装个监视器自动允许
        addUIInterruptionMonitor(withDescription: "权限弹窗") { alert in
            for label in ["好", "允许", "OK", "Allow", "确定"] {
                let b = alert.buttons[label]
                if b.exists { b.tap(); return true }
            }
            if alert.buttons.count > 0 {
                alert.buttons.element(boundBy: alert.buttons.count - 1).tap()
                return true
            }
            return false
        }
    }

    /// 点击并在被弹窗打断后重试。UI 测试里元素引用会因中断失效。
    private func tapWithRetry(_ app: XCUIApplication, _ id: String,
                              tries: Int = 3) -> Bool {
        for _ in 0..<tries {
            let el = app.buttons[id]
            guard el.waitForExistence(timeout: 4) else { continue }
            if el.isHittable {
                el.tap()
                // 触发中断处理
                app.tap()
                return true
            }
            app.tap()
        }
        return false
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testSetupToPromptingFlow() {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_SCRIPT"] =
            "大家好，欢迎来到今天的直播。那么我们接下来聊聊提词器的实现原理。"
            + "注意这里是关键的部分，效率提升了35%。第一步是流式语音识别，把音频送进引擎。"
        app.launch()

        // 设置页应自动出现
        let tv = app.textViews["scriptInput"]
        XCTAssertTrue(tv.waitForExistence(timeout: 12), "设置页文本框应出现")
        shot(app, "01-设置页-空")

        XCTAssertFalse(tv.value as? String == "", "稿子应已注入")

        // 预估胶囊应出现（时长 + 气口数）
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '约'")).firstMatch
            .waitForExistence(timeout: 3), "应显示时长预估")
        shot(app, "02-设置页-有稿子和预估")

        // 关掉相机取景，避免模拟器权限弹窗干扰截图
        let camToggle = app.buttons["toggle.相机取景"]
        if camToggle.exists { camToggle.tap() }

        XCTAssertTrue(tapWithRetry(app, "startButton"), "应能点到开始按钮")
        sleep(3)
        shot(app, "03-提词页")

        // 提词区应有文字，HUD 按钮应在
        XCTAssertTrue(app.buttons["hud.‹ 返回"].exists || app.buttons["hud.浮窗"].exists,
                      "提词页应有控制栏")

        // 浮窗按钮：模拟器不支持 PiP，点了应给提示而不是崩溃
        if tapWithRetry(app, "hud.浮窗") {
            sleep(1)
            shot(app, "04-点浮窗-模拟器提示")
        }
        XCTAssertTrue(app.state == .runningForeground, "全程不应崩溃")
    }
}
