import Foundation

// 对齐引擎。从 Web 版 align.mjs 移植，行为保持一致（同一套测试用例）。
// 纯值语义、无 IO，所以能脱离设备跑单测。

public enum Breath: Int, Sendable {
    case none = 0, short = 1, medium = 2, long = 3
}

public struct Token: Sendable, Equatable {
    public let text: String
    public let start: Int   // 原文字符偏移（UTF-16 无关，按 Character 计）
    public let end: Int
    public init(text: String, start: Int, end: Int) {
        self.text = text; self.start = start; self.end = end
    }
}

/// 稿子切分：汉字逐字，拉丁词整词，标点跳过但不打乱偏移。
public func tokenize(_ text: String) -> [Token] {
    var out: [Token] = []
    let chars = Array(text)
    var i = 0
    func isWordChar(_ c: Character) -> Bool {
        c.isLetter && c.isASCII || c.isNumber && c.isASCII || c == "'"
    }
    while i < chars.count {
        let c = chars[i]
        if c.unicodeScalars.first.map({ isHan($0) }) == true {
            out.append(Token(text: String(c), start: i, end: i + 1))
            i += 1
        } else if isWordChar(c) {
            var j = i
            while j < chars.count, isWordChar(chars[j]) { j += 1 }
            out.append(Token(text: String(chars[i..<j]), start: i, end: j))
            i = j
        } else {
            i += 1  // 标点、空格、换行不参与匹配
        }
    }
    return out
}

@inline(__always)
func isHan(_ s: Unicode.Scalar) -> Bool {
    let v = s.value
    return (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v)
        || (0xF900...0xFAFF).contains(v) || (0x20000...0x2A6DF).contains(v)
}

/// 音节数组的编辑距离。滚动数组，query 只有十几个元素，够快。
public func editDistance(_ a: [String], _ b: [String]) -> Int {
    let n = a.count, m = b.count
    if n == 0 { return m }
    if m == 0 { return n }
    var prev = Array(0...m)
    var cur = [Int](repeating: 0, count: m + 1)
    for i in 1...n {
        cur[0] = i
        let ai = a[i - 1]
        for j in 1...m {
            let cost = ai == b[j - 1] ? 0 : 1
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
        }
        swap(&prev, &cur)
    }
    return prev[m]
}

public func similarity(_ a: [String], _ b: [String]) -> Double {
    let L = max(a.count, b.count)
    return L == 0 ? 1 : 1 - Double(editDistance(a, b)) / Double(L)
}

public struct TrackerOptions: Sendable {
    public var queryLen = 12
    public var backWindow = 30
    public var fwdWindow = 110
    public var acceptFinal = 0.62
    public var acceptPartial = 0.72
    public var jumpGap = 45
    public var jumpConfirm = 2
    /// 高置信跳读免确认：相似度这么高的远处匹配几乎不可能是噪音，
    /// 而要求说两遍会让光标永远落后一句（实测跳 2 句要念两遍才跟上）。
    public var jumpInstant = 0.82
    /// partial 远跳的放行门槛。比 final 高：partial 会被改写，
    /// 但完全丢弃会导致「长时间不停顿」时光标卡死（实测落后 76 字）。
    public var jumpInstantPartial = 0.9
    public var backGap = 6
    public var historyLen = 24
    // ASR 会话重连后位置不可信，短期放宽窗口与门槛
    public var resyncBack = 120
    public var resyncFwd = 300
    public var resyncAccept = 0.55
    public var resyncUpdates = 3
    public init() {}
}

public struct TrackResult: Sendable {
    public let anchor: Int
    public let soft: Int
    public let moved: Bool
    public let sim: Double
    public let reason: String
}

public final class Tracker {
    private let syl: [String]
    private let n: Int
    private let o: TrackerOptions
    public private(set) var anchor = 0
    public private(set) var soft = 0
    private var history: [String] = []
    private var partial: [String] = []
    private var pendingJump: (pos: Int, count: Int)?
    private var resyncLeft = 0

    public init(syllables: [String], options: TrackerOptions = TrackerOptions()) {
        self.syl = syllables
        self.n = syllables.count
        self.o = options
    }

    public func reset(anchor: Int = 0) {
        self.anchor = anchor; self.soft = anchor
        history = []; partial = []; pendingJump = nil; resyncLeft = 0
    }

    /// 手动点词后强制校准，清历史避免旧语音把位置拽回去。
    public func seek(_ pos: Int) {
        reset(anchor: max(0, min(n, pos)))
    }

    /// ASR 断连重连后调用：接下来几次放宽窗口和门槛，让光标重新咬住位置。
    public func resync() {
        resyncLeft = o.resyncUpdates
        pendingJump = nil
    }

