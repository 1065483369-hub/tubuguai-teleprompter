import Foundation

// 稿件预处理：标气口、断句、标语速。与 Web 版 prep.mjs 行为一致。
// 规则实现，不联网、不花钱、结果可预期。

public enum Pace: String, Sendable { case slow, normal, fast }

public struct Line: Sendable {
    public let text: String
    public let start: Int      // 原文字符偏移
    public let end: Int
    public let breath: Breath
    public var pace: Pace
}

private let punctBreath: [Character: Breath] = [
    "，": .short, ",": .short, "、": .short,
    "；": .medium, ";": .medium, "：": .medium, ":": .medium,
    "。": .long, ".": .long, "！": .long, "!": .long,
    "？": .long, "?": .long, "…": .long,
]

// 需要放慢的信号：数字、序数、转折与结论。这些地方听众要反应时间。
private let slowHints = ["关键", "重点", "注意", "核心", "结论", "但是", "然而", "其实", "问题在于"]
private let slowOrdinals = ["第一", "第二", "第三", "第四", "第五", "第六", "第七", "第八", "第九", "第十"]
// 可以带快的：铺垫和过渡
private let fastPrefixes = ["那么", "然后", "接下来", "另外", "顺便", "对了", "所以说", "总之", "好的"]

private func hasSlowHint(_ s: String) -> Bool {
    // 只认阿拉伯数字。Swift 的 Character.isNumber 对汉字数字（一、二、十）也为 true，
    // 会把"聊一聊""说一下"误判成慢速，所以必须限定 ASCII。
    // 汉字序数由 slowOrdinals 的"第X"前缀负责，不会误伤。
    if s.contains(where: { $0.isASCII && $0.isNumber }) || s.contains("%") || s.contains("％") {
        return true
    }
    return slowHints.contains { s.contains($0) } || slowOrdinals.contains { s.contains($0) }
}

/// 把稿子切成"一口气一行"。
/// 两步走：先按标点切成原子单元，再合并到舒适长度。分两步比边攒边判断清楚，
/// 也不会出现"开头三个字单独一行"这类碎片。
public func segment(_ text: String, maxLen: Int = 18, hardLen: Int = 14) -> [Line] {
    let chars = Array(text)

    // ---- 第一步：切成原子单元 ----
    struct Unit { let text: String; let start: Int; let end: Int; let breath: Breath }
    var units: [Unit] = []
    var buf = ""
    var bufStart = 0
    func push(_ b: Breath, _ endIdx: Int) {
        let t = buf.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { units.append(Unit(text: t, start: bufStart, end: endIdx, breath: b)) }
        buf = ""
    }
    for (i, ch) in chars.enumerated() {
        if buf.isEmpty { bufStart = i }
        if ch == "\n" { push(.long, i); continue }
        buf.append(ch)
        if let b = punctBreath[ch] { push(b, i + 1); continue }
        if buf.count >= hardLen { push(.short, i + 1) }   // 无标点硬断
    }
    push(.long, chars.count)

    // ---- 第二步：合并到舒适长度 ----
    // 句末（长气口）收行，不跨句合并；否则攒到接近 maxLen。
    var lines: [Line] = []
    var cur: Line?
    for u in units {
        if let c = cur, c.text.count + u.text.count <= maxLen {
            cur = Line(text: c.text + u.text, start: c.start, end: u.end,
                       breath: u.breath, pace: .normal)
        } else {
            if let c = cur { lines.append(c) }
            cur = Line(text: u.text, start: u.start, end: u.end, breath: u.breath, pace: .normal)
        }
        if let c = cur, c.breath == .long { lines.append(c); cur = nil }
    }
    if let c = cur { lines.append(c) }

    // ---- 标语速 ----
    for i in lines.indices {
        if hasSlowHint(lines[i].text) { lines[i].pace = .slow }
        else if fastPrefixes.contains(where: { lines[i].text.hasPrefix($0) }) { lines[i].pace = .fast }
    }
    return lines
}

/// 预估朗读时长（秒）。中文口播正常约 4.5 字/秒；慢速打七折，快速加三成。
public func estimateDuration(_ lines: [Line]) -> Int {
    let cps = 4.5
    let breathSec: [Breath: Double] = [.none: 0, .short: 0.25, .medium: 0.45, .long: 0.7]
    var sec = 0.0
    for ln in lines {
        let rate = ln.pace == .slow ? cps * 0.7 : ln.pace == .fast ? cps * 1.3 : cps
        sec += Double(ln.text.count) / rate + (breathSec[ln.breath] ?? 0)
    }
    return Int(sec.rounded())
}

public func formatDuration(_ sec: Int) -> String {
    let m = sec / 60, s = sec % 60
    return m > 0 ? "\(m)分\(s)秒" : "\(s)秒"
}
