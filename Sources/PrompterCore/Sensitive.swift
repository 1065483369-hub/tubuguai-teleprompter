import Foundation

// 口播稿敏感词检测。与 Web 版 public/sensitive.js 同一套词库与口径：
// 《广告法》第九条（绝对化用语）、第十七条（非医疗广告不得宣称疗效），
// 以及抖音、小红书、B 站、公众号公开的营销审核口径。
//
// 刻意不收全网政治词库——那种词库拿到口播稿上误伤太重，
// 「第一步」「最近」「这一步最重要」全都会被判红，检测结果就没人看了。
// 仅供参考，不能替代平台人工审核。

public enum Platform: String, CaseIterable, Sendable {
    case douyin, xhs, bili, wechat

    public var label: String {
        switch self {
        case .douyin: return "抖音"
        case .xhs: return "小红书"
        case .bili: return "哔哩哔哩"
        case .wechat: return "公众号"
        }
    }
}

public enum RiskCategory: String, Sendable {
    case ads, health, finance, traffic, illegal, cosmetic, custom
    // 调研数据集新增的类别
    case platform, promo, taboo, edu, minors, politics

    public var label: String {
        switch self {
        case .ads: return "广告法极限词"
        case .health: return "医疗保健功效"
        case .finance: return "金融承诺收益"
        case .traffic: return "站外引流"
        case .illegal: return "违规营销"
        case .cosmetic: return "医美减肥承诺"
        case .platform: return "平台专属规则"
        case .promo: return "促销话术违规"
        case .taboo: return "低俗迷信违规"
        case .edu: return "教育培训承诺"
        case .minors: return "涉未成年人"
        case .politics: return "政治敏感边界"
        case .custom: return "自定义"
        }
    }

    public var reason: String {
        switch self {
        case .ads: return "《广告法》禁止绝对化用语，四个平台都会卡"
        case .health: return "非医疗广告不得宣称治疗功效，未认证账号高风险"
        case .finance: return "不得承诺保本保息或稳赚，财经口播严打"
        case .traffic: return "引导加微信、私聊、扣 1，平台会限流或下架"
        case .illegal: return "刷单、代开发票、博彩等，直接封禁风险"
        case .cosmetic: return "医美/减肥功效承诺，小红书和抖音特别严"
        case .platform: return "某个平台单独禁的词，换平台可能没事"
        case .promo: return "限时秒杀、全网最低这类话术，广告法和平台都管"
        case .taboo: return "低俗、迷信、暴力边界词，容易直接下架"
        case .edu: return "不得承诺升学率、保过、名师"
        case .minors: return "涉及未成年人的表述格外严格"
        case .politics: return "国家标志、领导人、版图等，商业营销语境下违规"
        case .custom: return "你自己加的词，按你设的替换"
        }
    }
}

/// 检测场景。决定用哪档词表。
///
/// 为什么不能只用一个 strict 开关：同一个词在不同语境结论相反 ——
/// 「食品带货说养胃」违反《广告法》第十七条，「科普频道说养胃」完全正常。
/// 一个全局开关表达不了，所以按稿子用途分档。
public enum ScanScene: String, CaseIterable, Sendable {
    case story    // 科普 / 测评 / 叙事
    case sales    // 带货 / 口播销售
    case audit    // 全量自查

    public var label: String {
        switch self {
        case .story: return "科普测评"
        case .sales: return "带货口播"
        case .audit: return "全量自查"
        }
    }

    public var hint: String {
        switch self {
        case .story: return "不扫功效词，「养胃」「第一步」不会误报"
        case .sales: return "加扫功效词与疾病名，卖货稿必开"
        case .audit: return "全部词都扫，日常口语也会提示"
        }
    }
}

public enum Severity: String, Sendable {
    case high, mid, low

    /// 展示用标签。用户要的是"会有什么后果"，不是内部等级名。
    public var label: String {
        switch self {
        case .high: return "会下架"
        case .mid:  return "会限流"
        case .low:  return "看上下文"
        }
    }
}

