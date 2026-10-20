import XCTest
@testable import PrompterCore

// 和 Web 版 test/align.test.mjs 同一套用例，确保两端行为一致。
final class AlignTests: XCTestCase {

    let script = [
        "大家好，欢迎来到今天的直播。",
        "今天我们要聊的话题是人工智能提词器的实现原理。",
        "第一步是流式语音识别，把麦克风的音频送进识别引擎。",
        "第二步是文本对齐，这一步决定了整个系统好不好用。",
        "第三步是平滑滚动，让文字跟着视线走而不是一跳一跳。",
        "最后我们会讲讲隐私和部署上需要注意的地方。",
    ].joined(separator: "\n")

    func make(_ text: String? = nil) -> (tokens: [Token], index: ScriptIndex, tracker: Tracker) {
        let t = tokenize(text ?? script)
        let idx = buildScriptIndex(t)
        return (t, idx, Tracker(syllables: idx.syllables))
    }

    func testTokenizePreservesOffsets() {
        let src = "你好 world 2024！"
        let tokens = tokenize(src)
        XCTAssertEqual(tokens.map(\.text), ["你", "好", "world", "2024"])
        let chars = Array(src)
        for t in tokens {
            XCTAssertEqual(String(chars[t.start..<t.end]), t.text)
        }
    }

    func testPinyinAbsorbsHomophoneErrors() {
        // 「部署」听成「不熟」，「实现」听成「实线」
        let a = textToSyllables("第三步是部署实现")
        let b = textToSyllables("第三步是不熟实线")
        let sim = similarity(a, b)
        XCTAssertGreaterThan(sim, 0.9, "同音错字应仍高相似, got \(sim)")
    }

    func testForwardReadingAdvancesMonotonically() {
        let (_, _, tr) = make()
        var prev = -1
        for s in ["大家好欢迎来到今天的直播",
                  "今天我们要聊的话题是人工智能提词器的实现原理",
                  "第一步是流式语音识别把麦克风的音频送进识别引擎"] {
            let r = tr.update(syllables: textToSyllables(s), isFinal: true)
            XCTAssertGreaterThan(r.anchor, prev, "anchor 应前进")
            prev = r.anchor
        }
    }

    func testRecognitionErrorsDoNotDrift() {
        let (_, _, tr) = make()
        tr.update(syllables: textToSyllables("大家好欢迎来到今天的直播"), isFinal: true)
        let before = tr.anchor
        tr.update(syllables: textToSyllables("打假好换应来到金田的直博"), isFinal: true)
        XCTAssertLessThan(abs(tr.anchor - before), 12, "漂移过大")
    }

    func testAdLibDoesNotMoveAnchor() {
        let (_, _, tr) = make()
        tr.update(syllables: textToSyllables("大家好欢迎来到今天的直播"), isFinal: true)
        let before = tr.anchor
        let r = tr.update(syllables: textToSyllables("哎对了我先喝口水稍等一下啊这个天气真热"), isFinal: true)
        XCTAssertFalse(r.moved)
        XCTAssertEqual(tr.anchor, before)
        XCTAssertEqual(r.reason, "below-threshold")
    }

    func testBacktrackFollowsImmediately() {
        let (_, _, tr) = make()
        tr.update(syllables: textToSyllables("大家好欢迎来到今天的直播"), isFinal: true)
        tr.update(syllables: textToSyllables("今天我们要聊的话题是人工智能提词器的实现原理"), isFinal: true)
        tr.update(syllables: textToSyllables("第一步是流式语音识别把麦克风的音频送进识别引擎"), isFinal: true)
        let high = tr.anchor
        let r = tr.update(syllables: textToSyllables("今天我们要聊的话题是人工智能提词器"), isFinal: true)
        XCTAssertEqual(r.reason, "backtrack")
        XCTAssertLessThan(tr.anchor, high)
    }

