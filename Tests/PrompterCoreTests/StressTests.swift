import XCTest
@testable import PrompterCore

/// 压测：一条真实口播时间线，混入 partial 累积、同音错字、插话、口误、重念。
/// 和 Web 端同一条序列，确保两端行为一致。
final class StressTests: XCTestCase {

    let script = [
        "大家好，欢迎来到今天的直播。",
        "今天我们要聊的话题是人工智能提词器的实现原理。",
        "第一步是流式语音识别，把麦克风的音频送进识别引擎。",
        "第二步是文本对齐，这一步决定了整个系统好不好用。",
        "第三步是平滑滚动，让文字跟着视线走而不是一跳一跳。",
        "最后我们会讲讲隐私和部署上需要注意的地方。",
    ].joined(separator: "\n")

    func testRealisticMessyTimelineDoesNotDerail() {
        let tokens = tokenize(script)
        let idx = buildScriptIndex(tokens)
        let tr = Tracker(syllables: idx.syllables)
        let chars = Array(script)

        func toChar(_ p: Int) -> Int {
            if p <= 0 { return 0 }
            if p >= idx.sylToToken.count { return tokens.last?.end ?? 0 }
            return tokens[idx.sylToToken[p]].start
        }

        let timeline: [(String, Bool)] = [
            ("大家", false), ("大家好", false), ("大家好欢迎", false),
            ("大家好欢迎来到今天的直播", false),
            ("大家好欢迎来到今天的直播", true),
            ("哎等一下我喝口水", true),                                    // 插话
            ("今天我们要聊的话题", false),
            ("今天我们要聊的话题是人工智能提词器", false),
            ("今天我们要聊的话题是人工智能提词器的实现原理", true),
            ("第一步是留式语音识别把麦刻风的音频送进识别引情", true),        // 全同音错字
            ("第二步是文本对齐", false),
            ("第二不是文本对齐这一步决定了整个系统好不好用", true),          // 口误
            ("第二步是文本对齐这一步决定了整个系统好不好用", true),          // 重念纠正
            ("第三步是平滑滚动让文字跟着视线走", true),
            ("最后我们会讲讲隐私和部署上需要注意的地方", true),
        ]

        var prevChar = 0, backSteps = 0, maxJump = 0
        for (text, isFinal) in timeline {
            let r = tr.update(syllables: textToSyllables(text), isFinal: isFinal)
            let c = toChar(r.anchor)
            let delta = c - prevChar
            if delta < -8 { backSteps += 1 }
            maxJump = max(maxJump, abs(delta))
            prevChar = c
        }

        let finalChar = toChar(tr.anchor)
        XCTAssertGreaterThan(finalChar, Int(Double(chars.count) * 0.85),
            "终点应接近稿尾 (\(finalChar)/\(chars.count))")
        XCTAssertLessThanOrEqual(backSteps, 2, "异常回退过多: \(backSteps)")
        XCTAssertLessThan(maxJump, 90, "单步跳幅过大: \(maxJump)")
    }

    /// 插话不该移动位置——这是最影响体感的一条。
    func testAdLibInMiddleDoesNotMoveCursor() {
        let idx = buildScriptIndex(tokenize(script))
        let tr = Tracker(syllables: idx.syllables)
        tr.update(syllables: textToSyllables("大家好欢迎来到今天的直播"), isFinal: true)
        let before = tr.anchor
        for chat in ["哎等一下我喝口水", "这个天气真的太热了", "嗯那个怎么说呢"] {
            let r = tr.update(syllables: textToSyllables(chat), isFinal: true)
            XCTAssertFalse(r.moved, "插话「\(chat)」不该移动位置 (reason=\(r.reason))")
        }
        XCTAssertEqual(tr.anchor, before, "连续插话后位置应不变")
    }
}

extension StressTests {

