import XCTest
@testable import PrompterCore

/// 敏感词检测的回归测试。
/// 词表 1566 条由 tp-refs/banned-words.json 生成，这里验证检测逻辑本身。
final class SensitiveTests: XCTestCase {

    // MARK: - 场景分档

    /// 为什么必须分档：同一个词在不同语境结论相反。
    /// 「科普频道说养胃」正常，「食品带货说养胃」违反《广告法》第十七条。
    func testSceneDecidesWhetherEfficacyWordsFire() {
        let text = "今天聊聊养胃这件事，很多人问我排毒有没有用。"

        let story = Sensitive.scan(text, scene: .story)
        let sales = Sensitive.scan(text, scene: .sales)

        XCTAssertTrue(story.isEmpty,
            "科普场景不该报功效词，否则产品没人用（实际报了 \(story.map(\.word))）")
        XCTAssertFalse(sales.isEmpty, "带货场景必须报功效词")
        XCTAssertTrue(sales.contains { $0.word == "养胃" }, "带货稿应命中「养胃」")
    }

    /// 这是最容易写错的一处：功效词的 tier 全是 strict，
    /// 带货档必须**并入**而非与 core 取交集，否则整批漏掉。
    func testSalesSceneUnionsRatherThanIntersects() {
        let words = Sensitive.lexicon(scene: .sales).map(\.word)
        for w in ["养胃", "排毒", "通便"] {
            XCTAssertTrue(words.contains(w),
                "带货词表缺「\(w)」—— 大概率是把 sales 和 core 取了交集")
        }
        // 而科普档不该有它们
        let story = Sensitive.lexicon(scene: .story).map(\.word)
        XCTAssertFalse(story.contains("养胃"), "科普档不该含功效词")
    }

    func testAuditSceneIsSupersetOfBoth() {
        let audit = Set(Sensitive.lexicon(scene: .audit).map(\.word))
        let story = Set(Sensitive.lexicon(scene: .story).map(\.word))
        let sales = Set(Sensitive.lexicon(scene: .sales).map(\.word))
        XCTAssertTrue(audit.isSuperset(of: story), "全量档应包含科普档")
        XCTAssertTrue(audit.isSuperset(of: sales), "全量档应包含带货档")
        XCTAssertGreaterThan(audit.count, sales.count, "全量应比带货更多")
    }

    // MARK: - 命中准确性

    /// 长词优先。「全网最低价」不该只命中「全网最低」——
    /// 那会让替换后残留一个「价」字，输出「优惠价价」。
    func testLongestMatchWinsToAvoidLeftoverChars() {
        let hits = Sensitive.scan("全网最低价的好东西", scene: .sales)
        XCTAssertTrue(hits.contains { $0.word == "全网最低价" },
            "应命中完整的「全网最低价」，实际 \(hits.map(\.word))")
        XCTAssertFalse(hits.contains { $0.word == "全网最低" },
            "不该同时报短前缀，会导致替换残留")
    }

