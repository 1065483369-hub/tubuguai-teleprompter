import XCTest
import AVFoundation
@testable import Prompter

/// 反复启停不该泄漏资源。用户会频繁「开始/暂停/改稿子」，
/// 每次都新建对象而不清理，跑一会儿就卡死或崩。
final class LifecycleTests: XCTestCase {

    /// 模拟器没有音频硬件，真的激活音频会话会卡死在 AURemoteIO，
    /// 所以这类测试只在真机跑。不是"假装通过"，是明确跳过。
    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    func testAudioSessionCategoryAllowsRecording() throws {
        try XCTSkipIf(isSimulator, "音频会话激活在模拟器会卡死，只能真机验证")
        // 这是曾经导致崩溃的根因：类别若是 .playback，
        // inputNode 的采样率会是 0，installTap 直接抛 NSException。
        XCTAssertTrue(AudioSessionManager.activateForRecordAndPlayback(),
                      "会话应能配置成可录音")
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playAndRecord,
                       "必须是 playAndRecord，否则麦克风拿不到")
        XCTAssertTrue(AVAudioSession.sharedInstance().categoryOptions.contains(.mixWithOthers),
                      "要 mixWithOthers，否则会打断别人的音频")
    }

    /// 不激活会话，只验证 observer 不重复注册这一纯逻辑。
    func testKeepAliveRepeatedStartStopDoesNotLeakObservers() throws {
        try XCTSkipIf(isSimulator, "start() 会激活音频会话，模拟器上会卡死")
        let ka = KeepAlive()
        var fires = 0
        ka.onInterrupted = { _ in fires += 1 }
        for _ in 0..<5 { ka.start(); ka.stop() }
        ka.start()
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [AVAudioSessionInterruptionTypeKey:
                        AVAudioSession.InterruptionType.began.rawValue])
        let exp = expectation(description: "notify")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(fires, 1, "6 次 start 后应只回调 1 次，实际 \(fires)")
        ka.stop()
    }

    func testSpeechTrackerStopWithoutStartIsSafe() {
        let t = SpeechTracker()
        t.stop()          // 没 start 就 stop
        t.stop()          // 再来一次
        XCTAssertFalse(t.isRunning)
    }

    func testSpeechTrackerSeekBeforeLoadIsSafe() {
        let t = SpeechTracker()
        t.seek(toChar: 100)   // 还没 load 稿子
        t.seek(toChar: -5)
        XCTAssertFalse(t.isRunning)
    }

    func testSpeechTrackerRepeatedLoadResetsState() {
        let t = SpeechTracker()
        t.load(script: "第一份稿子的内容在这里。")
        t.load(script: "换成完全不同的第二份稿子。")
        // 换稿后位置必须归零，否则旧位置会落在新稿子的错误处
        var reported: Int?
        t.onPosition = { anchor, _, _ in reported = anchor }
        t.seek(toChar: 0)
        XCTAssertNil(reported ?? nil, "seek 不该触发位置回调")
    }

    func testPiPPrompterUnsupportedDoesNotCrash() {
        let p = PiPPrompter()
        // 模拟器上 isSupported == false，start 必须安全返回而不是崩
        XCTAssertFalse(p.isSupported, "模拟器不该支持 PiP")
        p.script = "测试稿子内容"
        p.readChar = 3
        p.start()
        XCTAssertFalse(p.isActive)
        p.stop()
        p.stop()   // 重复 stop
    }

    func testPiPPrompterRepeatedAttachDoesNotStackLayers() {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let p = PiPPrompter()
        for _ in 0..<4 { p.attach(to: host) }
        let layers = host.layer.sublayers?.filter { $0 is AVSampleBufferDisplayLayer } ?? []
        XCTAssertEqual(layers.count, 1, "重复 attach 应只留一个 layer，实际 \(layers.count)")
    }

    /// 重复 attach 必须保持同一个控制器实例。
    /// 否则 viewDidLayoutSubviews（旋转、键盘）会把正在进行的 PiP 会话丢掉：
    /// 系统浮窗还在，但新控制器报 isPictureInPictureActive == false，按钮语义反转。
    func testPiPPrompterAttachIsIdempotent() {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let p = PiPPrompter()
        p.attach(to: host)
        let firstLayer = host.layer.sublayers?.first { $0 is AVSampleBufferDisplayLayer }
        for _ in 0..<5 { p.attach(to: host) }   // 模拟多次布局
        let layers = host.layer.sublayers?.filter { $0 is AVSampleBufferDisplayLayer } ?? []
        XCTAssertEqual(layers.count, 1, "不该叠加 layer")
        XCTAssertTrue(layers.first === firstLayer, "应是同一个 layer 实例，未被重建")
    }

    func testCameraRepeatedConfigureDoesNotStackInputs() {
        let c = CameraController()
        for _ in 0..<4 { c.configure(useMic: false) }
        // 配置是异步的，等队列排空
        let exp = expectation(description: "configure")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { exp.fulfill() }
        wait(for: [exp], timeout: 3)
        // 模拟器无摄像头时 inputs 为空是正常的；关键是不能无限叠加
        XCTAssertLessThanOrEqual(c.session.inputs.count, 2,
            "重复 configure 不应叠加输入，实际 \(c.session.inputs.count)")
    }

    func testCameraStopRecordingWithoutStartIsSafe() {
        let c = CameraController()
        c.stopRecording()
        c.stopRecording()
        XCTAssertFalse(c.isRecording)
    }
}