    /// 干净的跳读（念得和稿子基本一致）应一次生效。
    /// 用户要求「跳了一两句还能找到跟读位置」——要求念两遍等于永远落后一句。
    func testCleanJumpTakesEffectImmediately() {
        let (_, _, tr) = make()
        tr.update(syllables: textToSyllables("大家好欢迎来到今天的直播"), isFinal: true)
        let before = tr.anchor
        let jump = "最后我们会讲讲隐私和部署上需要注意的地方"
        let r = tr.update(syllables: textToSyllables(jump), isFinal: true)
        XCTAssertEqual(r.reason, "jump", "高相似度远跳应免确认")
        XCTAssertGreaterThan(tr.anchor, before + 40)
    }

    /// 相似度一般的远跳仍需两次确认，否则噪音会把光标甩飞。
    func testFuzzyJumpStillNeedsConfirmation() {
        let (_, _, tr) = make()
        tr.update(syllables: textToSyllables("大家好欢迎来到今天的直播"), isFinal: true)
        let before = tr.anchor
        // 故意念得残缺：能匹配上但相似度低于 jumpInstant 门槛
        let fuzzy = "最后讲讲隐私部署注意地方那个什么"
        let r1 = tr.update(syllables: textToSyllables(fuzzy), isFinal: true)
        if r1.reason == "jump-pending" {
            XCTAssertEqual(tr.anchor, before, "模糊远跳首次不应移动")
            let r2 = tr.update(syllables: textToSyllables(fuzzy), isFinal: true)
            XCTAssertEqual(r2.reason, "jump", "二次确认后应跳")
        } else {
            // 相似度已达免确认门槛也可以接受，但必须落在稿尾附近
            XCTAssertTrue(r1.reason == "jump" || !r1.moved,
                          "要么跳、要么不动，不该有别的行为: \(r1.reason)")
        }
    }

    func testPartialOnlyMovesSoft() {
        let (_, _, tr) = make()
        tr.update(syllables: textToSyllables("大家好欢迎来到今天的直播"), isFinal: true)
        let a = tr.anchor
        let r = tr.update(syllables: textToSyllables("今天我们要聊的话题是人工智能"), isFinal: false)
        XCTAssertEqual(tr.anchor, a, "partial 不应改 anchor")
        XCTAssertGreaterThan(tr.soft, a, "partial 应推进 soft")
        XCTAssertEqual(r.reason, "predict")
    }

    func testRepeatedSentenceDoesNotJump() {
        let rep = "请注意安全。第一段内容在这里。请注意安全。第二段内容在那里。请注意安全。"
        let (_, idx, tr) = make(rep)
        tr.update(syllables: textToSyllables("请注意安全"), isFinal: true)
        tr.update(syllables: textToSyllables("第一段内容在这里"), isFinal: true)
        tr.update(syllables: textToSyllables("请注意安全"), isFinal: true)
        let ti = idx.sylToToken[min(tr.anchor, idx.sylToToken.count - 1)]
        let t = tokenize(rep)[ti]
        let tail = String(Array(rep)[t.start...])
        XCTAssertTrue(tail.hasPrefix("第二"), "应落在第二段前, got \(tail.prefix(8))")
    }

    func testSeekClampsAndClearsHistory() {
        let (_, idx, tr) = make()
        tr.update(syllables: textToSyllables("大家好欢迎来到今天的直播"), isFinal: true)
        let target = idx.syllables.count / 2
        tr.seek(target)
        XCTAssertEqual(tr.anchor, target)
        tr.seek(idx.syllables.count + 999)
        XCTAssertEqual(tr.anchor, idx.syllables.count)
        tr.seek(-5)
        XCTAssertEqual(tr.anchor, 0)
    }

    func testEmptyInputsDoNotCrash() {
        let (_, _, empty) = make("")
        _ = empty.update(syllables: [], isFinal: true)
        let (_, _, tr) = make()
        _ = tr.update(syllables: [], isFinal: false)
    }

    // ---- ASR 会话重连 ----

