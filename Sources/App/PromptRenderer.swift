import UIKit
import AVFoundation
import CoreVideo

/// 把提词文字画成视频帧。
///
/// 直接用 CoreGraphics 画进 CVPixelBuffer，不走 UIView -> UIImage -> JPEG -> buffer
/// 那条链（UIPiPView 用的是那条，作者自己也标注"relatively heavy"、想优化）。
/// 少两次编解码，10fps 下几乎不占 CPU。
enum PromptRenderer {

    private static var pool: CVPixelBufferPool?
    private static var poolSize: CGSize = .zero

    private static func makePool(_ size: CGSize) -> CVPixelBufferPool? {
        if let p = pool, poolSize == size { return p }
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        var p: CVPixelBufferPool?
        guard CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &p) == kCVReturnSuccess
        else { return nil }
        pool = p; poolSize = size
        return p
    }

    /// 渲染一帧。readChar 之前置灰，之后高亮，当前行居中。
    static func makeSampleBuffer(script: String, readChar: Int,
                                 pace: Pace?, size: CGSize) -> CMSampleBuffer? {
        guard let pool = makePool(size) else { return nil }
        var pb: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb) == kCVReturnSuccess,
              let buffer = pb else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let ctx = CGContext(
                data: base,
                width: Int(size.width), height: Int(size.height),
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }

        // CGContext 原点在左下、Y 轴向上；UIKit 原点在左上、Y 轴向下。
        // 不翻转就把内容画反 —— 这正是"浮窗是倒置的"的原因。
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)

        UIGraphicsPushContext(ctx)
        draw(script: script, readChar: readChar, pace: pace, size: size)
        UIGraphicsPopContext()

        return wrap(buffer)
    }

    private static func draw(script: String, readChar: Int, pace: Pace?, size: CGSize) {
        // PiP 窗口本身有圆角，画满黑底即可
        UIColor.black.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))

        let chars = Array(script)
        guard !chars.isEmpty else { return }

        let fontSize: CGFloat = 34
        let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        // 当前位置前后各留一段上下文。太少了接不上，太多了字就小。
        let back = 14, fwd = 46
        // readChar 先钳进合法范围。外部传进来的可能越界（对齐引擎给的 soft
        // 位置、手动 seek、或稿子被换掉），不钳会让下面的 Range 崩。
        let rc = min(max(0, readChar), chars.count)
        let lo = max(0, rc - back)
        let hi = min(chars.count, max(lo, rc + fwd))
        guard lo < hi else { return }
        let readIdx = rc - lo

        let visible = String(chars[lo..<hi])
        let attr = NSMutableAttributedString(string: visible)
        let full = NSRange(location: 0, length: attr.length)

        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byWordWrapping
        para.lineSpacing = 5
        attr.addAttributes([.font: font, .paragraphStyle: para], range: full)

        // 已读置灰，未读亮白，当前两字最亮 —— 和 Web 版一致的三档。
        //
        // readIdx 是 Character 下标，NSRange 要的是 UTF-16 偏移。中文下两者
        // 相等，但 emoji 是代理对（1 个 Character = 2 个 UTF-16 单元），
        // 直接混用会让灰白分界落进 emoji 中间，切出半个代理项渲染成方块，
        // 而且每遇一个 emoji 就多偏 1 位。所以必须显式换算。
        let hi16: Int = {
            guard readIdx > 0 else { return 0 }
            guard readIdx < visible.count else { return attr.length }
            let ci = visible.index(visible.startIndex, offsetBy: readIdx)
            guard let u = ci.samePosition(in: visible.utf16) else { return attr.length }
            return min(visible.utf16.distance(from: visible.utf16.startIndex, to: u),
                       attr.length)
        }()
        // 已读用亮粉（和主页面 DS.textRead 一致），不用灰——原来三档
        // 全是灰阶（0.42 / 0.82 / 1.0），在小窗里根本分不出读到哪了。
        attr.addAttribute(.foregroundColor, value: UIColor(red: 1, green: 0.71, blue: 0.85, alpha: 1),
                          range: NSRange(location: 0, length: hi16))
        if hi16 < attr.length {
            attr.addAttribute(.foregroundColor, value: UIColor(white: 0.62, alpha: 1),
                              range: NSRange(location: hi16, length: attr.length - hi16))
            // 当前高亮"两个字"同样按 Character 算：直接取 2 个 UTF-16 单元
            // 在 emoji 处只会亮半个字符。
            let nowLen: Int = {
                let start = visible.index(visible.startIndex,
                                          offsetBy: min(readIdx, visible.count))
                let end = visible.index(start,
                                        offsetBy: min(2, visible.distance(from: start,
                                                                          to: visible.endIndex)))
                guard let us = start.samePosition(in: visible.utf16),
                      let ue = end.samePosition(in: visible.utf16) else {
                    return min(2, attr.length - hi16)
                }
                return min(visible.utf16.distance(from: us, to: ue), attr.length - hi16)
            }()
            // 当前字：纯白 + 紫色底衬。只靠字色（白 vs 0.62 白）区分太弱，
            // 小窗里扫一眼看不出光标在哪。底衬和主页面 DS.textNowBg 一致。
            let nowRange = NSRange(location: hi16, length: nowLen)
            attr.addAttribute(.foregroundColor, value: UIColor.white, range: nowRange)
            attr.addAttribute(.backgroundColor,
                              value: UIColor(red: 0.79, green: 0.71, blue: 1, alpha: 0.55),
                              range: nowRange)
        }

        let inset: CGFloat = 14
        var textRect = CGRect(x: inset, y: inset,
                              width: size.width - inset * 2, height: size.height - inset * 2)

        // 让当前字所在行靠上停住，这样后文可见、眼睛不用往下找
        let bounding = attr.boundingRect(
            with: CGSize(width: textRect.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        if bounding.height > textRect.height {
            // 估算当前行位置，把它顶到可视区上方 1/4 处
            let ratio = attr.length > 0 ? CGFloat(readIdx) / CGFloat(attr.length) : 0
            let shift = max(0, bounding.height * ratio - textRect.height * 0.25)
            textRect.origin.y -= shift
        }
        attr.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)

        if let pace { drawPaceBadge(pace, size: size) }
    }

    /// 语速标记。慢的地方要放慢，快的地方带一带就过。
    private static func drawPaceBadge(_ pace: Pace, size: CGSize) {
        guard pace != .normal else { return }
        let text = pace == .slow ? "慢" : "快"
        let bg = pace == .slow ? UIColor(red: 0.96, green: 0.62, blue: 0.04, alpha: 0.95)
                              : UIColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 0.95)
        let fg = pace == .slow ? UIColor(white: 0.06, alpha: 1) : UIColor(white: 0.03, alpha: 1)
        let f = UIFont.systemFont(ofSize: 15, weight: .bold)
        let s = text as NSString
        let sz = s.size(withAttributes: [.font: f])
        let pad: CGFloat = 5
        let rect = CGRect(x: size.width - sz.width - pad * 2 - 10, y: 10,
                          width: sz.width + pad * 2, height: sz.height + pad)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 5)
        bg.setFill(); path.fill()
        s.draw(at: CGPoint(x: rect.minX + pad, y: rect.minY + pad / 2),
               withAttributes: [.font: f, .foregroundColor: fg])
    }

    /// CVPixelBuffer -> CMSampleBuffer。PiP 的 display layer 只吃后者。
    private static func wrap(_ pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        var fmt: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: nil, imageBuffer: pixelBuffer, formatDescriptionOut: &fmt
        ) == noErr, let fmt else { return nil }

        // 时间戳用当前时钟。PiP 认的是"活流"，给 invalid 会被判成静止。
        // duration 也必须给：invalid 等于"这帧不知道显示多久"，
        // 队列见底后系统就把 PiP 画成黑窗。按 10fps 给 100ms。
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 10),
            presentationTimeStamp: now,
            decodeTimeStamp: .invalid)
        var sb: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil, imageBuffer: pixelBuffer,
            formatDescription: fmt, sampleTiming: &timing, sampleBufferOut: &sb
        ) == noErr else { return nil }
        return sb
    }
}