    /// 跳读必须一次跟上。用户原话：「能识别我跳了一两句再找到我跟读的地方才对」。
    /// 之前跳 2~3 句要把那句念两遍（jump-pending → jump），光标永远落后一句。
    func testSkipAheadCatchesUpImmediately() {
        let lines = script.components(separatedBy: "\n")
        let tokens = tokenize(script)
        let idx = buildScriptIndex(tokens)
        let chars = Array(script)

        func toChar(_ p: Int) -> Int {
            if p <= 0 { return 0 }
            if p >= idx.sylToToken.count { return tokens.last?.end ?? 0 }
            return tokens[idx.sylToToken[p]].start
        }
        func clean(_ s: String) -> String {
            s.filter { !"，。、；：！？".contains($0) }
        }

        for skip in 1...3 {
            let targetIdx = 1 + skip
            guard targetIdx < lines.count else { continue }
            let tr = Tracker(syllables: idx.syllables)
            tr.update(syllables: textToSyllables(clean(lines[0])), isFinal: true)

            // 只念一次跳到的那句
            let r = tr.update(syllables: textToSyllables(clean(lines[targetIdx])), isFinal: true)
            XCTAssertTrue(r.moved, "跳过 \(skip) 句应一次跟上，reason=\(r.reason)")
            XCTAssertTrue(r.reason == "jump" || r.reason == "advance",
                          "跳过 \(skip) 句 reason 应是 jump/advance，实际 \(r.reason)")

            // 落点要在目标句附近
            let landed = toChar(r.anchor)
            let wantRange = script.range(of: lines[targetIdx])!
            let wantEnd = script.distance(from: script.startIndex, to: wantRange.upperBound)
            XCTAssertLessThan(abs(landed - wantEnd), 24,
                "跳过 \(skip) 句落点偏差过大：\(landed) vs 期望 ≈\(wantEnd)")
            XCTAssertLessThanOrEqual(landed, chars.count)
        }
    }

    /// 免确认不能削弱防噪音：稿外内容再怎么念也不该跳。
    func testInstantJumpDoesNotWeakenNoiseRejection() {
        let idx = buildScriptIndex(tokenize(script))
        let tr = Tracker(syllables: idx.syllables)
        tr.update(syllables: textToSyllables("大家好欢迎来到今天的直播"), isFinal: true)
        let before = tr.anchor
        for noise in ["完全不相干的胡言乱语在这里瞎说一通",
                      "今天天气不错适合出门散步买菜",
                      "随便说点什么东西都可以的啦"] {
            let r = tr.update(syllables: textToSyllables(noise), isFinal: true)
            XCTAssertFalse(r.moved, "稿外内容「\(noise)」不该移动 (reason=\(r.reason))")
        }
        XCTAssertEqual(tr.anchor, before, "连续噪音后位置应不变")
    }
}

extension StressTests {

    /// 长时间不停顿时光标不能卡死。
    ///
    /// 用户反馈「语音识别跟不上」。真因不是延迟，而是 partial 的远跳被
    /// 一律丢弃：SFSpeech 连续说话时可能长时间不出 final，anchor 就不推进，
    /// 搜索窗锚在旧位置，念到远处全被判成跳读扔掉。
    /// 实测相似度 1.000 也被丢，光标停在字符 39，落后 76 字。
    func testContinuousSpeechWithoutFinalKeepsUp() {
        let lines = script.components(separatedBy: "\n")
        let tokens = tokenize(script)
        let idx = buildScriptIndex(tokens)
        let tr = Tracker(syllables: idx.syllables)

        func toChar(_ p: Int) -> Int {
            if p <= 0 { return 0 }
            if p >= idx.sylToToken.count { return tokens.last?.end ?? 0 }
            return tokens[idx.sylToToken[p]].start
        }
        func clean(_ s: String) -> String { s.filter { !"，。、；：！？".contains($0) } }

        var acc = ""
        var worstLag = 0
        // 全程只有 partial，模拟一口气念完不停顿
        for line in lines {
            acc += clean(line)
            let tail = acc.count > 20 ? String(Array(acc).suffix(20)) : acc
            let r = tr.update(syllables: textToSyllables(tail), isFinal: false)
            let got = toChar(r.soft)
            guard let range = script.range(of: line) else { continue }
            let want = script.distance(from: script.startIndex, to: range.upperBound)
            worstLag = max(worstLag, want - got)
        }
        XCTAssertLessThanOrEqual(worstLag, 15,
            "连续说话（无 final）时光标落后 \(worstLag) 字，应保持跟随")
    }

    /// 放行 partial 远跳不能让噪音把光标甩飞。
    func testPartialJumpStillRejectsNoise() {
        let idx = buildScriptIndex(tokenize(script))
        let tr = Tracker(syllables: idx.syllables)
        tr.update(syllables: textToSyllables("大家好欢迎来到今天的直播"), isFinal: true)
        let before = tr.anchor
        for noise in ["完全不相干的胡言乱语在这里瞎说一通",
                      "今天天气不错适合出门散步"] {
            let r = tr.update(syllables: textToSyllables(noise), isFinal: false)
            XCTAssertFalse(r.moved, "partial 噪音不该移动位置 (reason=\(r.reason))")
        }
        XCTAssertEqual(tr.anchor, before)
    }
}