public struct LexEntry: Sendable {
    public let word: String
    public let replacement: String
    public let category: RiskCategory
    public let severity: Severity
    public let platforms: Set<Platform>

    init(_ word: String, _ replacement: String, _ category: RiskCategory,
         _ severity: Severity, _ platforms: Set<Platform> = Set(Platform.allCases)) {
        self.word = word
        self.replacement = replacement
        self.category = category
        self.severity = severity
        self.platforms = platforms
    }
}

/// 一处命中。`range` 是原文里的字符串范围，直接拿去替换不必再查找。
public struct Hit: Sendable {
    public let word: String
    public let replacement: String
    public let category: RiskCategory
    public let severity: Severity
    public let platforms: [Platform]
    public let range: Range<String.Index>
    /// UTF-16 偏移，给 UITextView / NSRange 用
    public let nsRange: NSRange

    public var reason: String { category.reason }
    public var canReplace: Bool { !replacement.isEmpty }
    public var platformLabel: String { platforms.map(\.label).joined(separator: "、") }
}

public struct CustomWord: Sendable, Codable, Equatable {
    public var word: String
    public var replacement: String
    public init(word: String, replacement: String) {
        self.word = word
        self.replacement = replacement
    }
}

public enum ApplyMode: Sendable { case replace, delete }

public struct Sensitive {

