import XCTest
@testable import PrompterCore

// 和 Web 版 test/prep.test.mjs 同一套用例。
final class PrepTests: XCTestCase {

    func testSegmentsBySentence() {
        let lines = segment("大家好，欢迎来到今天的直播。今天我们聊提词器。")
        XCTAssertEqual(lines.count, 2, "应按句断成 2 行, got \(lines.map(\.text))")
        for ln in lines { XCTAssertLessThanOrEqual(ln.text.count, 18) }
    }

    func testLongSentenceSplitsAtComma() {
        let lines = segment("今天我们要聊的话题是人工智能提词器，它的实现原理其实并不复杂。")
        XCTAssertGreaterThanOrEqual(lines.count, 2, "超长句应拆行, got \(lines.map(\.text))")
        for ln in lines { XCTAssertLessThanOrEqual(ln.text.count, 18) }
    }

    func testOffsetsMapBackToSource() {
        let src = "大家好，欢迎来到今天的直播。今天我们聊提词器的实现。"
        let chars = Array(src)
        for ln in segment(src) {
            let slice = String(chars[ln.start..<ln.end])
            XCTAssertTrue(slice.contains(ln.text.prefix(3)),
                          "区间错位: \(ln.text) vs \(slice)")
        }
    }

    func testBreathStrength() {
        let lines = segment("这是第一句话的内容，这是同一句的后半。这是第二句话。")
        XCTAssertGreaterThanOrEqual(lines.filter { $0.breath == .long }.count, 2, "句号应产生长气口")
    }

    func testNewlineIsLongBreath() {
        let lines = segment("第一段内容在这里。\n第二段内容在那里。")
        XCTAssertEqual(lines[0].breath, .long)
    }

    func testNoTinyFragments() {
        let lines = segment("好，行，对，是的，没问题，我们继续往下讲这个话题。")
        let tiny = lines.filter { $0.text.count <= 2 }
        XCTAssertLessThanOrEqual(tiny.count, 1, "碎片过多: \(lines.map(\.text))")
    }

    func testHardBreakWithoutPunctuation() {
        let lines = segment("这是一段完全没有任何标点符号的很长的话需要被强制断开否则一行会长到没法读")
        XCTAssertGreaterThanOrEqual(lines.count, 3, "应硬断成多行")
        for ln in lines { XCTAssertLessThanOrEqual(ln.text.count, 14, "硬断后仍过长: \(ln.text)") }
    }

    func testSlowMarks() {
        XCTAssertEqual(segment("注意这里是关键的部分。")[0].pace, .slow, "「关键」应标慢速")
        XCTAssertEqual(segment("增长了35%。")[0].pace, .slow, "数字应标慢速")
        XCTAssertEqual(segment("第一步是这样做的。")[0].pace, .slow, "序数应标慢速")
    }

    func testFastMarks() {
        XCTAssertEqual(segment("那么我们接着往下看。")[0].pace, .fast, "「那么」开头应标快速")
    }

    func testDurationEstimate() {
        let text = String(repeating: "大家好，欢迎来到今天的直播。", count: 7)
        let sec = estimateDuration(segment(text))
        XCTAssertTrue(sec > 15 && sec < 60, "预估 \(sec) 秒超出合理范围")
    }

    func testSlowIsLonger() {
        // 两句字数相同，只有语速标记不同，这样差异才只来自语速
        let plain = "我们今天来聊聊这个事情的来龙去脉啊。"
        let heavy = "注意这里是关键的重点内容部分记住。"
        let n = segment(plain), sl = segment(heavy)
        XCTAssertEqual(n[0].pace, .normal, "对照句不该被标慢速")
        XCTAssertEqual(sl[0].pace, .slow)
        XCTAssertGreaterThan(estimateDuration(sl), estimateDuration(n) - 1,
                             "慢速段落用时不应更短")
    }

    func testChineseNumeralsAreNotFalseSlow() {
        // Character.isNumber 对汉字数字也为 true，容易误判
        XCTAssertEqual(segment("我们来聊一聊这件事情吧。")[0].pace, .normal, "「一聊」不该判慢")
        XCTAssertEqual(segment("他说了一下就走开了。")[0].pace, .normal, "「一下」不该判慢")
        XCTAssertEqual(segment("第一步先这样做。")[0].pace, .slow, "「第一」应判慢")
    }

    func testFormatDuration() {
        XCTAssertEqual(formatDuration(45), "45秒")
        XCTAssertEqual(formatDuration(83), "1分23秒")
    }

    func testEmptyAndPunctOnly() {
        XCTAssertTrue(segment("").isEmpty)
        XCTAssertEqual(estimateDuration([]), 0)
        _ = segment("。。。，，，")
    }
}
