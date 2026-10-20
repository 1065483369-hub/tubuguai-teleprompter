import XCTest

/// 跟读进度可见性。用户原话：「我现在看不到我的跟读进度」。
/// 原因是未读色 #C4CBD6（亮度 202）和当前字白色（255）只差 53，几乎分不出。
/// 现在当前字用品牌绿 + 底色块，另加顶部进度条与百分比。
final class HighlightTests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func shot(_ app: XCUIApplication, _ n: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = n; a.lifetime = .keepAlways; add(a)
    }

    func testProgressVisibleAtMidScript() {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_SCRIPT"] = [
            "大家好，欢迎来到今天的直播。",
            "那么我们接下来聊聊提词器的实现原理。",
            "注意这里是关键的部分，效率提升了35%。",
            "第一步是流式语音识别，把音频送进引擎。",
            "第二步是文本对齐，这一步决定了好不好用。",
        ].joined(separator: "\n")
        app.launchEnvironment["UITEST_AUTOSTART"] = "1"
        app.launchEnvironment["UITEST_NOCAM"] = "1"
        // 直接落在稿子中段，才看得出三档区分
        app.launchEnvironment["UITEST_READCHAR"] = "40"
        app.launch()
        sleep(4)
        shot(app, "01-中段跟读进度")

        // 百分比标签必须出现且不是 0%
        let pct = app.staticTexts.matching(
            NSPredicate(format: "label ENDSWITH '%'")).firstMatch
        XCTAssertTrue(pct.waitForExistence(timeout: 5), "应显示百分比")
        let v = pct.label
        print("HL 百分比=\(v)")
        let n = Int(v.replacingOccurrences(of: "%", with: "")) ?? -1
        XCTAssertTrue(n > 5 && n < 95, "中段进度应在 5~95% 之间，实际 \(v)")

        // 提词文字仍在
        XCTAssertTrue(app.textViews["prompterText"].exists, "提词区应存在")
    }
}
