import UIKit

/// 梦核背景：淡粉到薰衣草紫的渐变天空，漂浮棉花糖软云，
/// 散布模糊光斑与星星点点，覆盖轻微胶片颗粒和柔焦光晕。
///
/// 全部代码绘制，不用图片资源 —— 任何屏幕尺寸都不会拉伸失真，
/// 而且云和光斑的位置能按屏宽自适应。
final class DreamBackground: UIView {

    private let sky = CAGradientLayer()
    private let grain = CALayer()
    private var clouds: [CloudLayer] = []
    private var orbs: [CALayer] = []
    private var stars: [CALayer] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        buildSky()
        buildOrbs()
        buildClouds()
        buildStars()
        buildGrain()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - 渐变天空

    private func buildSky() {
        // 淡粉 → 薰衣草紫。中间插一档更亮的过渡，避免两色直连显脏。
        sky.colors = [
            DS.pinkSoft.cgColor,
            UIColor(hex: 0xF3D6F0).cgColor,
            DS.lavender.cgColor,
        ]
        sky.locations = [0, 0.48, 1]
        sky.startPoint = CGPoint(x: 0.15, y: 0)
        sky.endPoint = CGPoint(x: 0.85, y: 1)
        layer.addSublayer(sky)
    }

    // MARK: - 模糊光斑

    /// 散布的圆形光斑。梦核的"柔焦"感主要来自这些 —— 大面积低透明度，
    /// 边缘完全羽化，像镜头前有雾。
    private func buildOrbs() {
        let specs: [(CGFloat, CGFloat, CGFloat, UIColor, Float)] = [
            (0.18, 0.12, 150, UIColor.white, 0.55),
            (0.86, 0.22, 120, DS.pinkBright, 0.40),
            (0.10, 0.58, 180, DS.violet, 0.32),
            (0.78, 0.72, 140, UIColor.white, 0.44),
            (0.46, 0.90, 160, DS.pinkSoft, 0.38),
        ]
        for (fx, fy, r, color, op) in specs {
            let l = CALayer()
            l.backgroundColor = color.cgColor
            l.cornerRadius = r
            l.opacity = op
            // 靠 shadow 做羽化：比 CIFilter 便宜得多，滚动时不掉帧
            l.shadowColor = color.cgColor
            l.shadowOpacity = 1
            l.shadowRadius = r * 0.9
            l.shadowOffset = .zero
            l.setValue(fx, forKey: "fx")
            l.setValue(fy, forKey: "fy")
            l.setValue(r, forKey: "r")
            layer.addSublayer(l)
            orbs.append(l)
        }
    }

    // MARK: - 棉花糖软云

    private func buildClouds() {
        // (相对 x, 相对 y, 宽, 透明度)
        let specs: [(CGFloat, CGFloat, CGFloat, Float)] = [
            (0.08, 0.16, 132, 0.85),
            (0.68, 0.09, 104, 0.70),
            (0.80, 0.44, 148, 0.62),
            (0.04, 0.74, 118, 0.66),
            (0.52, 0.62, 92,  0.52),
        ]
        for (fx, fy, w, op) in specs {
            let c = CloudLayer(width: w)
            c.opacity = op
            c.setValue(fx, forKey: "fx")
            c.setValue(fy, forKey: "fy")
            layer.addSublayer(c)
            clouds.append(c)
        }
    }

    // MARK: - 星星点点

    private func buildStars() {
        // 位置用固定表而非随机 —— 随机会让每次启动构图都变，不稳定
        let pts: [(CGFloat, CGFloat, CGFloat)] = [
            (0.24, 0.07, 7), (0.62, 0.18, 5), (0.90, 0.34, 8),
            (0.14, 0.42, 6), (0.44, 0.30, 4), (0.72, 0.55, 7),
            (0.30, 0.68, 5), (0.88, 0.80, 6), (0.20, 0.88, 4),
            (0.56, 0.82, 7),
        ]
        for (fx, fy, size) in pts {
            let l = CALayer()
            l.contents = Self.starImage(size: size * 3).cgImage
            l.opacity = 0.85
            l.setValue(fx, forKey: "fx")
            l.setValue(fy, forKey: "fy")
            l.setValue(size, forKey: "r")
            layer.addSublayer(l)
            stars.append(l)
        }
    }

