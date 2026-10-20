import UIKit

/// 梦核风格图标集。圆润扁平造型，淡粉紫配色，柔和外发光。
/// 全部代码绘制 —— 任何尺寸都锐利，且能跟着配色统一调整。
enum DreamIcon {

    private static let pink = UIColor(hex: 0xE8B4D9)
    private static let violet = UIColor(hex: 0xC9B6FF)
    private static let deepV = UIColor(hex: 0xA894E8)
    private static let white = UIColor.white

    /// 通用绘制外壳：透明底 + 柔和外发光。
    private static func make(_ side: CGFloat = 44,
                             _ draw: (CGContext, CGFloat) -> Void) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            let c = ctx.cgContext
            c.setShadow(offset: CGSize(width: 0, height: 1),
                        blur: side * 0.14,
                        color: violet.withAlphaComponent(0.55).cgColor)
            draw(c, side)
        }
    }

    /// 渐变填充路径：白→淡紫，梦核的标准填充。
    private static func fillDream(_ c: CGContext, _ path: UIBezierPath,
                                  from: UIColor = white, to: UIColor = violet) {
        c.saveGState()
        path.addClip()
        let cs = CGColorSpaceCreateDeviceRGB()
        let g = CGGradient(colorsSpace: cs,
                           colors: [from.cgColor, to.cgColor] as CFArray,
                           locations: [0, 1])!
        let b = path.bounds
        c.drawLinearGradient(g, start: CGPoint(x: b.minX, y: b.minY),
                             end: CGPoint(x: b.maxX, y: b.maxY), options: [])
        c.restoreGState()
    }

    /// 四角柔星，多处复用。
    private static func star(_ c: CGContext, cx: CGFloat, cy: CGFloat, r: CGFloat,
                             color: UIColor = white) {
        let p = UIBezierPath()
        p.move(to: CGPoint(x: cx, y: cy - r))
        p.addQuadCurve(to: CGPoint(x: cx + r, y: cy), controlPoint: CGPoint(x: cx + r * 0.24, y: cy - r * 0.24))
        p.addQuadCurve(to: CGPoint(x: cx, y: cy + r), controlPoint: CGPoint(x: cx + r * 0.24, y: cy + r * 0.24))
        p.addQuadCurve(to: CGPoint(x: cx - r, y: cy), controlPoint: CGPoint(x: cx - r * 0.24, y: cy + r * 0.24))
        p.addQuadCurve(to: CGPoint(x: cx, y: cy - r), controlPoint: CGPoint(x: cx - r * 0.24, y: cy - r * 0.24))
        p.close()
        color.setFill(); p.fill()
    }

    // ── 稿子：一朵软云，中心嵌卷角小纸条 ──
    static let script = make { c, s in
        let cloud = UIBezierPath()
        cloud.move(to: CGPoint(x: s * 0.14, y: s * 0.68))
        cloud.addLine(to: CGPoint(x: s * 0.86, y: s * 0.68))
        cloud.addArc(withCenter: CGPoint(x: s * 0.74, y: s * 0.54), radius: s * 0.17,
                     startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: true)
        cloud.addArc(withCenter: CGPoint(x: s * 0.5, y: s * 0.40), radius: s * 0.23,
                     startAngle: .pi * 0.08, endAngle: .pi * 1.05, clockwise: true)
        cloud.addArc(withCenter: CGPoint(x: s * 0.26, y: s * 0.54), radius: s * 0.18,
                     startAngle: .pi * 0.92, endAngle: .pi * 1.92, clockwise: true)
        cloud.close()
        fillDream(c, cloud)
        // 卷角纸条
        let note = UIBezierPath()
        note.move(to: CGPoint(x: s * 0.38, y: s * 0.36))
        note.addLine(to: CGPoint(x: s * 0.62, y: s * 0.36))
        note.addLine(to: CGPoint(x: s * 0.62, y: s * 0.56))
        note.addQuadCurve(to: CGPoint(x: s * 0.52, y: s * 0.58),
                          controlPoint: CGPoint(x: s * 0.58, y: s * 0.60))
        note.addLine(to: CGPoint(x: s * 0.38, y: s * 0.58))
        note.close()
        white.setFill(); note.fill()
        deepV.withAlphaComponent(0.5).setStroke()
        for i in 0..<2 {
            let l = UIBezierPath()
            let y = s * (0.42 + CGFloat(i) * 0.07)
            l.move(to: CGPoint(x: s * 0.43, y: y)); l.addLine(to: CGPoint(x: s * 0.57, y: y))
            l.lineWidth = s * 0.028; l.lineCapStyle = .round; l.stroke()
        }
    }

    // ── 相机取景：圆润粉相机，镜头是发光星星 ──
    static let camera = make { c, s in
        let body = UIBezierPath(roundedRect:
            CGRect(x: s * 0.14, y: s * 0.28, width: s * 0.72, height: s * 0.46),
            cornerRadius: s * 0.16)
        fillDream(c, body, from: white, to: pink)
        // 顶部取景凸起
        let hump = UIBezierPath(roundedRect:
            CGRect(x: s * 0.36, y: s * 0.20, width: s * 0.24, height: s * 0.12),
            cornerRadius: s * 0.05)
        white.withAlphaComponent(0.9).setFill(); hump.fill()
        // 镜头圈
        let lens = UIBezierPath(ovalIn:
            CGRect(x: s * 0.36, y: s * 0.38, width: s * 0.28, height: s * 0.28))
        violet.withAlphaComponent(0.35).setFill(); lens.fill()
        star(c, cx: s * 0.5, cy: s * 0.52, r: s * 0.11)
    }

    // ── 前置摄像头：柔紫圆脸镜头，带光晕 ──
    static let front = make { c, s in
        let outer = UIBezierPath(ovalIn:
            CGRect(x: s * 0.18, y: s * 0.18, width: s * 0.64, height: s * 0.64))
        fillDream(c, outer, from: white, to: violet)
        let ring = UIBezierPath(ovalIn:
            CGRect(x: s * 0.30, y: s * 0.30, width: s * 0.40, height: s * 0.40))
        deepV.withAlphaComponent(0.28).setFill(); ring.fill()
        let core = UIBezierPath(ovalIn:
            CGRect(x: s * 0.40, y: s * 0.40, width: s * 0.20, height: s * 0.20))
        white.setFill(); core.fill()
        star(c, cx: s * 0.68, cy: s * 0.32, r: s * 0.07)
    }

    // ── 屏幕常亮：发光月牙，里面嵌小星 ──
    static let keepAwake = make { c, s in
        let moon = UIBezierPath()
        moon.addArc(withCenter: CGPoint(x: s * 0.5, y: s * 0.5), radius: s * 0.32,
                    startAngle: .pi * 0.35, endAngle: .pi * 1.65, clockwise: true)
        moon.addArc(withCenter: CGPoint(x: s * 0.66, y: s * 0.5), radius: s * 0.30,
                    startAngle: .pi * 1.5, endAngle: .pi * 0.5, clockwise: false)
        moon.close()
        fillDream(c, moon, from: white, to: violet)
        star(c, cx: s * 0.42, cy: s * 0.42, r: s * 0.075, color: white)
    }

    // ── 陪读兔：棉花糖捏的小白兔剪影 ──
    static let buddy = make { c, s in
        let p = UIBezierPath()
        // 两只耳朵
        p.append(UIBezierPath(ovalIn: CGRect(x: s * 0.32, y: s * 0.12,
                                             width: s * 0.13, height: s * 0.32)))
        p.append(UIBezierPath(ovalIn: CGRect(x: s * 0.55, y: s * 0.12,
                                             width: s * 0.13, height: s * 0.32)))
        // 头
        p.append(UIBezierPath(ovalIn: CGRect(x: s * 0.26, y: s * 0.40,
                                             width: s * 0.48, height: s * 0.42)))
        fillDream(c, p, from: white, to: pink)
        // 眼睛
        deepV.withAlphaComponent(0.7).setFill()
        c.fillEllipse(in: CGRect(x: s * 0.39, y: s * 0.55, width: s * 0.06, height: s * 0.07))
        c.fillEllipse(in: CGRect(x: s * 0.55, y: s * 0.55, width: s * 0.06, height: s * 0.07))
    }

    // ── 语音跟随：三道跳动声波，末端小星光 ──
    static let voice = make { c, s in
        let heights: [CGFloat] = [0.30, 0.46, 0.24]
        for (i, h) in heights.enumerated() {
            let x = s * (0.28 + CGFloat(i) * 0.18)
            let bar = UIBezierPath(roundedRect:
                CGRect(x: x, y: s * (0.5 - h / 2), width: s * 0.09, height: s * h),
                cornerRadius: s * 0.045)
            fillDream(c, bar, from: pink, to: violet)
        }
        star(c, cx: s * 0.76, cy: s * 0.28, r: s * 0.075)
    }

    // ── 匀速滚动：三条水平波浪，向右流动 ──
    static let manual = make { c, s in
        for i in 0..<3 {
            let y = s * (0.34 + CGFloat(i) * 0.16)
            let w = UIBezierPath()
            w.move(to: CGPoint(x: s * 0.18, y: y))
            w.addQuadCurve(to: CGPoint(x: s * 0.5, y: y),
                           controlPoint: CGPoint(x: s * 0.34, y: y - s * 0.07))
            w.addQuadCurve(to: CGPoint(x: s * 0.82, y: y),
                           controlPoint: CGPoint(x: s * 0.66, y: y + s * 0.07))
            let col = i == 1 ? violet : pink
            col.setStroke()
            w.lineWidth = s * 0.075; w.lineCapStyle = .round; w.stroke()
        }
    }

    // ── 定时读完：圆润粉闹钟，表盘是星星 ──
    static let timed = make { c, s in
        // 铃盖
        for cx in [CGFloat(0.32), CGFloat(0.68)] {
            let bell = UIBezierPath(ovalIn:
                CGRect(x: s * cx - s * 0.075, y: s * 0.14, width: s * 0.15, height: s * 0.13))
            fillDream(c, bell, from: white, to: pink)
        }
        let face = UIBezierPath(ovalIn:
            CGRect(x: s * 0.20, y: s * 0.24, width: s * 0.60, height: s * 0.60))
        fillDream(c, face, from: white, to: pink)
        let inner = UIBezierPath(ovalIn:
            CGRect(x: s * 0.29, y: s * 0.33, width: s * 0.42, height: s * 0.42))
        white.withAlphaComponent(0.85).setFill(); inner.fill()
        star(c, cx: s * 0.5, cy: s * 0.54, r: s * 0.13, color: violet)
    }

    // ── 状态灯：发光小星，柔粉 ──
    static let statusStar = make(28) { c, s in
        star(c, cx: s * 0.5, cy: s * 0.5, r: s * 0.34, color: UIColor(hex: 0xFFC2DE))
    }

    // ── 箭头 / 进入：圆润粉紫小箭头 ──
    static let chevron = make(28) { c, s in
        let p = UIBezierPath()
        p.move(to: CGPoint(x: s * 0.38, y: s * 0.26))
        p.addQuadCurve(to: CGPoint(x: s * 0.64, y: s * 0.5),
                       controlPoint: CGPoint(x: s * 0.60, y: s * 0.36))
        p.addQuadCurve(to: CGPoint(x: s * 0.38, y: s * 0.74),
                       controlPoint: CGPoint(x: s * 0.60, y: s * 0.64))
        violet.setStroke()
        p.lineWidth = s * 0.11
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        p.stroke()
    }
}