    /// 命中区间不重叠。同一段文字被两条规则命中时只报一次。
    func testHitsDoNotOverlap() {
        let text = "这是国家级的顶级产品，全网最低价。"
        let hits = Sensitive.scan(text, scene: .sales)
        let sorted = hits.sorted { $0.nsRange.location < $1.nsRange.location }
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            XCTAssertLessThanOrEqual(a.nsRange.location + a.nsRange.length,
                                     b.nsRange.location,
                "命中区间重叠: \(a.word) 与 \(b.word)")
        }
    }

    /// 区间必须能还原出命中的词，否则替换会改错位置。
    func testRangesMapBackToTheMatchedWord() {
        let text = "国家级认证，稳赚不赔，加我微信。"
        let ns = text as NSString
        for h in Sensitive.scan(text, scene: .sales) {
            XCTAssertEqual(ns.substring(with: h.nsRange), h.word,
                "区间与词不符: \(h.word) @ \(h.nsRange)")
        }
    }

    // MARK: - 平台过滤

    func testPlatformFilterNarrowsResults() {
        let text = "集赞有礼，三连投币走一波。"
        let wechat = Sensitive.scan(text, platforms: [.wechat], scene: .audit)
        let bili = Sensitive.scan(text, platforms: [.bili], scene: .audit)
        XCTAssertTrue(wechat.contains { $0.word == "集赞" },
            "公众号应命中「集赞」（官方规范原文点名）")
        XCTAssertTrue(bili.contains { $0.word.contains("三连") || $0.word.contains("投币") },
            "B站应命中三连投币类，实际 \(bili.map(\.word))")
    }

    // MARK: - 一键替换

    /// 从后往前改，否则前面的替换会让后面的区间失效。
    func testApplyReplacesAllHitsWithoutCorruption() {
        // 从词表动态取两个有替换建议的词，别写死具体词 ——
        // 某个词属于 core 还是 strict 是数据决定的，测试不该依赖它。
        let lex = Sensitive.lexicon(scene: .sales)
            .filter { !$0.replacement.isEmpty && $0.word.count >= 2 }
        guard lex.count >= 2 else { return XCTFail("词表应有足够的可替换词") }
        let a = lex[0].word, b = lex[1].word
        let text = "\(a)的\(b)产品"

        let hits = Sensitive.scan(text, scene: .sales)
        XCTAssertEqual(hits.count, 2, "两个词都该命中，实际 \(hits.map(\.word))")

        let out = Sensitive.apply(text, hits: hits, mode: .replace)
        XCTAssertFalse(out.contains(a), "「\(a)」应已替换：\(out)")
        XCTAssertFalse(out.contains(b), "「\(b)」应已替换：\(out)")
        XCTAssertTrue(out.contains("产品"), "非违规部分不该被动：\(out)")
    }

    /// 删除模式：连没有替换建议的词一起删。
    func testDeleteModeRemovesEvenWordsWithoutSuggestion() {
        let text = "包治百病还能开光"
        let hits = Sensitive.scan(text, scene: .audit)
        XCTAssertFalse(hits.isEmpty, "应有命中")
        let out = Sensitive.apply(text, hits: hits, mode: .delete)
        for h in hits {
            XCTAssertFalse(out.contains(h.word), "删除模式应移除「\(h.word)」")
        }
    }

    /// 替换模式遇到无建议的词应跳过而非误删 ——
    /// 用户选的是「替换」，不该悄悄删掉内容。
    func testReplaceModeSkipsWordsWithoutSuggestion() {
        let all = Sensitive.lexicon(scene: .audit)
        guard let noRepl = all.first(where: { $0.replacement.isEmpty }) else {
            return XCTFail("词表里应有无替换建议的词")
        }
        let text = "前缀\(noRepl.word)后缀"
        let hits = Sensitive.scan(text, scene: .audit)
        let out = Sensitive.apply(text, hits: hits, mode: .replace)
        XCTAssertTrue(out.contains(noRepl.word),
            "替换模式不该删掉无建议的词「\(noRepl.word)」")
    }

    /// 相邻重复替换词要合并。541 条词共用 53 个替换目标，
    /// 「养胃通便排毒」替换后会变成「日常养护日常养护日常养护」。
    func testAdjacentIdenticalReplacementsAreMerged() {
        let text = "养胃通便排毒三管齐下"
        let hits = Sensitive.scan(text, scene: .sales)
        guard hits.count >= 2 else { return XCTFail("应命中多个功效词") }
        let out = Sensitive.apply(text, hits: hits, mode: .replace)
        // 任一替换词都不该连续出现两次
        for r in Set(hits.map(\.replacement)) where !r.isEmpty {
            XCTAssertFalse(out.contains(r + r),
                "替换词「\(r)」重复出现: \(out)")
        }
        print("SENS 去重结果: \(text) -> \(out)")
    }

    /// 用户原文里本来就重复的表达不该被合并。
    func testUserOwnRepetitionIsPreserved() {
        let text = "很开心很开心，这个国家级认证真好。"
        let hits = Sensitive.scan(text, scene: .sales)
        let out = Sensitive.apply(text, hits: hits, mode: .replace)
        XCTAssertTrue(out.contains("很开心很开心"),
            "用户自己的重复表达不该被动: \(out)")
    }

    // MARK: - 词表不变量

    /// 循环替换会让用户改完还是违规。
    func testNoReplacementIsItselfBanned() {
        let all = Sensitive.lexicon(scene: .audit)
        let words = Set(all.map(\.word))
        let loops = all.filter { !$0.replacement.isEmpty && words.contains($0.replacement) }
        XCTAssertTrue(loops.isEmpty,
            "循环替换: " + loops.prefix(5).map { "\($0.word)→\($0.replacement)" }
                .joined(separator: ", "))
    }

    func testNoDuplicateWords() {
        let words = Sensitive.lexicon(scene: .audit).map(\.word)
        XCTAssertEqual(words.count, Set(words).count, "词表有重复词")
    }

    func testLexiconIsSubstantial() {
        XCTAssertGreaterThan(Sensitive.lexicon(scene: .audit).count, 1400,
            "词表规模不足，覆盖不了各平台违禁词")
    }

    // MARK: - 性能与边界

    /// 粘贴后要立刻出结果，不能让用户等。
    func testScanIsFastEnoughForInstantFeedback() {
        let script = String(repeating: "今天我们来聊聊这个产品的实际使用体验。", count: 160)
        let t0 = Date()
        _ = Sensitive.scan(script, scene: .audit)
        let ms = Date().timeIntervalSince(t0) * 1000
        print("SENS 性能: \(script.count) 字 × \(Sensitive.lexicon(scene: .audit).count) 词 = \(Int(ms))ms")
        XCTAssertLessThan(ms, 300, "扫描 \(Int(ms))ms 太慢，粘贴后会卡顿")
    }

    func testEmptyAndCleanTextYieldNothing() {
        XCTAssertTrue(Sensitive.scan("", scene: .audit).isEmpty)
        XCTAssertTrue(Sensitive.scan("今天天气不错，我们出去走走吧。", scene: .story).isEmpty,
            "干净的句子不该有命中")
    }

    /// 自定义词能覆盖内置建议。
    func testCustomWordOverridesBuiltinReplacement() {
        let custom = [CustomWord(word: "国家级", replacement: "我自己的说法")]
        let hits = Sensitive.scan("国家级认证", scene: .sales, custom: custom)
        XCTAssertEqual(hits.first?.replacement, "我自己的说法",
            "自定义替换应覆盖内置建议")
    }
}