    static let base: [LexEntry] = [
        LexEntry("国家级", "知名", .ads, .high),
        LexEntry("世界级", "知名", .ads, .high),
        LexEntry("最高级", "高端", .ads, .high),
        LexEntry("最佳", "很合适", .ads, .high),
        LexEntry("最优", "更合适", .ads, .high),
        LexEntry("最强", "突出", .ads, .high),
        LexEntry("最便宜", "更划算", .ads, .high),
        LexEntry("最低价", "优惠价", .ads, .high),
        LexEntry("全网最低", "优惠价", .ads, .high),
        LexEntry("史上最低", "优惠价", .ads, .high),
        LexEntry("最先进", "较新", .ads, .high),
        LexEntry("最有效", "有帮助", .ads, .high),
        LexEntry("第一品牌", "知名品牌", .ads, .high),
        LexEntry("全国第一", "名列前茅", .ads, .high),
        LexEntry("全网第一", "名列前茅", .ads, .high),
        LexEntry("销量第一", "销量靠前", .ads, .high),
        LexEntry("行业第一", "行业前列", .ads, .high),
        LexEntry("NO.1", "前列", .ads, .high),
        LexEntry("No.1", "前列", .ads, .high),
        LexEntry("独一无二", "少见", .ads, .high),
        LexEntry("绝无仅有", "少见", .ads, .high),
        LexEntry("史无前例", "少见", .ads, .high),
        LexEntry("前无古人", "少见", .ads, .high),
        LexEntry("后无来者", "少见", .ads, .high),
        LexEntry("顶级", "高端", .ads, .mid),
        LexEntry("顶尖", "领先", .ads, .mid),
        LexEntry("王牌", "主打", .ads, .mid),
        LexEntry("领袖品牌", "知名品牌", .ads, .high),
        LexEntry("万能", "多用", .ads, .high),
        LexEntry("无敌", "出色", .ads, .high),
        LexEntry("永久有效", "长期可用", .ads, .high),
        LexEntry("100%有效", "效果因人而异", .ads, .high),
        LexEntry("百分之百有效", "效果因人而异", .ads, .high),
        LexEntry("绝对有效", "效果因人而异", .ads, .high),
        LexEntry("填补国内空白", "较少见", .ads, .high),
        LexEntry("填补空白", "较少见", .ads, .high),
        LexEntry("一经使用", "用过之后", .ads, .mid),
        LexEntry("大品牌指定", "常见选择", .ads, .mid),

        LexEntry("包治百病", "日常调理", .health, .high),
        LexEntry("药到病除", "对症使用", .health, .high),
        LexEntry("祖传秘方", "传统配方", .health, .high),
        LexEntry("根治", "改善", .health, .high),
        LexEntry("治愈", "好转", .health, .high),
        LexEntry("特效药", "常用药", .health, .high),
        LexEntry("速效", "较快", .health, .mid),
        LexEntry("立竿见影", "可能有感", .health, .high),
        LexEntry("无副作用", "相对温和", .health, .high),
        LexEntry("纯天然无添加", "成分相对简单", .health, .mid),
        LexEntry("降三高", "辅助管理三高", .health, .high),
        LexEntry("增强免疫力", "有助于日常养护", .health, .high),
        LexEntry("提高免疫力", "有助于日常养护", .health, .high),
        LexEntry("抗癌", "日常养护", .health, .high),
        LexEntry("防癌", "日常养护", .health, .high),
        LexEntry("抗肿瘤", "日常养护", .health, .high),
        LexEntry("消炎灭菌", "清洁护理", .health, .high),

        LexEntry("保本保息", "有波动", .finance, .high),
        LexEntry("稳赚不赔", "有风险", .finance, .high),
        LexEntry("稳赚", "可能有收益", .finance, .high),
        LexEntry("零风险", "有风险", .finance, .high),
        LexEntry("没有风险", "有风险", .finance, .high),
        LexEntry("100%回本", "不保证回本", .finance, .high),
        LexEntry("保证收益", "收益不固定", .finance, .high),
        LexEntry("日入过万", "收入因人而异", .finance, .high),
        LexEntry("躺赚", "需要投入", .finance, .high),
        LexEntry("高收益低风险", "风险与收益并存", .finance, .high),
        LexEntry("内幕消息", "", .finance, .high),
        LexEntry("稳赚秘籍", "", .finance, .high),
        LexEntry("保本", "本金有波动", .finance, .high),

        LexEntry("加我微信", "看主页", .traffic, .mid),
        LexEntry("加微信", "看主页", .traffic, .mid),
        LexEntry("加我V", "看主页", .traffic, .mid),
        LexEntry("加我v", "看主页", .traffic, .mid),
        LexEntry("加V信", "看主页", .traffic, .mid),
        LexEntry("加薇信", "看主页", .traffic, .mid),
        LexEntry("加威信", "看主页", .traffic, .mid),
        LexEntry("薇信", "主页", .traffic, .mid),
        LexEntry("扣1", "看评论", .traffic, .mid),
        LexEntry("扣一", "看评论", .traffic, .mid),
        LexEntry("私聊我", "看主页", .traffic, .mid),
        LexEntry("扫码加我", "看主页", .traffic, .mid),
        LexEntry("扫码加", "看主页", .traffic, .mid),

        LexEntry("代开发票", "", .illegal, .high),
        LexEntry("代开增值税", "", .illegal, .high),
        LexEntry("办证", "", .illegal, .high),
        LexEntry("假证", "", .illegal, .high),
        LexEntry("刷单", "", .illegal, .high),
        LexEntry("返利刷", "", .illegal, .high),
        LexEntry("网赌", "", .illegal, .high),
        LexEntry("六合彩", "", .illegal, .high),
        LexEntry("私服", "", .illegal, .high),
        LexEntry("外挂", "", .illegal, .high),
        LexEntry("博彩", "", .illegal, .high),

        LexEntry("七日瘦", "减重计划", .cosmetic, .high, [.douyin, .xhs]),
        LexEntry("7日瘦", "减重计划", .cosmetic, .high, [.douyin, .xhs]),
        LexEntry("躺着瘦", "减重", .cosmetic, .high, [.douyin, .xhs]),
        LexEntry("躺瘦", "减重", .cosmetic, .high, [.douyin, .xhs]),
        LexEntry("不用运动", "配合运动", .cosmetic, .mid, [.douyin, .xhs]),
        LexEntry("永久瘦", "维持体态", .cosmetic, .high, [.douyin, .xhs]),
        LexEntry("永久脱毛", "长期脱毛", .cosmetic, .high, [.douyin, .xhs]),
        LexEntry("逆龄", "保养", .cosmetic, .mid, [.douyin, .xhs, .wechat]),
        LexEntry("回春", "保养", .cosmetic, .mid, [.douyin, .xhs]),
        LexEntry("去除皱纹", "淡化细纹", .cosmetic, .high, [.douyin, .xhs, .wechat]),
        LexEntry("美白祛斑", "提亮肤色", .cosmetic, .high, [.douyin, .xhs, .wechat]),
        LexEntry("药妆", "护肤品", .cosmetic, .high, [.douyin, .xhs, .wechat]),
        LexEntry("医学护肤品", "护肤品", .cosmetic, .high, [.douyin, .xhs, .wechat]),
    ]