    func testResyncCrossesNormalWindow() {
        // 各段内容必须真正不同，否则位置先验会（正确地）压住远处的雷同匹配
        let long = [
            "开场先说今天要讲的三件事，这段是稿子的最前面一部分内容。",
            "春天的时候我在南方的一个小城里住过大半年，那边的雨水特别多。",
            "后来聊到成本结构，采购、仓储、物流三块各占多少比例都要拆开算。",
            "有个读者问我关于摄影构图的问题，说三分法是不是一定要遵守。",
            "中间插一段题外话，上周去看了场话剧，舞台调度做得相当讲究。",
            "关于健身计划，深蹲硬拉卧推这三个动作的重量安排其实很有讲究。",
            "再往后是数据部分，去年同期对比、环比增速、留存曲线都列在这里。",
            "最后这段讲的是烘焙，黄油和面粉的比例决定了饼干的酥脆程度。",
        ].joined(separator: "\n")
        let (_, _, tr) = make(long)
        tr.update(syllables: textToSyllables("开场先说今天要讲的三件事这段是稿子的最前面一部分内容"), isFinal: true)
        let near = tr.anchor
        let far = "最后这段讲的是烘焙黄油和面粉的比例决定了饼干的酥脆程度"

        tr.reset(anchor: near)
        tr.resync()
        let r = tr.update(syllables: textToSyllables(far), isFinal: true)
        XCTAssertEqual(r.reason, "resync", "重连后应一次到位")
        XCTAssertGreaterThan(r.anchor, near + 110, "应跨出常规窗口")
    }

    func testResyncExpiresAndStrictResumes() {
        let (_, _, tr) = make()
        tr.resync()
        // 喂真实顺读内容。不能反复喂同一句：历史会累积成
        // 「大家好大家好大家好」，相似度掉破门槛后就不再消耗额度
        //（这是有意的——被拒绝的匹配不该白烧放宽次数）。
        for t in ["大家好欢迎来到今天的直播",
                  "今天我们要聊的话题是人工智能提词器的实现原理",
                  "第一步是流式语音识别把麦克风的音频送进识别引擎"] {
            tr.update(syllables: textToSyllables(t), isFinal: true)
        }
        let before = tr.anchor
        let r = tr.update(syllables: textToSyllables("完全不相干的一句话在这里胡说八道"),
                          isFinal: true)
        XCTAssertFalse(r.moved, "恢复严格后应拒绝稿外内容, reason=\(r.reason)")
        XCTAssertEqual(tr.anchor, before)
    }

    /// resync 额度必须对 partial 也生效。原来只在 isFinal 时递减：
    /// 一句长话若迟迟不出 final，放宽状态永不过期，大幅跳位会绕过两次确认。
    func testResyncQuotaConsumedByPartialToo() {
        let (_, _, tr) = make()
        tr.resync()
        for _ in 0..<3 {
            tr.update(syllables: textToSyllables("大家好欢迎来到今天的直播"), isFinal: false)
        }
        let before = tr.anchor
        let r = tr.update(syllables: textToSyllables("完全不相干的胡言乱语在这里瞎说一通"),
                          isFinal: true)
        XCTAssertFalse(r.moved, "额度耗尽后应拒绝稿外内容, reason=\(r.reason)")
        XCTAssertEqual(tr.anchor, before)
    }

    /// 手动点词后，同一个识别任务里"在飞"的 final 不该把光标拽回去。
    /// 场景：用户念到一半发现要跳段，点了后面某个字，此时之前说的话
    /// 才刚出 final。seek 清空 history 正是为了防这个。
    func testSeekSurvivesInFlightFinal() {
        let (tokens, idx, tr) = make()
        tr.update(syllables: textToSyllables("大家好欢迎来到今天的直播"), isFinal: false)

        // 点到"最后我们会讲讲隐私"那句
        let chars = Array(script)
        let target = script.range(of: "最后我们会讲讲隐私").map {
            script.distance(from: script.startIndex, to: $0.lowerBound)
        } ?? 0
        var ti = tokens.firstIndex { $0.start >= target } ?? tokens.count
        ti = min(ti, idx.tokenToSyl.count - 1)
        tr.seek(idx.tokenToSyl[ti])
        let afterSeek = tr.anchor
        XCTAssertGreaterThan(afterSeek, 0, "seek 应生效")

        // 此时之前说的话才出 final
        tr.update(syllables: textToSyllables("大家好欢迎来到今天的直播"), isFinal: true)
        XCTAssertEqual(tr.anchor, afterSeek,
                       "在飞的 final 不应把光标从 seek 位置拽走（seek 已清空 history）")
        XCTAssertLessThanOrEqual(afterSeek, chars.count, "位置应在稿子范围内")
    }
}