    /// 四角星。梦核里的星星是柔的，不是尖锐的几何形。
    private static func starImage(size: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
            let c = ctx.cgContext
            let h = size / 2
            let p = UIBezierPath()
            // 四个方向的柔和尖角，用二次曲线让腰部收进去
            p.move(to: CGPoint(x: h, y: 0))
            p.addQuadCurve(to: CGPoint(x: size, y: h), controlPoint: CGPoint(x: h * 1.2, y: h * 0.8))
            p.addQuadCurve(to: CGPoint(x: h, y: size), controlPoint: CGPoint(x: h * 1.2, y: h * 1.2))
            p.addQuadCurve(to: CGPoint(x: 0, y: h), controlPoint: CGPoint(x: h * 0.8, y: h * 1.2))
            p.addQuadCurve(to: CGPoint(x: h, y: 0), controlPoint: CGPoint(x: h * 0.8, y: h * 0.8))
            p.close()
            c.setShadow(offset: .zero, blur: size * 0.5,
                        color: UIColor.white.withAlphaComponent(0.9).cgColor)
            UIColor.white.setFill()
            p.fill()
        }
    }

    // MARK: - 胶片颗粒

    /// 轻微颗粒。梦核/VHS 质感的关键 —— 没有它整个画面会太"数码"。
    /// 用一张小噪点图平铺，比实时滤镜省电得多。
    private func buildGrain() {
        grain.contents = Self.grainTile().cgImage
        grain.contentsGravity = .resize
        // 平铺：contentsRect 放大即重复
        grain.opacity = 0.055
        grain.compositingFilter = "overlayBlendMode"
        layer.addSublayer(grain)
    }

    private static func grainTile(side: CGFloat = 128) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            let c = ctx.cgContext
            // 固定种子，保证每次生成同一张，避免闪烁
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func rnd() -> CGFloat {
                seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
                return CGFloat(seed % 1000) / 1000
            }
            for _ in 0..<2600 {
                let g = rnd()
                c.setFillColor(UIColor(white: g, alpha: 0.5).cgColor)
                c.fill(CGRect(x: rnd() * side, y: rnd() * side, width: 1, height: 1))
            }
        }
    }

    // MARK: - 布局

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds
        sky.frame = b
        grain.frame = b

        func place(_ l: CALayer, size: CGSize) {
            let fx = (l.value(forKey: "fx") as? CGFloat) ?? 0.5
            let fy = (l.value(forKey: "fy") as? CGFloat) ?? 0.5
            l.frame = CGRect(x: b.width * fx - size.width / 2,
                             y: b.height * fy - size.height / 2,
                             width: size.width, height: size.height)
        }
        for l in orbs {
            let r = (l.value(forKey: "r") as? CGFloat) ?? 100
            place(l, size: CGSize(width: r * 2, height: r * 2))
        }
        for l in stars {
            let r = (l.value(forKey: "r") as? CGFloat) ?? 6
            place(l, size: CGSize(width: r * 3, height: r * 3))
        }
        for c in clouds { place(c, size: c.naturalSize) }
    }
}

/// 一朵棉花糖云。三到四个交叠圆＋底部平边，边缘柔化。
final class CloudLayer: CALayer {

    let naturalSize: CGSize

    init(width: CGFloat) {
        naturalSize = CGSize(width: width, height: width * 0.62)
        super.init()
        contents = CloudLayer.render(size: naturalSize).cgImage
        contentsGravity = .resizeAspect
    }
    override init(layer: Any) {
        naturalSize = (layer as? CloudLayer)?.naturalSize ?? .zero
        super.init(layer: layer)
    }
    required init?(coder: NSCoder) { fatalError() }

    private static func render(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            let w = size.width, h = size.height
            let p = UIBezierPath()
            // 底边
            p.move(to: CGPoint(x: w * 0.10, y: h * 0.82))
            p.addLine(to: CGPoint(x: w * 0.90, y: h * 0.82))
            // 右侧小圆
            p.addArc(withCenter: CGPoint(x: w * 0.78, y: h * 0.62),
                     radius: w * 0.21, startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: true)
            // 顶部大圆
            p.addArc(withCenter: CGPoint(x: w * 0.52, y: h * 0.42),
                     radius: w * 0.28, startAngle: .pi * 0.1, endAngle: .pi * 1.05, clockwise: true)
            // 左侧中圆
            p.addArc(withCenter: CGPoint(x: w * 0.24, y: h * 0.60),
                     radius: w * 0.22, startAngle: .pi * 0.9, endAngle: .pi * 1.9, clockwise: true)
            p.close()

            // 柔光让云"发亮"，这是梦核的关键
            c.setShadow(offset: CGSize(width: 0, height: h * 0.06), blur: w * 0.22,
                        color: UIColor.white.withAlphaComponent(0.85).cgColor)
            DS.cloudWhite.withAlphaComponent(0.94).setFill()
            p.fill()

            // 顶部高光，给出体积
            c.setShadow(offset: .zero, blur: 0, color: nil)
            UIColor.white.withAlphaComponent(0.6).setFill()
            c.fillEllipse(in: CGRect(x: w * 0.36, y: h * 0.22, width: w * 0.3, height: h * 0.2))
        }
    }
}