    /// 严格模式追加的短词。默认不启用——它们在口播稿里误伤率高
    /// （「第一步」「这一步最重要」「治疗方案介绍」）。
    static let strictExtra: [LexEntry] = [
        LexEntry("第一", "前列", .ads, .high),
        LexEntry("唯一", "少见", .ads, .high),
        LexEntry("绝对", "相对", .ads, .high),
        LexEntry("永久", "长期", .ads, .high),
        LexEntry("独家", "少见", .ads, .mid),
        LexEntry("权威", "专业", .ads, .mid),
        LexEntry("专家推荐", "有人在用", .ads, .high),
        LexEntry("必买", "可考虑", .ads, .mid),
        LexEntry("秒杀", "优惠", .ads, .mid),
        LexEntry("限量", "数量有限", .ads, .mid),
        LexEntry("疗效", "效果", .health, .high),
        LexEntry("治疗", "调理", .health, .high),
        LexEntry("处方", "", .health, .high),
        LexEntry("临床验证", "有人反馈", .health, .high),
        LexEntry("医院指定", "常见选择", .health, .high),
        LexEntry("立刻见效", "因人而异", .health, .high),
        LexEntry("马上见效", "因人而异", .health, .high),
        LexEntry("暴利", "收益不固定", .finance, .high),
        LexEntry("翻倍", "可能上涨", .finance, .high),
        LexEntry("必赚", "有风险", .finance, .high),
        LexEntry("必瘦", "减重", .cosmetic, .high, [.douyin, .xhs]),
    ]

    /// 合成生效词库：内置 +（可选）严格模式 + 自定义。
    /// 自定义词同名时覆盖内置的替换建议，让用户能改掉不合口味的建议。
    public static func lexicon(scene: ScanScene,
                               custom: [CustomWord] = []) -> [LexEntry] {
        var byWord: [String: LexEntry] = [:]
        var order: [String] = []
        func put(_ e: LexEntry) {
            if byWord[e.word] == nil { order.append(e.word) }
            byWord[e.word] = e
        }
        for e in generatedBase { put(e) }
        // 带货与自查都要并入功效词。注意是**并入**而非与 core 取交集 ——
        // 这些词的 tier 都是 strict，取交集会把「养胃」「排毒」「糖尿病」整批漏掉。
        if scene == .sales || scene == .audit {
            for e in generatedSales where byWord[e.word] == nil { put(e) }
        }
        if scene == .audit {
            for e in generatedStrict where byWord[e.word] == nil { put(e) }
        }
        for c in custom {
            let word = c.word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { continue }
            let rep = c.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
            if let prev = byWord[word] {
                put(LexEntry(word, rep, prev.category, prev.severity, prev.platforms))
            } else {
                put(LexEntry(word, rep, .custom, .high))
            }
        }
        return order.compactMap { byWord[$0] }
    }

