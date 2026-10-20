import XCTest

/// 窗口必须拿到真正的全屏尺寸。
///
/// 之前 Info.plist 缺 UILaunchScreen + UIApplicationSceneManifest，
/// iOS 按兼容模式运行，把窗口信箱化成 402x603（2:3），上下各留 135pt 黑边 ——
/// 用户看到的就是「整个 App 的比例是 3:4」。
final class WindowSizeTests: XCTestCase {

    func testWindowFillsScreen() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["scriptEntry"].waitForExistence(timeout: 12))

        let win = app.windows.firstMatch.frame
        print("WIN 窗口=\(win)")

        // 窗口必须从 y=0 开始，不能有信箱化偏移
        XCTAssertEqual(win.minY, 0, accuracy: 1,
            "窗口顶部应贴屏幕顶，实际 y=\(win.minY)（信箱化）")

        // 现代 iPhone 宽高比 ≈ 2.16（19.5:9）。2:3=0.667 说明被信箱化了
        let ratio = win.width / win.height
        print("WIN 比例=\(String(format: "%.3f", ratio))")
        XCTAssertLessThan(ratio, 0.55,
            "宽高比 \(String(format: "%.3f", ratio)) 太方，说明窗口被信箱化")

        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = "fullscreen"; a.lifetime = .keepAlways; add(a)
    }
}
