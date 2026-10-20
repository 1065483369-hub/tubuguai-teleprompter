import XCTest
@testable import PrompterCore

/// 三个偏移空间必须互相一致：原文字符偏移 <-> 音节下标 <-> 显示偏移。
/// 这里穷举验证，不靠肉眼读代码。和 Web 端同一套断言。
final class OffsetTests: XCTestCase {

    let cases = [
        "大家好，欢迎来到今天的直播。",
        "那么我们接下来聊聊提词器的实现原理。注意这里是关键，提升了35%。",
        "第一步是流式语音识别。\n第二步是文本对齐。\n第三步是平滑滚动。",
        "Hello world 2024 混排中文 test。",
        "。。。，，，",
        "",
        "一二三四五六七八九十",
        "a",
        "中",
        "很长的一段没有任何标点符号的话用来测试硬断行是否会破坏偏移映射关系",
    ]

    func testTokenRangesReconstructSource() {
        for src in cases {
            let chars = Array(src)
            for t in tokenize(src) {
                XCTAssertTrue(t.start >= 0 && t.end <= chars.count,
                              "区间越界 [\(t.start),\(t.end)] len=\(chars.count)")
                XCTAssertEqual(String(chars[t.start..<t.end]), t.text,
                               "token 区间错位: \(t.text)")
            }
        }
    }

    func testIndexMapsAreMonotonicAndComplete() {
        for src in cases {
            let tokens = tokenize(src)
            let idx = buildScriptIndex(tokens)

            // tokenToSyl 单调不减
            for i in 1..<max(1, idx.tokenToSyl.count) where idx.tokenToSyl.count > 1 {
                XCTAssertGreaterThanOrEqual(idx.tokenToSyl[i], idx.tokenToSyl[i - 1],
                                            "tokenToSyl 非单调 @\(i)")
            }
            // 末位必须等于音节总数
            XCTAssertEqual(idx.tokenToSyl.last, idx.syllables.count,
                           "tokenToSyl 末位应等于音节数")
            // sylToToken 每项都是合法 token 下标
            for ti in idx.sylToToken {
                XCTAssertTrue(ti >= 0 && ti < tokens.count, "sylToToken 越界: \(ti)")
            }
        }
    }

    func testBidirectionalMappingIsSelfConsistent() {
        for src in cases {
            let tokens = tokenize(src)
            let idx = buildScriptIndex(tokens)
            // token -> syl -> token 应回到原 token
            for ti in tokens.indices {
                let s = idx.tokenToSyl[ti]
                if s < idx.sylToToken.count {
                    XCTAssertEqual(idx.sylToToken[s], ti,
                        "双向映射不自洽: token \(ti) -> syl \(s) -> token \(idx.sylToToken[s])")
                }
            }
        }
    }

    func testSegmentLinesTileTheSource() {
        for src in cases {
            let chars = Array(src)
            var prevEnd = 0
            for ln in segment(src) {
                XCTAssertTrue(ln.start >= 0 && ln.end <= chars.count,
                              "行区间越界 [\(ln.start),\(ln.end)] len=\(chars.count)")
                XCTAssertGreaterThanOrEqual(ln.end, ln.start, "行 end < start")
                XCTAssertGreaterThanOrEqual(ln.start, prevEnd - 1,
                    "行区间倒序: 上行结束 \(prevEnd), 本行起始 \(ln.start)")
                prevEnd = ln.end
            }
        }
    }

    /// 音节位置换算成字符偏移，任何输入都不能越界。
    /// 这正是 SpeechTracker.charOffset 的逻辑，之前 PromptRenderer 就因为
    /// 类似的没钳制导致 "Range requires lowerBound <= upperBound" 崩溃。
    func testSyllableToCharOffsetNeverOutOfRange() {
        let src = "大家好，欢迎来到今天的直播。今天聊提词器。"
        let chars = Array(src)
        let tokens = tokenize(src)
        let idx = buildScriptIndex(tokens)

        func toChar(_ p: Int) -> Int {
            if p <= 0 { return 0 }
            if p >= idx.sylToToken.count { return tokens.last?.end ?? 0 }
            return tokens[idx.sylToToken[p]].start
        }

        for p in [-100, -1, 0, 1, idx.syllables.count - 1,
                  idx.syllables.count, idx.syllables.count + 50, 99_999] {
            let c = toChar(p)
            XCTAssertTrue(c >= 0 && c <= chars.count,
                          "toChar(\(p)) = \(c) 越界 (len=\(chars.count))")
        }
    }

    /// Tracker 的 anchor/soft 永远落在 [0, 音节数] 内，
    /// 否则下游换算和渲染都会越界。
    func testTrackerPositionsStayInBounds() {
        let src = cases[1]
        let idx = buildScriptIndex(tokenize(src))
        guard !idx.syllables.isEmpty else { return }
        let tr = Tracker(syllables: idx.syllables)

        let inputs = ["那么我们接下来聊聊提词器", "完全不相干的胡言乱语在这里",
                      "注意这里是关键提升了35%", "", "提升了"]
        for text in inputs {
            for final in [true, false] {
                let r = tr.update(syllables: textToSyllables(text), isFinal: final)
                XCTAssertTrue(r.anchor >= 0 && r.anchor <= idx.syllables.count,
                              "anchor \(r.anchor) 越界 (n=\(idx.syllables.count))")
                XCTAssertTrue(r.soft >= 0 && r.soft <= idx.syllables.count,
                              "soft \(r.soft) 越界")
            }
        }
    }
}