    /// 扫描全文。长词优先，命中区间不重叠——否则「全网第一」会被
    /// 「第一」再报一次，同一段文字重复报警。
    public static func scan(_ text: String,
                            platforms: Set<Platform> = Set(Platform.allCases),
                            scene: ScanScene = .story,
                            custom: [CustomWord] = []) -> [Hit] {
        guard !text.isEmpty else { return [] }
        let allow = platforms.isEmpty ? Set(Platform.allCases) : platforms
        let words = lexicon(scene: scene, custom: custom)
            .filter { !$0.platforms.isDisjoint(with: allow) }
            .sorted { $0.word.count > $1.word.count }

        let ns = text as NSString
        var taken = [Bool](repeating: false, count: ns.length)
        var hits: [Hit] = []

        for entry in words {
            var from = 0
            while from < ns.length {
                let found = ns.range(of: entry.word,
                                     options: [.literal],
                                     range: NSRange(location: from, length: ns.length - from))
                if found.location == NSNotFound { break }
                from = found.location + 1
                var overlap = false
                for i in found.location..<(found.location + found.length) where taken[i] {
                    overlap = true
                    break
                }
                if overlap { continue }
                for i in found.location..<(found.location + found.length) { taken[i] = true }
                guard let r = Range(found, in: text) else { continue }
                hits.append(Hit(word: entry.word,
                                replacement: entry.replacement,
                                category: entry.category,
                                severity: entry.severity,
                                platforms: entry.platforms.filter { allow.contains($0) }
                                    .sorted { $0.rawValue < $1.rawValue },
                                range: r,
                                nsRange: found))
            }
        }
        return hits.sorted { $0.nsRange.location < $1.nsRange.location }
    }

    /// 应用处理。**从后往前改**——从前往后会让后面命中的偏移全部串位。
    /// 原文被手动编辑过时，位置对不上的命中直接跳过而不是盲改。
    public static func apply(_ text: String, hits: [Hit], mode: ApplyMode,
                             only index: Int? = nil) -> String {
        let chosen: [Hit]
        if let i = index {
            guard hits.indices.contains(i) else { return text }
            chosen = [hits[i]]
        } else {
            chosen = hits
        }
        var out = text as NSString
        for h in chosen.sorted(by: { $0.nsRange.location > $1.nsRange.location }) {
            let r = h.nsRange
            guard r.location >= 0, r.location + r.length <= out.length else { continue }
            guard out.substring(with: r) == h.word else { continue }
            if mode == .replace && h.replacement.isEmpty { continue }
            let next = mode == .delete ? "" : h.replacement
            out = out.replacingCharacters(in: r, with: next) as NSString
        }
        return mergeAdjacentRepeats(out as String, hits: chosen)
    }

    /// 合并相邻重复的替换词。
    ///
    /// 541 条有替换建议的词共用 53 个替换目标（「日常养护」被 108 条共用），
    /// 所以「养胃通便排毒」三个词相邻替换后会变成「日常养护日常养护日常养护」。
    /// 数据层解决不了 —— 总得有词共用同一个安全表达。
    ///
    /// 只合并本次实际命中的替换词：用户原文里本来就重复的表达
    /// （「很开心很开心」）不该被动。
    private static func mergeAdjacentRepeats(_ text: String, hits: [Hit]) -> String {
        let reps = Set(hits.map(\.replacement).filter { !$0.isEmpty })
            .sorted { $0.count > $1.count }      // 长的先合，避免短词先吃掉一半
        guard !reps.isEmpty else { return text }

        var out = text
        for r in reps {
            let esc = NSRegularExpression.escapedPattern(for: r)
            // 中间允许顶格的逗号顿号和空白：「日常养护，日常养护」也要合
            let pattern = "(?:\(esc))(?:\\s*[，、,]?\\s*(?:\(esc)))+"
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            out = re.stringByReplacingMatches(
                in: out, range: NSRange(out.startIndex..., in: out), withTemplate: r)
        }
        return out
    }

    /// 命中处的上下文，给列表展示用。
    public static func snippet(_ text: String, range: NSRange, radius: Int = 8) -> String {
        let ns = text as NSString
        let lo = max(0, range.location - radius)
        let hi = min(ns.length, range.location + range.length + radius)
        var s = ns.substring(with: NSRange(location: lo, length: hi - lo))
        if lo > 0 { s = "…" + s }
        if hi < ns.length { s += "…" }
        return s
    }
}
