import Foundation

// 音节归一化。中文 ASR 错误绝大多数是同音字（"部署"->"不熟"），
// 字面匹配会崩，拼音层匹配毫发无伤。这层是方案能不能用的关键。
//
// iOS 自带汉字转拼音（CFStringTransform），不需要第三方拼音表，
// 所以这里比 Web 版还省事——Web 版得带 pinyin-pro 依赖。

/// 常见口音混淆折叠。普通话里 zh/z、sh/s、n/l、ing/in 分不清的很多，
/// 折叠掉能显著提高容错。代价是极少数真同音词的区分度，但对齐不需要那个精度。
private func fold(_ s: String) -> String {
    var t = s
    // 声母
    if t.hasPrefix("zh") { t = "z" + t.dropFirst(2) }
    else if t.hasPrefix("ch") { t = "c" + t.dropFirst(2) }
    else if t.hasPrefix("sh") { t = "s" + t.dropFirst(2) }
    else if t.hasPrefix("r") { t = "l" + t.dropFirst() }
    else if t.hasPrefix("n") { t = "l" + t.dropFirst() }
    // 韵母（顺序重要：长的先匹配）
    for (from, to) in [("iang", "ian"), ("uang", "uan"), ("ing", "in"),
                       ("eng", "en"), ("ang", "an")] {
        if t.hasSuffix(from) { t = String(t.dropLast(from.count)) + to; break }
    }
    return t
}

/// 数字口语化：稿子写 "2024"，人念"二零二四"或"两千零二十四"。
/// ASR 返回什么形态不定，两边都拆成单字数字音节，让编辑距离消化差异。
private let digitSyllable: [Character: String] = [
    "0": "lin", "1": "yi", "2": "er", "3": "san", "4": "si",
    "5": "wu", "6": "liu", "7": "qi", "8": "ba", "9": "jiu",
]

/// 汉字 -> 无声调拼音。用系统的 CFStringTransform，无第三方依赖。
private func toPinyin(_ s: String) -> [String] {
    let mutable = NSMutableString(string: s) as CFMutableString
    CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
    CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
    return (mutable as String)
        .lowercased()
        .split(separator: " ")
        .map { fold(String($0)) }
        .filter { !$0.isEmpty }
}

private final class SyllableCache: @unchecked Sendable {
    static let shared = SyllableCache()
    private var map: [String: [String]] = [:]
    private let lock = NSLock()
    func get(_ k: String) -> [String]? { lock.lock(); defer { lock.unlock() }; return map[k] }
    func set(_ k: String, _ v: [String]) {
        lock.lock(); defer { lock.unlock() }
        if map.count < 20_000 { map[k] = v }
    }
}

/// 单个 token -> 音节数组（一个 token 可能产出多个音节，如 "2024"）。
public func tokenSyllables(_ text: String) -> [String] {
    if let hit = SyllableCache.shared.get(text) { return hit }
    var out: [String]
    if !text.isEmpty, text.allSatisfy({ $0.isNumber && $0.isASCII }) {
        out = text.compactMap { digitSyllable[$0] }
    } else if text.unicodeScalars.contains(where: { isHan($0) }) {
        out = toPinyin(text)
    } else {
        out = [text.lowercased()]
    }
    if out.isEmpty { out = [text.lowercased()] }
    SyllableCache.shared.set(text, out)
    return out
}

/// 稿子索引：Tracker 在音节维度匹配，UI 在字符维度高亮，靠映射换算。
public struct ScriptIndex: Sendable {
    public let syllables: [String]
    public let sylToToken: [Int]   // 音节下标 -> token 下标
    public let tokenToSyl: [Int]   // token 下标 -> 起始音节下标（末尾多一位）
}

public func buildScriptIndex(_ tokens: [Token]) -> ScriptIndex {
    var syl: [String] = [], s2t: [Int] = [], t2s: [Int] = []
    for (ti, t) in tokens.enumerated() {
        t2s.append(syl.count)
        for s in tokenSyllables(t.text) { syl.append(s); s2t.append(ti) }
    }
    t2s.append(syl.count)
    return ScriptIndex(syllables: syl, sylToToken: s2t, tokenToSyl: t2s)
}

/// ASR 侧：识别文本 -> 音节数组。标点直接丢。
public func textToSyllables(_ text: String) -> [String] {
    var out: [String] = []
    var numBuf = ""
    func flushNum() {
        if !numBuf.isEmpty { out.append(contentsOf: tokenSyllables(numBuf)); numBuf = "" }
    }
    var latinBuf = ""
    func flushLatin() {
        if !latinBuf.isEmpty { out.append(latinBuf.lowercased()); latinBuf = "" }
    }
    for ch in text {
        if ch.isNumber, ch.isASCII { flushLatin(); numBuf.append(ch) }
        else if ch.isLetter, ch.isASCII { flushNum(); latinBuf.append(ch) }
        else if ch.unicodeScalars.first.map({ isHan($0) }) == true {
            flushNum(); flushLatin()
            out.append(contentsOf: tokenSyllables(String(ch)))
        } else { flushNum(); flushLatin() }
    }
    flushNum(); flushLatin()
    return out
}
