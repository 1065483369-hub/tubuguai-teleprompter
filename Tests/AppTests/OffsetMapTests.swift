import XCTest
@testable import Prompter

/// 高亮偏移映射的回归测试。
///
/// 曾经的 bug：`visualOffset` 按 Character 累加，但 `NSAttributedString.length`
/// 是 UTF-16 长度。"\r\n" 是 1 个 Character 却占 2 个 UTF-16 单元，emoji 同理，
/// 于是读到后面高亮整体偏移。CRLF 特别常见——从 Word / Windows 复制稿子就是。
///
/// 修法是渲染时建一张权威映射表，高亮和点词都查表。这里验证该表的性质。
final class OffsetMapTests: XCTestCase {

    /// 复刻控制器建表的逻辑，验证表本身的不变量。
    /// （控制器的表是 private，这里用同样规则构造并断言性质。）
    private func buildMap(_ script: String) -> (map: [Int], total: Int) {
        let lines = segment(script)
        let chars = Array(script)
        var breathAt: [Int: Breath] = [:]
        var paceAt: [Int: Pace] = [:]
        for ln in lines {
            breathAt[ln.end] = ln.breath
            if ln.pace != .normal { paceAt[ln.start] = ln.pace }
        }
        let attr = NSMutableAttributedString()
        var map: [Int] = []
        for i in chars.indices {
            if paceAt[i] != nil { attr.append(NSAttributedString(string: " 慢 ")) }
            map.append(attr.length)
            attr.append(NSAttributedString(string: String(chars[i])))
            if let b = breathAt[i + 1] {
                attr.append(NSAttributedString(string: b == .long ? "\n"
                                                     : (b == .medium ? "  " : " ")))
            }
        }
        map.append(attr.length)
        return (map, attr.length)
    }

    private let cases: [(String, String)] = [
        ("LF 纯中文", "第一段内容。\n第二段内容。\n第三段内容。"),
        ("CRLF 三段", "第一段内容。\r\n第二段内容。\r\n第三段内容。"),
        ("emoji", "开场很棒👍效果不错🎉继续。"),
        ("组合字符", "café 测试 naïve 内容。"),
        ("混排", "Hello 2024 世界🌏，注意关键点。\r\n第二行。"),
        ("纯标点", "。。。，，，"),
        ("空", ""),
        ("单字", "中"),
    ]

    func testMapIsMonotonicAndBounded() {
        for (name, src) in cases {
            let (map, total) = buildMap(src)
            let chars = Array(src)
            XCTAssertEqual(map.count, chars.count + 1,
                           "[\(name)] 表长应为字符数+1")
            for i in 1..<max(1, map.count) where map.count > 1 {
                XCTAssertGreaterThanOrEqual(map[i], map[i - 1],
                    "[\(name)] 表必须单调不减 @\(i)")
            }
            for v in map {
                XCTAssertTrue(v >= 0 && v <= total,
                    "[\(name)] 偏移 \(v) 超出显示串长度 \(total)")
            }
            XCTAssertEqual(map.last, total, "[\(name)] 末位应等于显示串总长")
        }
    }

    /// 关键回归：CRLF 不该让映射漂移。
    /// 旧实现在这里会因为 Character/UTF-16 计数不一致而错位。
    func testCRLFDoesNotDriftMapping() {
        let crlf = "第一段内容。\r\n第二段内容。\r\n第三段内容。"
        let (map, total) = buildMap(crlf)
        let chars = Array(crlf)
        // 逐字符验证：表里的偏移必须真的指向该字符在显示串里的位置
        XCTAssertEqual(map.count, chars.count + 1)
        XCTAssertEqual(map.last, total)
        // "\r\n" 是 1 个 Character 但 2 个 UTF-16 —— 表必须体现这个跳变
        if let crIdx = chars.firstIndex(where: { $0 == "\r\n" }) {
            let jump = map[crIdx + 1] - map[crIdx]
            XCTAssertGreaterThanOrEqual(jump, 2,
                "\\r\\n 应至少占 2 个 UTF-16 单元，实际跳 \(jump)")
        }
    }

    func testEmojiDoesNotDriftMapping() {
        let src = "开场很棒👍效果不错🎉继续。"
        let (map, total) = buildMap(src)
        let chars = Array(src)
        XCTAssertEqual(map.count, chars.count + 1)
        XCTAssertEqual(map.last, total)
        if let e = chars.firstIndex(of: "👍") {
            let jump = map[e + 1] - map[e]
            XCTAssertGreaterThanOrEqual(jump, 2,
                "emoji 应占 2 个 UTF-16 单元，实际跳 \(jump)")
        }
    }

    /// 双向换算自洽：char -> visual -> char 应回到原处。
    func testRoundTripIsStable() {
        for (name, src) in cases where !src.isEmpty {
            let (map, _) = buildMap(src)
            // 二分反查，和控制器 charOffset(forVisual:) 同一算法
            func back(_ visual: Int) -> Int {
                var lo = 0, hi = map.count - 1
                while lo < hi {
                    let mid = (lo + hi + 1) / 2
                    if map[mid] <= visual { lo = mid } else { hi = mid - 1 }
                }
                return lo
            }
            for c in 0..<(map.count - 1) {
                XCTAssertEqual(back(map[c]), c,
                    "[\(name)] char \(c) -> visual \(map[c]) -> char \(back(map[c]))")
            }
        }
    }

    /// 越界输入必须被钳制，不能崩。
    func testOutOfRangeClamped() {
        let (map, total) = buildMap("测试内容。")
        func lookup(_ char: Int) -> Int {
            guard !map.isEmpty else { return 0 }
            return min(map[max(0, min(char, map.count - 1))], total)
        }
        for c in [-999, -1, 0, 1, map.count - 1, map.count, 99_999] {
            let v = lookup(c)
            XCTAssertTrue(v >= 0 && v <= total, "lookup(\(c)) = \(v) 越界")
        }
    }
}
