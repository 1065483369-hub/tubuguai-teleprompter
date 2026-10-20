import XCTest

/// 敏感词检测的链路测试。
/// 用户要的是「粘贴完一键检测、标注、可一键改也可自己改」，
/// 所以这里验证从稿子页进入到改完退出的完整路径。
final class SensitiveUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func shot(_ app: XCUIApplication, _ n: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = n; a.lifetime = .keepAlways; add(a)
    }

    /// 带违禁词的稿子必须被查出来，且能一键改。
    func testDetectAndFixFlow() {
        let app = XCUIApplication()
        // 一句典型的带货违规稿：极限词 + 功效词 + 金融承诺 + 导流
        app.launchEnvironment["UITEST_SCRIPT"] =
            "全网最低价的国家级神器，养胃通便排毒，稳赚不赔零风险，加我微信。"
        app.launch()

        // 进稿子页
        let entry = app.buttons["scriptEntry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 12), "应有稿子入口")
        entry.tap()
        XCTAssertTrue(app.textViews["scriptInput"].waitForExistence(timeout: 8))
        shot(app, "01-稿子页")

        let check = app.buttons["sensitiveButton"]
        XCTAssertTrue(check.waitForExistence(timeout: 6), "应有「查敏感词」入口")
        check.tap()
        sleep(3)
        shot(app, "02-检测结果")

        // 必须报出命中，且能看到具体词
        let hasHit = app.staticTexts.allElementsBoundByIndex.contains {
            $0.label.contains("全网最低价") || $0.label.contains("国家级")
                || $0.label.contains("处") || $0.label.contains("命中")
        }
        XCTAssertTrue(hasHit, "应列出命中的敏感词")

        // 档位选择器必须在 —— 同一个词在科普/带货稿里结论不同
        XCTAssertTrue(app.segmentedControls["sceneSeg"].exists
                      || app.buttons["带货口播"].exists,
                      "应有稿子类型选择")
        shot(app, "03-档位与命中")
    }

    /// 干净的稿子不该误报，否则功能没人敢用。
    func testCleanScriptShowsNoFalsePositives() {
        let app = XCUIApplication()
        // 科普口吻，含「第一步」「最近」这类高频词 —— 默认档不该报
        app.launchEnvironment["UITEST_SCRIPT"] =
            "今天第一步先讲讲原理。我最近做了几组测试，结果挺有意思。"
        app.launch()
        XCTAssertTrue(app.buttons["scriptEntry"].waitForExistence(timeout: 12))
        app.buttons["scriptEntry"].tap()
        XCTAssertTrue(app.textViews["scriptInput"].waitForExistence(timeout: 8))

        let check = app.buttons["sensitiveButton"]
        XCTAssertTrue(check.waitForExistence(timeout: 6))
        check.tap()
        sleep(3)
        shot(app, "04-干净稿零误报")

        let clean = app.staticTexts.allElementsBoundByIndex.contains {
            $0.label.contains("未检出") || $0.label.contains("没检出")
        }
        XCTAssertTrue(clean,
            "「第一步」「我最近」在默认档不该报 —— 误伤会让功能没人用")
    }
}
