import XCTest
@testable import Prompter

/// Dreamcore 梦核规范守卫。
///
/// 之前这组测试守的是 Apple 原生风格（系统语义色、圆角 10）。
/// 用户改了方向：粉紫甜梦配色、圆角 32、磨砂玻璃、柔和外发光。
/// 所以断言整体重写 —— 守新规范，而不是留着旧断言当噪音。
final class DesignTests: XCTestCase {

    private func rgb(_ c: UIColor) -> (CGFloat, CGFloat, CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }

    /// 梦核基色必须是指定的粉紫，不能被改回系统语义色 ——
    /// 语义色会跟随深色模式反转，那会毁掉整个梦境氛围。
    func testDreamcorePaletteIsFixed() {
        XCTAssertEqual(DS.pinkSoft.hexString, "FFD9E8", "淡粉背景起点")
        XCTAssertEqual(DS.lavender.hexString, "D4C5F9", "薰衣草紫背景终点")
        XCTAssertEqual(DS.pinkBright.hexString, "FFB6D9", "主按钮渐变起点")
        XCTAssertEqual(DS.violet.hexString, "C9B6FF", "主按钮渐变终点")
    }

    /// 背景色不能是系统语义色。
    func testBackgroundIsNotSemanticColor() {
        XCTAssertNotEqual(DS.bg, UIColor.systemBackground,
            "梦核是浅色固定风格，用语义色会在深色模式下反转")
        let light = DS.bg.resolvedColor(with: .init(userInterfaceStyle: .light))
        let dark = DS.bg.resolvedColor(with: .init(userInterfaceStyle: .dark))
        XCTAssertEqual(light, dark, "背景不该随深浅模式变")
    }

    /// 卡片是半透明磨砂玻璃：白色 + 中等不透明度。
    func testCardsAreTranslucentGlass() {
        var a: CGFloat = 0
        DS.panel.getWhite(nil, alpha: &a)
        XCTAssertTrue(a > 0.4 && a < 0.9,
            "卡片白膜应半透明（实测 \(a)），全透明看不清、全不透明就没有玻璃感")
        var a2: CGFloat = 0
        DS.panel2.getWhite(nil, alpha: &a2)
        XCTAssertLessThan(a2, a, "卡片内控件应比卡片本身更透，形成层次")
    }

    /// 圆角要圆润饱满 —— 梦核的关键特征之一。
    func testCornersAreGenerouslyRounded() {
        XCTAssertEqual(DS.radius, 32, "卡片圆角 32")
        XCTAssertEqual(DS.radiusSm, 20, "控件圆角 20")
        XCTAssertGreaterThan(DS.radius, 24, "圆角太小会显得生硬，失去梦核气质")
    }

    /// 文字在浅粉紫底上必须够深 —— 梦核要柔和，但可读性是底线。
    func testTextContrastOnPastelBackground() {
        func luma(_ c: UIColor) -> CGFloat {
            let (r, g, b) = rgb(c)
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        let bgL = luma(DS.pinkSoft)
        XCTAssertLessThan(luma(DS.ink), bgL - 0.35,
            "标题与背景亮度差不足，读不清（ink \(luma(DS.ink)) vs bg \(bgL)）")
        XCTAssertLessThan(luma(DS.ink2), bgL - 0.22, "正文对比度不足")
        // 三级文字要有层次
        XCTAssertLessThan(luma(DS.ink), luma(DS.ink2))
        XCTAssertLessThan(luma(DS.ink2), luma(DS.ink3))
    }

    /// 文字应偏紫而非纯灰 —— 纯黑灰会破坏甜梦氛围。
    func testTextIsPurpleTintedNotNeutralGray() {
        let (r, g, b) = rgb(DS.ink)
        XCTAssertGreaterThan(b, g + 0.04, "标题色应偏紫（B > G）")
        XCTAssertGreaterThan(r, g, "标题色应带一点粉（R > G）")
    }

    /// 字体必须是圆润无衬线（SF Rounded）。
    func testFontUsesRoundedDesign() {
        let f = DS.font(.body, weight: .semibold)
        let name = f.fontName.lowercased()
        XCTAssertTrue(name.contains("rounded") || name.contains("sfui"),
            "应使用圆润字体设计，实际 \(f.fontName)")
    }

    /// Dynamic Type 仍要生效 —— 换风格不能牺牲无障碍。
    func testFontsStillScaleWithContentSize() {
        let normal = DS.font(.body).pointSize
        let big = UIFont.preferredFont(forTextStyle: .body,
            compatibleWith: .init(preferredContentSizeCategory: .accessibilityLarge))
        XCTAssertGreaterThan(big.pointSize, normal,
            "放大系统字号后字体应变大（\(normal) -> \(big.pointSize)）")
    }

    /// 提词文字三档在深色取景画面上必须区分得开。
    func testPrompterHighlightTiersStayDistinct() {
        let read = DS.textRead, now = DS.textNow, ahead = DS.textAhead
        XCTAssertNotEqual(read, ahead, "已读与未读必须区分")
        XCTAssertNotEqual(now, ahead, "光标与未读必须区分")
        // 已读应是暖粉（R 最高），呼应梦核配色
        let (rr, rg, rb) = rgb(read)
        XCTAssertGreaterThan(rr, rg, "已读应偏粉（R > G）")
        XCTAssertGreaterThan(rr, rb * 0.9, "已读应是暖色")
        // 未读要够淡，退到背景里
        var aheadA: CGFloat = 0
        ahead.getWhite(nil, alpha: &aheadA)
        XCTAssertLessThan(aheadA, 0.6, "未读应半透明，不与已读抢注意力")
    }

    /// 外发光工具必须真的设置阴影 —— 梦核靠它替代硬描边。
    func testDreamGlowAppliesShadow() {
        let l = CALayer()
        DS.applyDreamGlow(l)
        XCTAssertNotNil(l.shadowColor)
        XCTAssertGreaterThan(l.shadowOpacity, 0.2, "发光要看得见")
        XCTAssertGreaterThan(l.shadowRadius, 10, "发光要柔和扩散")
        XCTAssertFalse(l.masksToBounds, "masksToBounds 会把发光裁掉")
    }
}

private extension UIColor {
    /// 取十六进制串，便于断言固定色值。
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X",
                      Int((r * 255).rounded()), Int((g * 255).rounded()),
                      Int((b * 255).rounded()))
    }
}