    private func buildQuery() -> [String] {
        let h = history.suffix(o.historyLen)
        let src = Array(h) + partial
        return Array(src.suffix(o.queryLen))
    }

    /// 位置先验：只用于候选排序，不参与准入，否则远处的正确匹配会被压死。
    private func prior(_ delta: Int) -> Double {
        delta >= 0 ? 1 / (1 + Double(delta) * 0.006)
                   : 1 / (1 + Double(-delta) * 0.02)
    }

    private func search(_ query: [String]) -> (pos: Int, sim: Double)? {
        let L = query.count
        if L == 0 || n == 0 { return nil }
        let wide = resyncLeft > 0
        let back = wide ? o.resyncBack : o.backWindow
        let fwd = wide ? o.resyncFwd : o.fwdWindow
        let lo = max(L, anchor - back)
        let hi = min(n, anchor + fwd)
        if lo > hi { return nil }
        var best: (pos: Int, sim: Double)?
        var bestRank = -Double.infinity
        for p in lo...hi {
            let from = max(0, p - L)
            let s = similarity(Array(syl[from..<p]), query)
            let rank = s * prior(p - anchor)
            if rank > bestRank { bestRank = rank; best = (p, s) }
        }
        return best
    }

    /// 喂一条 ASR 结果。isFinal=false 的 partial 只推 soft，不动 anchor。
    @discardableResult
    public func update(syllables: [String], isFinal: Bool) -> TrackResult {
        if isFinal {
            history.append(contentsOf: syllables)
            partial = []
        } else {
            partial = syllables  // partial 是整句重写，直接替换
        }

        func out(_ moved: Bool, _ sim: Double, _ reason: String) -> TrackResult {
            TrackResult(anchor: anchor, soft: soft, moved: moved, sim: sim, reason: reason)
        }

        let query = buildQuery()
        guard let hit = search(query) else { return out(false, 0, "no-query") }

        let wide = resyncLeft > 0
        let threshold = wide ? o.resyncAccept : (isFinal ? o.acceptFinal : o.acceptPartial)

        if hit.sim < threshold {
            pendingJump = nil
            return out(false, hit.sim, "below-threshold")  // 即兴/噪音/跑题
        }

        // 放宽额度按「成功咬住位置的次数」消耗，partial 也算。
        // 原来只在 isFinal 时递减：一句长话如果迟迟不出 final，
        // 放宽状态就永不过期，此时大幅跳位会绕过两次确认直接生效。
        if resyncLeft > 0 { resyncLeft -= 1 }

        let delta = hit.pos - anchor

        // resync 期间位置本就不可信，直接接受最佳匹配
        if wide {
            anchor = hit.pos; soft = hit.pos
            return out(true, hit.sim, "resync")
        }

        // 跳读：位置大幅前跳。
        if delta > o.jumpGap {
            if !isFinal {
                // partial 的远跳原本一律忽略，但这会在「长时间不停顿」时卡死：
                // 没有 final → anchor 不动 → 搜索窗锚在旧位置 → 越念越远 →
                // 全被判成跳读丢弃。实测相似度 1.000 也被丢，落后 76 字。
                if hit.sim >= o.jumpInstantPartial {
                    anchor = hit.pos; soft = hit.pos
                    return out(true, hit.sim, "jump-partial")
                }
                return out(false, hit.sim, "jump-partial-ignored")
            }
            // 匹配得非常好就直接跳。噪音不可能和稿子某段高度吻合，
            // 而让用户把跳到的那句说两遍才跟上是不能接受的。
            if hit.sim >= o.jumpInstant {
                pendingJump = nil
                anchor = hit.pos; soft = hit.pos
                return out(true, hit.sim, "jump")
            }
            let near = pendingJump.map { abs($0.pos - hit.pos) <= 12 } ?? false
            let count = near ? (pendingJump!.count + 1) : 1
            pendingJump = (hit.pos, count)
            if count < o.jumpConfirm { return out(false, hit.sim, "jump-pending") }
            pendingJump = nil
            anchor = hit.pos; soft = hit.pos
            return out(true, hit.sim, "jump")
        }
        pendingJump = nil

        // 回读：重念一句，立刻跟上
        if delta < -o.backGap {
            anchor = hit.pos; soft = hit.pos
            return out(true, hit.sim, "backtrack")
        }

        if isFinal {
            anchor = hit.pos
            soft = max(soft, hit.pos)
            return out(true, hit.sim, "advance")
        }

        if hit.pos > soft {
            soft = hit.pos
            return out(true, hit.sim, "predict")
        }
        return out(false, hit.sim, "stale-partial")
    }
}