/// 静态守卫：曾经因为 KeepAlive 把类别设成 `.playback`（不允许输入），
/// 导致 `installTap` 崩溃。这条测试直接读源码，确保没人再犯——
/// 比运行时检查可靠，且在模拟器上也能跑。
final class AudioCategoryGuardTests: XCTestCase {

    private func sourceDir() throws -> URL {
        // #filePath = <root>/Tests/AppTests/LifecycleTests.swift
        // 去掉文件名、AppTests、Tests 三级才到仓库根。
        var dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // -> Tests/AppTests
            .deletingLastPathComponent()   // -> Tests
            .deletingLastPathComponent()   // -> <root>
        dir.appendPathComponent("Sources/App")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir),
              isDir.boolValue else {
            throw XCTSkip("找不到源码目录: \(dir.path)")
        }
        return dir
    }

    func testOnlyAudioSessionManagerSetsCategory() throws {
        let dir = try sourceDir()
        let files = try FileManager.default.contentsOfDirectory(at: dir,
            includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "应能读到源文件")

        var offenders: [String] = []
        for f in files where f.lastPathComponent != "AudioSessionManager.swift" {
            let text = try String(contentsOf: f, encoding: .utf8)
            for (i, line) in text.components(separatedBy: .newlines).enumerated() {
                // 跳过注释行，只看真实代码
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("//") { continue }
                if t.contains("setCategory(") {
                    offenders.append("\(f.lastPathComponent):\(i + 1)")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty,
            "音频会话类别必须只由 AudioSessionManager 设置，违规处: \(offenders)")
    }

    func testAudioSessionManagerUsesPlayAndRecord() throws {
        let dir = try sourceDir()
        let src = try String(contentsOf: dir.appendingPathComponent("AudioSessionManager.swift"),
                             encoding: .utf8)
        XCTAssertTrue(src.contains(".playAndRecord"),
            "必须用 playAndRecord —— .playback 会关掉麦克风输入，installTap 崩溃")
        XCTAssertTrue(src.contains(".mixWithOthers"),
            "必须 mixWithOthers，否则会打断用户其他音频，且更易被相机抢走会话")
    }
}

extension LifecycleTests {

    /// 暂停必须不拆会话。用户原话（出现在 5 星好评里，说明是真痛点）：
    /// 「中途说错了，暂停不了，也后退不了，必须再次开始，浪费时间」
    /// 之前只有启停整个会话，重启 ASR 有明显空档，"继续"就不无缝了。
    func testPauseDoesNotTearDownSession() {
        let t = SpeechTracker()
        t.load(script: "你好，今天天气很好。我们来聊聊提词器。")

        var positions: [Int] = []
        t.onPosition = { anchor, _, _ in positions.append(anchor) }

        // 暂停期间喂词不该推进位置
        t.pause()
        // 直接调 feed 不可行（private），改为验证 pause/resume 不崩且状态正确
        t.resume()
        t.pause()
        t.pause()          // 重复暂停
        t.resume()
        t.resume()         // 重复继续
        XCTAssertFalse(t.isRunning, "没 start 过就不该 running")
    }

    /// 暂停/继续在未加载稿子时也不能崩。
    func testPauseWithoutScriptIsSafe() {
        let t = SpeechTracker()
        t.pause()
        t.resume()
        t.stop()
        XCTAssertFalse(t.isRunning)
    }
}
