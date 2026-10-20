import XCTest
import AVFoundation
import CoreVideo
@testable import Prompter

/// PiP 能不能成立，全看 PromptRenderer 是否真的产出可用的视频帧。
/// 这些测试不需要真机——渲染是纯 CoreGraphics/CoreVideo，模拟器上跑得通。
final class RendererTests: XCTestCase {

    let size = CGSize(width: 480, height: 270)
    let script = "大家好，欢迎来到今天的直播。今天我们聊提词器的实现原理。第一步是流式语音识别。"

    func testProducesValidSampleBuffer() throws {
        let sb = PromptRenderer.makeSampleBuffer(
            script: script, readChar: 0, pace: nil, size: size)
        let buf = try XCTUnwrap(sb, "应产出 CMSampleBuffer")
        XCTAssertTrue(CMSampleBufferIsValid(buf))
        XCTAssertTrue(CMSampleBufferDataIsReady(buf), "PiP 只接受 ready 的 buffer")

        let img = try XCTUnwrap(CMSampleBufferGetImageBuffer(buf))
        XCTAssertEqual(CVPixelBufferGetWidth(img), Int(size.width))
        XCTAssertEqual(CVPixelBufferGetHeight(img), Int(size.height))
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(img), kCVPixelFormatType_32BGRA)
    }

    func testTimestampIsValidAndMonotonic() throws {
        // PiP 认的是"活流"。时间戳无效会被判成静止画面，窗口可能直接关掉。
        let a = try XCTUnwrap(PromptRenderer.makeSampleBuffer(
            script: script, readChar: 0, pace: nil, size: size))
        Thread.sleep(forTimeInterval: 0.05)
        let b = try XCTUnwrap(PromptRenderer.makeSampleBuffer(
            script: script, readChar: 6, pace: nil, size: size))

        let ta = CMSampleBufferGetPresentationTimeStamp(a)
        let tb = CMSampleBufferGetPresentationTimeStamp(b)
        XCTAssertTrue(ta.isValid, "时间戳必须有效")
        XCTAssertTrue(tb.isValid)
        XCTAssertGreaterThan(CMTimeGetSeconds(tb), CMTimeGetSeconds(ta), "时间戳应递增")
    }

    /// 画面真的画了东西——不能是纯黑帧。
    fileprivate func nonBlackRatio(_ buf: CMSampleBuffer) -> Double {
        guard let img = CMSampleBufferGetImageBuffer(buf) else { return 0 }
        CVPixelBufferLockBaseAddress(img, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(img, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(img) else { return 0 }
        let bpr = CVPixelBufferGetBytesPerRow(img)
        let h = CVPixelBufferGetHeight(img), w = CVPixelBufferGetWidth(img)
        let p = base.assumingMemoryBound(to: UInt8.self)
        var lit = 0, total = 0
        for y in stride(from: 0, to: h, by: 2) {
            for x in stride(from: 0, to: w, by: 2) {
                let o = y * bpr + x * 4
                let lum = Int(p[o]) + Int(p[o + 1]) + Int(p[o + 2])
                if lum > 90 { lit += 1 }
                total += 1
            }
        }
        return total > 0 ? Double(lit) / Double(total) : 0
    }

    func testFrameActuallyContainsText() throws {
        let buf = try XCTUnwrap(PromptRenderer.makeSampleBuffer(
            script: script, readChar: 4, pace: nil, size: size))
        let ratio = nonBlackRatio(buf)
        XCTAssertGreaterThan(ratio, 0.01, "画面应有文字像素，不能是纯黑帧 (ratio=\(ratio))")
        XCTAssertLessThan(ratio, 0.85, "不该整屏糊白 (ratio=\(ratio))")
    }

    func testEmptyScriptDoesNotCrash() throws {
        let buf = PromptRenderer.makeSampleBuffer(script: "", readChar: 0, pace: nil, size: size)
        XCTAssertNotNil(buf, "空稿也该产出帧（黑底），不能返回 nil 让 PiP 空转")
    }

    func testOutOfRangeReadCharClamped() {
        for rc in [-50, 0, 5, 9_999_999] {
            XCTAssertNotNil(PromptRenderer.makeSampleBuffer(
                script: script, readChar: rc, pace: nil, size: size),
                "readChar=\(rc) 不应崩溃或返回 nil")
        }
    }

    func testPaceBadgeChangesPixels() throws {
        let plain = try XCTUnwrap(PromptRenderer.makeSampleBuffer(
            script: script, readChar: 4, pace: nil, size: size))
        let slow = try XCTUnwrap(PromptRenderer.makeSampleBuffer(
            script: script, readChar: 4, pace: .slow, size: size))
        // 慢速标记是橙色块，应该让亮像素变多
        XCTAssertGreaterThan(nonBlackRatio(slow), nonBlackRatio(plain),
                             "语速标记应在画面上可见")
    }

    func testPixelBufferPoolIsReused() throws {
        // 10fps 持续渲染，若每帧新建 buffer 会飙内存。池化必须生效。
        var addrs = Set<UInt>()
        for i in 0..<30 {
            let buf = try XCTUnwrap(PromptRenderer.makeSampleBuffer(
                script: script, readChar: i, pace: nil, size: size))
            if let img = CMSampleBufferGetImageBuffer(buf) {
                CVPixelBufferLockBaseAddress(img, .readOnly)
                if let a = CVPixelBufferGetBaseAddress(img) {
                    addrs.insert(UInt(bitPattern: a))
                }
                CVPixelBufferUnlockBaseAddress(img, .readOnly)
            }
        }
        // 池会复用少量 buffer，不该是 30 个各不相同的地址
        XCTAssertLessThan(addrs.count, 30, "PixelBuffer 应被池复用，实际 \(addrs.count) 个不同地址")
    }

    func testRenderPerformanceFitsTenFps() {
        // 10fps 意味着每帧预算 100ms。远超就说明这条路走不通。
        let start = Date()
        let n = 40
        for i in 0..<n {
            _ = PromptRenderer.makeSampleBuffer(
                script: script, readChar: i * 2, pace: i % 3 == 0 ? .slow : nil, size: size)
        }
        let perFrame = Date().timeIntervalSince(start) / Double(n) * 1000
        NSLog("[perf] 每帧 \(String(format: "%.2f", perFrame)) ms")
        XCTAssertLessThan(perFrame, 40, "每帧 \(perFrame)ms，10fps 下开销过大")
    }
}

/// PiP 帧渲染里的 emoji 处理。
///
/// 曾经的 bug：`readIdx` 是 Character 下标，却直接当 NSRange 的 UTF-16 位置用。
/// 中文下两者相等所以看不出来，但 emoji 是代理对（1 Character = 2 UTF-16），
/// 灰白分界会落进 emoji 中间切出半个代理项（渲染成方块），
/// 且每遇一个 emoji 就多偏 1 位。
extension RendererTests {

    /// 复刻渲染器的换算逻辑，验证 Character 下标 -> UTF-16 偏移是对的。
    fileprivate func utf16Offset(in s: String, characterIndex i: Int) -> Int {
        guard i > 0 else { return 0 }
        guard i < s.count else { return s.utf16.count }
        let ci = s.index(s.startIndex, offsetBy: i)
        guard let u = ci.samePosition(in: s.utf16) else { return s.utf16.count }
        return s.utf16.distance(from: s.utf16.startIndex, to: u)
    }

    func testEmojiHighlightBoundaryDoesNotSplitSurrogate() {
        let visible = "开场很棒👍效果不错🎉我们继续讲。"
        let units = Array(visible.utf16)

        for charIdx in 0...visible.count {
            let off = utf16Offset(in: visible, characterIndex: charIdx)
            XCTAssertTrue(off >= 0 && off <= units.count, "偏移 \(off) 越界")
            // 切出"已读"部分，必须是合法字符串（不含孤立代理项）
            let read = String(decoding: units[0..<off], as: UTF16.self)
            XCTAssertFalse(read.unicodeScalars.contains { ($0.value >= 0xD800 && $0.value <= 0xDFFF) },
                           "charIdx=\(charIdx) 切出了孤立代理项: \(read.debugDescription)")
            // 已读部分的字符数必须正好等于 charIdx
            XCTAssertEqual(read.count, charIdx,
                           "charIdx=\(charIdx) 但已读了 \(read.count) 个字符")
        }
    }

    func testEmojiOffsetDiffersFromCharacterIndex() {
        // 证明这个换算是必要的：emoji 之后两个坐标系确实分叉
        let visible = "开场很棒👍效果不错🎉我们"
        XCTAssertNotEqual(utf16Offset(in: visible, characterIndex: 6), 6,
                          "emoji 之后 UTF-16 偏移必须大于 Character 下标")
        XCTAssertEqual(utf16Offset(in: visible, characterIndex: 4), 4, "emoji 之前应相等")
        XCTAssertEqual(utf16Offset(in: visible, characterIndex: 5), 6, "跨过 👍 应 +2")
        XCTAssertEqual(utf16Offset(in: visible, characterIndex: 10), 12, "跨过两个 emoji 应 +4")
    }

    /// 端到端：含 emoji 的稿子渲染出的帧必须有效且画了东西。
    func testEmojiScriptRendersValidFrame() throws {
        let emojiScript = "开场很棒👍效果不错🎉我们继续往下讲这个话题。"
        for rc in [0, 4, 5, 6, 10, 11, emojiScript.count] {
            let buf = PromptRenderer.makeSampleBuffer(
                script: emojiScript, readChar: rc, pace: nil, size: size)
            let sb = try XCTUnwrap(buf, "readChar=\(rc) 应产出帧")
            XCTAssertTrue(CMSampleBufferIsValid(sb))
            XCTAssertGreaterThan(nonBlackRatio(sb), 0.005,
                                 "readChar=\(rc) 画面应有文字")
        }
    }
}
