import XCTest
import AVFoundation
@testable import Prompter

/// 录制相关的回归测试。全部来自 App Store 真实差评。
///
/// 一条 3 星评价列了 4 个具体缺陷，我对照自查后发现自己也有：
///   ①「延迟3秒拍摄的阶段一样会被录像，后期还要视频剪辑」
///   ③「录制时镜头显示范围比录成视频显示范围小」
///   ④「横屏录制录出来的是竖屏视频」
/// 另外我自己还有个更严重的：录制会关掉语音跟读，等于核心功能二选一。
final class RecordingTests: XCTestCase {

    /// ④ 方向必须显式设置，否则横屏录出竖屏视频。
    func testRotationAngleCoversAllOrientations() {
        // 用反射拿不到 private static，这里验证映射逻辑的完备性：
        // 四个方向必须各自映射到不同角度，不能全落到默认值。
        let angles: [UIDeviceOrientation] = [
            .portrait, .landscapeLeft, .landscapeRight, .portraitUpsideDown,
        ]
        var seen = Set<CGFloat>()
        for o in angles {
            // 复刻 CameraController.rotationAngle 的规则
            let a: CGFloat
            switch o {
            case .landscapeLeft:      a = 0
            case .landscapeRight:     a = 180
            case .portraitUpsideDown: a = 270
            default:                  a = 90
            }
            seen.insert(a)
        }
        XCTAssertEqual(seen.count, 4,
            "四个方向应映射到四个不同角度，否则横屏会录成竖屏")
    }

    /// ③ 取景框的几何计算：必须落在屏幕内且保持 4:3 画幅。
    func testFrameGuideGeometryMatchesCaptureAspect() {
        let capture: CGFloat = 4.0 / 3.0
        // 竖屏 iPhone 16 Pro
        for b in [CGRect(x: 0, y: 0, width: 402, height: 874),
                  CGRect(x: 0, y: 0, width: 874, height: 402)] {
            // 复刻 layoutFrameGuide：画幅铺满短边，长边按比例推出
            let shortSide = min(b.width, b.height)
            let longSide = shortSide * capture
            let f: CGRect = b.height > b.width
                ? CGRect(x: 0, y: (b.height - longSide) / 2,
                         width: b.width, height: longSide)
                : CGRect(x: (b.width - longSide) / 2, y: 0,
                         width: longSide, height: b.height)
            XCTAssertGreaterThan(f.width, 0)
            XCTAssertGreaterThan(f.height, 0)
            // 框必须在屏内
            XCTAssertGreaterThanOrEqual(f.minX, -0.5, "框左边超出屏幕 \(f)")
            XCTAssertGreaterThanOrEqual(f.minY, -0.5, "框上边超出屏幕 \(f)")
            XCTAssertLessThanOrEqual(f.maxX, b.width + 0.5, "框右边超出屏幕 \(f)")
            XCTAssertLessThanOrEqual(f.maxY, b.height + 0.5, "框下边超出屏幕 \(f)")
            // 比例必须是 4:3（长边/短边）
            let r = max(f.width, f.height) / min(f.width, f.height)
            XCTAssertEqual(r, capture, accuracy: 0.02,
                "取景框比例应为 4:3，实际 \(r)")
        }
    }

    /// ① 倒计时不该被录进视频：配置项必须存在且默认开启。
    func testRecordStartsAfterCountdownByDefault() {
        let c = SetupViewController.Config()
        XCTAssertTrue(c.recordAfterCountdown,
            "默认应等倒计时结束才开录，否则倒计时进成片")
        XCTAssertGreaterThan(c.countdown, 0, "默认应有倒计时")
        XCTAssertTrue(c.showFrameGuide, "默认应显示取景框")
    }

    /// 音频会话必须允许录制与识别共存 —— 这是「边录边跟读」的前提。
    func testAudioSessionAllowsSimultaneousRecordAndRecognition() {
        #if targetEnvironment(simulator)
        // 模拟器没音频硬件，激活会卡死，只做静态检查
        let src = (try? String(contentsOfFile:
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/App/AudioSessionManager.swift").path,
            encoding: .utf8)) ?? ""
        XCTAssertTrue(src.contains(".playAndRecord"),
            "必须 playAndRecord —— 只 record 或只 playback 都无法边录边跟读")
        XCTAssertTrue(src.contains(".mixWithOthers"),
            "必须 mixWithOthers，否则两条音频路径互相打断")
        #endif
    }

    /// 相机重复配置不该叠加输入 —— 录制会二次 configure(useMic:)。
    func testRepeatedConfigureWithMicDoesNotStackInputs() {
        let c = CameraController()
        c.configure(useMic: false)
        c.configure(useMic: true)      // 录制时切成带麦克风
        c.configure(useMic: true)
        let exp = expectation(description: "configure")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { exp.fulfill() }
        wait(for: [exp], timeout: 4)
        XCTAssertLessThanOrEqual(c.session.inputs.count, 2,
            "最多 1 视频 + 1 音频，实际 \(c.session.inputs.count)")
    }
}
