import UIKit

/// 设置页。和 Web 端同一套视觉：卡片分组、开关块、滑块行、预估胶囊。
/// 原来是塞在主控制器里的临时 sheet，拆出来才好维护。
final class SetupViewController: UIViewController {

    struct Config {
        var script = ""
        var camOn = true
        var front = true
        var fontSize: Float = 30
        var lineSpacing: Float = 150
        var textOpacity: Float = 100
        var mirrorX = false
        var mirrorY = false
        var promptTop: Float = 40            // 提词区锚定线位置（屏高百分比）
        var scrollMode: ScrollMode = .voice  // 语音跟随 / 匀速 / 定时
        var manualSpeed: Float = 40          // 匀速：×10 = 字/分钟（40 → 400字/分）
        var countdown: Int = 3               // 开始前倒计时秒数，0 = 关
        var showFrameGuide = true            // 取景框：标出真正录到的范围
        var recordAfterCountdown = true      // 倒计时结束才开录，别把倒计时录进去
    }

    private(set) var config: Config
    /// 点「开始」回调，带回最新配置。
    var onStart: ((Config) -> Void)?

    private let preview = UILabel()
    private let modeHint = UILabel()
    private var speedRow = SliderRow("", min: 0, max: 1, value: 0) { _ in "" }
    private let mascot = UIImageView()
    private let dream = DreamBackground()
    private var glowView: UIView?
    private let estStack = UIStackView()
    private let statusLabel = UILabel()
    private let scroll = UIScrollView()

    init(config: Config) {
        self.config = config
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DS.bg
        // 梦核背景：渐变天空 + 软云 + 光斑 + 胶片颗粒
        view.addSubview(dream)
        buildHeader()
        // footer 必须先建：buildBody 的滚动区底部约束要引用 footer.topAnchor，
        // 若此时 footer 还没进视图层级，AutoLayout 会直接抛异常崩溃。
        buildFooter()
        buildBody()
        refreshPreview()
        refreshEstimate()
    }

    // MARK: - 头部

    private let header = UIView()

    private func buildHeader() {
        // 头图透明 —— 梦核背景本身就是视觉主体，不需要另一层渐变。
        // 兔子后面加一团柔光把它"托"起来。
        let glow = UIView()
        glow.backgroundColor = UIColor.white.withAlphaComponent(0.5)
        glow.layer.cornerRadius = 64
        glow.layer.masksToBounds = false
        glow.layer.shadowColor = UIColor.white.cgColor
        glow.layer.shadowOpacity = 0.9
        glow.layer.shadowRadius = 26
        glow.layer.shadowOffset = .zero
        header.addSubview(glow)
        glowView = glow

        mascot.image = UIImage(named: "HomeRabbit")
        mascot.contentMode = .scaleAspectFit
        header.addSubview(mascot)

        let title = UILabel()
        title.text = "兔不乖的提词器"
        title.font = DS.font(.title2, weight: .bold)
        title.adjustsFontForContentSizeCategory = true
        title.textColor = DS.ink
        DS.applyTitleGlow(title)      // 梦核里标题要"浮"在梦境上

        let sub = UILabel()
        sub.text = "念到哪，亮到哪。开浮窗还能切去系统相机。"
        sub.font = DS.font(.subheadline)
        sub.adjustsFontForContentSizeCategory = true
        sub.textColor = DS.ink2
        sub.numberOfLines = 0

        let col = UIStackView(arrangedSubviews: [title, sub])
        col.axis = .vertical
        col.spacing = 5
        col.alignment = .leading

        header.addSubview(col)
        header.clipsToBounds = true
        view.addSubview(header)
        [col, header, mascot].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            // 兔子放大为首页主视觉，和标题形成清晰的品牌锚点。
            mascot.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            mascot.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -12),
            mascot.widthAnchor.constraint(equalToConstant: 84),
            mascot.heightAnchor.constraint(equalToConstant: 96),

            col.leadingAnchor.constraint(equalTo: mascot.trailingAnchor, constant: 12),
            col.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
            col.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -24),
            col.topAnchor.constraint(greaterThanOrEqualTo:
                view.safeAreaLayoutGuide.topAnchor, constant: 10),
            // 给放大的兔子留足耳朵和星星的呼吸空间。
            header.bottomAnchor.constraint(equalTo:
                view.safeAreaLayoutGuide.topAnchor, constant: 146),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        dream.frame = view.bounds
        view.sendSubviewToBack(dream)
        // 柔光跟着兔子走，藏在它后面
        glowView?.frame = CGRect(x: mascot.frame.midX - 64,
                                 y: mascot.frame.midY - 64,
                                 width: 128, height: 128)
    }

    /// 头图上的兔子。和 App 图标同一套形体（连续路径而非椭圆拼接），
    /// 保证品牌一致 —— 用户在桌面看到的和进 App 看到的是同一只兔子。
    private static func mascotImage() -> UIImage {
        let size = CGSize(width: 128, height: 144)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            let fur = UIColor(hex: 0xF4EDE4)
            let furLight = UIColor(hex: 0xFFFCF8)
            let furDark = UIColor(hex: 0xDCD0C2)
            let inner = UIColor(hex: 0xF6BFCB)
            let ink = UIColor(hex: 0x2E2724)

            // 耳朵：贝塞尔画出真耳形，尖端收窄根部饱满
            func ear(x: CGFloat, tilt: CGFloat) {
                c.saveGState()
                c.translateBy(x: x, y: 46)
                c.rotate(by: tilt)
                let p = UIBezierPath()
                p.move(to: CGPoint(x: 0, y: 16))
                p.addCurve(to: CGPoint(x: -5, y: -34),
                           controlPoint1: CGPoint(x: -12, y: -2),
                           controlPoint2: CGPoint(x: -12, y: -24))
                p.addCurve(to: CGPoint(x: 7, y: -32),
                           controlPoint1: CGPoint(x: -1, y: -44),
                           controlPoint2: CGPoint(x: 4, y: -44))
                p.addCurve(to: CGPoint(x: 6, y: 17),
                           controlPoint1: CGPoint(x: 14, y: -20),
                           controlPoint2: CGPoint(x: 13, y: 2))
                p.close()
                fur.setFill(); p.fill()
                let ip = UIBezierPath(ovalIn: CGRect(x: -3.5, y: -28, width: 8, height: 38))
                inner.setFill(); ip.fill()
                c.restoreGState()
            }
            ear(x: 44, tilt: -0.16)
            ear(x: 84, tilt: 0.30)

            // 头：路径而非椭圆，脸颊饱满下颌收窄
            let head = UIBezierPath()
            head.move(to: CGPoint(x: 64, y: 42))
            head.addCurve(to: CGPoint(x: 106, y: 78),
                          controlPoint1: CGPoint(x: 92, y: 42),
                          controlPoint2: CGPoint(x: 106, y: 56))
            head.addCurve(to: CGPoint(x: 64, y: 116),
                          controlPoint1: CGPoint(x: 106, y: 100),
                          controlPoint2: CGPoint(x: 92, y: 116))
            head.addCurve(to: CGPoint(x: 22, y: 78),
                          controlPoint1: CGPoint(x: 36, y: 116),
                          controlPoint2: CGPoint(x: 22, y: 100))
            head.addCurve(to: CGPoint(x: 64, y: 42),
                          controlPoint1: CGPoint(x: 22, y: 56),
                          controlPoint2: CGPoint(x: 36, y: 42))
            fur.setFill(); head.fill()

            // 额头高光给体积
            furLight.withAlphaComponent(0.75).setFill()
            c.fillEllipse(in: CGRect(x: 38, y: 54, width: 40, height: 18))

            // 眼睛：一睁一眨
            ink.setFill()
            c.fillEllipse(in: CGRect(x: 44, y: 74, width: 8, height: 10))
            UIColor.white.withAlphaComponent(0.95).setFill()
            c.fillEllipse(in: CGRect(x: 47, y: 76, width: 3.5, height: 3.5))
            let wink = UIBezierPath()
            wink.move(to: CGPoint(x: 76, y: 80))
            wink.addQuadCurve(to: CGPoint(x: 88, y: 80), controlPoint: CGPoint(x: 82, y: 74))
            ink.setStroke(); wink.lineWidth = 3
            wink.lineCapStyle = .round; wink.stroke()

            // 鼻与人字嘴
            UIColor(hex: 0xE39AAB).setFill()
            let nose = UIBezierPath()
            nose.move(to: CGPoint(x: 59, y: 92))
            nose.addQuadCurve(to: CGPoint(x: 69, y: 92), controlPoint: CGPoint(x: 64, y: 88))
            nose.addQuadCurve(to: CGPoint(x: 59, y: 92), controlPoint: CGPoint(x: 64, y: 98))
            nose.close(); nose.fill()
            let mouth = UIBezierPath()
            mouth.move(to: CGPoint(x: 64, y: 98))
            mouth.addLine(to: CGPoint(x: 64, y: 104))
            mouth.move(to: CGPoint(x: 64, y: 104))
            mouth.addQuadCurve(to: CGPoint(x: 55, y: 108), controlPoint: CGPoint(x: 59, y: 108))
            mouth.move(to: CGPoint(x: 64, y: 104))
            mouth.addQuadCurve(to: CGPoint(x: 73, y: 108), controlPoint: CGPoint(x: 69, y: 108))
            ink.setStroke(); mouth.lineWidth = 2.4
            mouth.lineCapStyle = .round; mouth.stroke()

            // 腮红与胡须
            inner.withAlphaComponent(0.5).setFill()
            c.fillEllipse(in: CGRect(x: 26, y: 92, width: 14, height: 8))
            c.fillEllipse(in: CGRect(x: 88, y: 92, width: 14, height: 8))
            furDark.withAlphaComponent(0.7).setStroke()
            for dy in [0.0, 5.0] {
                let w = UIBezierPath()
                w.move(to: CGPoint(x: 24, y: 96 + dy)); w.addLine(to: CGPoint(x: 12, y: 95 + dy))
                w.move(to: CGPoint(x: 104, y: 96 + dy)); w.addLine(to: CGPoint(x: 116, y: 95 + dy))
                w.lineWidth = 1.6; w.lineCapStyle = .round; w.stroke()
            }
        }
    }

    // MARK: - 主体

    private func buildBody() {
        scroll.showsVerticalScrollIndicator = false
        scroll.keyboardDismissMode = .interactive
        view.addSubview(scroll)

        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 11
        scroll.addSubview(content)

        // ── 稿子入口 ──
        // 不在这里内嵌输入框：设置页是滚动表单，键盘一弹就和它抢高度，
        // 输入框会被挤到只剩 21pt。改成点开进独立编辑页（ScriptEditorViewController）。
        let scriptCard = Card("稿子")
        let entry = UIControl()
        entry.backgroundColor = DS.panel2
        entry.layer.cornerRadius = DS.radiusSm
        entry.layer.borderWidth = 1
        entry.layer.borderColor = DS.line.withAlphaComponent(0.6).cgColor
        entry.accessibilityIdentifier = "scriptEntry"
        entry.isAccessibilityElement = true
        entry.accessibilityTraits = .button
        entry.addTarget(self, action: #selector(openEditor), for: .touchUpInside)

        preview.font = DS.font(.body)
        preview.adjustsFontForContentSizeCategory = true
        preview.textColor = DS.ink
        preview.numberOfLines = 3
        let arrow = UIImageView(image: DreamIcon.chevron)
        arrow.contentMode = .scaleAspectFit

        entry.addSubview(preview); entry.addSubview(arrow)
        [preview, arrow].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: entry.topAnchor, constant: 14),
            preview.leadingAnchor.constraint(equalTo: entry.leadingAnchor, constant: 13),
            preview.trailingAnchor.constraint(equalTo: arrow.leadingAnchor, constant: -10),
            preview.bottomAnchor.constraint(equalTo: entry.bottomAnchor, constant: -14),
            arrow.trailingAnchor.constraint(equalTo: entry.trailingAnchor, constant: -13),
            arrow.centerYAnchor.constraint(equalTo: entry.centerYAnchor),
            arrow.widthAnchor.constraint(equalToConstant: 12),
            arrow.heightAnchor.constraint(equalToConstant: 16),
            entry.heightAnchor.constraint(greaterThanOrEqualToConstant: 62),
        ])
        scriptCard.stack.addArrangedSubview(entry)

        estStack.spacing = 7
        estStack.alignment = .leading
        estStack.accessibilityIdentifier = "estimate"
        scriptCard.stack.addArrangedSubview(estStack)
        content.addArrangedSubview(scriptCard)

        // 首页顺序按开读前的真实动作走：稿子 → 跟读设置 → 拍摄；
        // 显示样式留在跟读页，边看效果边调更合理。

        // ── 拍摄 ──
        let shootCard = Card("拍摄")
        let camT = Toggle("相机取景", on: config.camOn, icon: DreamIcon.camera)
        let frontT = Toggle("前置摄像头", on: config.front, icon: DreamIcon.front)
        camT.onChange = { [weak self] v in self?.config.camOn = v }
        frontT.onChange = { [weak self] v in self?.config.front = v }
        shootCard.stack.addArrangedSubview(grid([camT, frontT]))

        // ── 跟读设置 ──
        let scrollCard = Card("跟读设置")
        let modeSeg = UISegmentedControl(items: ScrollMode.allCases.map(\.rawValue))
        modeSeg.selectedSegmentIndex =
            ScrollMode.allCases.firstIndex(of: config.scrollMode) ?? 0
        modeSeg.selectedSegmentTintColor = DS.brand
        modeSeg.backgroundColor = DS.panel2
        modeSeg.accessibilityIdentifier = "scrollMode"
        modeSeg.setTitleTextAttributes([.foregroundColor: DS.ink2], for: .normal)
        modeSeg.setTitleTextAttributes([.foregroundColor: DS.brandInk,
            .font: DS.font(.subheadline, weight: .semibold)], for: .selected)
        modeSeg.addTarget(self, action: #selector(modeChanged(_:)), for: .valueChanged)
        scrollCard.stack.addArrangedSubview(modeSeg)

        modeHint.font = DS.font(.caption1)
        modeHint.adjustsFontForContentSizeCategory = true
        modeHint.textColor = DS.ink3
        modeHint.numberOfLines = 0
        modeHint.text = config.scrollMode.hint
        scrollCard.stack.addArrangedSubview(modeHint)

        // 匀速速度：只在匀速模式下有意义
        speedRow = SliderRow("速度", min: 15, max: 80, value: config.manualSpeed) {
            "\(Int($0 * 10))字/分" }
        speedRow.onChange = { [weak self] v in self?.config.manualSpeed = v }
        scrollCard.stack.addArrangedSubview(speedRow)

        let topRow = SliderRow("提词位置", min: 15, max: 65, value: config.promptTop) {
            "\(Int($0))%" }
        topRow.onChange = { [weak self] v in self?.config.promptTop = v }
        scrollCard.stack.addArrangedSubview(topRow)
        let topHint = UILabel()
        topHint.text = "让正在读的文字靠近镜头，减少眼神向下偏移"
        topHint.font = DS.font(.caption1)
        topHint.textColor = DS.ink3
        topHint.numberOfLines = 0
        scrollCard.stack.addArrangedSubview(topHint)

        let cdRow = SliderRow("倒计时", min: 0, max: 10, value: Float(config.countdown)) {
            $0 < 1 ? "关" : "\(Int($0))秒" }
        cdRow.onChange = { [weak self] v in self?.config.countdown = Int(v) }
        scrollCard.stack.addArrangedSubview(cdRow)
        refreshModeUI()

        // 字号、透明度、行距和镜像都在跟读页即时调整，首页只保留进稿前必要配置。
        content.addArrangedSubview(scrollCard)
        content.addArrangedSubview(shootCard)

        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor),
            // 内容用 contentLayoutGuide 定位，高度由内容自己决定。
            // 之前钉在 scroll.bottomAnchor 上等于强制"内容高 = 可视高"，
            // 键盘一来滚动区变矮就把整个栈压扁，输入框从 264pt 掉到 21pt。
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor,
                                             constant: 16),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor,
                                              constant: -16),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor,
                                            constant: -14),
            // 宽度跟随可视区（frameLayoutGuide），这样只纵向滚
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor,
                                           constant: -32),
        ])
    }


    @objc private func modeChanged(_ sender: UISegmentedControl) {
        let all = ScrollMode.allCases
        guard sender.selectedSegmentIndex < all.count else { return }
        config.scrollMode = all[sender.selectedSegmentIndex]
        refreshModeUI()
    }

    /// 速度滑块只在匀速模式下有意义，其他模式收起来减少干扰。
    private func refreshModeUI() {
        modeHint.text = config.scrollMode.hint
        let show = config.scrollMode == .manual
        UIView.animate(withDuration: 0.2) {
            self.speedRow.isHidden = !show
            self.speedRow.alpha = show ? 1 : 0
        }
    }

    /// 一个带左侧小标题的控件行。
    private func labeled(_ name: String, _ control: UIView) -> UIStackView {
        let l = UILabel()
        l.text = name
        l.font = DS.font(.subheadline, weight: .medium)
        l.adjustsFontForContentSizeCategory = true
        l.textColor = DS.ink2
        l.translatesAutoresizingMaskIntoConstraints = false
        l.widthAnchor.constraint(equalToConstant: 68).isActive = true
        let row = UIStackView(arrangedSubviews: [l, control])
        row.spacing = 10
        row.alignment = .center
        return row
    }

    /// 两列网格。开关成对排列比一列到底紧凑。
    private func grid(_ items: [UIView]) -> UIStackView {
        let col = UIStackView()
        col.axis = .vertical
        col.spacing = 8
        col.distribution = .fillEqually
        for pair in stride(from: 0, to: items.count, by: 2) {
            let row = UIStackView(arrangedSubviews: Array(items[pair..<min(pair + 2, items.count)]))
            row.spacing = 8
            row.distribution = .fillEqually
            col.addArrangedSubview(row)
        }
        return col
    }

    // MARK: - 底部

    private let footer = UIView()
    private var footerBottom: NSLayoutConstraint!

    private func buildFooter() {
        let sep = UIView()
        sep.backgroundColor = DS.line

        statusLabel.font = DS.font(.footnote)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = DS.ink3
        statusLabel.numberOfLines = 0        // 不限行：Dynamic Type 放大后两行装不下
        statusLabel.text = "输入稿子后点开始，会请求麦克风与摄像头权限。"

        let start = PrimaryButton("开始")
        start.accessibilityIdentifier = "startButton"
        start.addTarget(self, action: #selector(startTapped), for: .touchUpInside)

        let col = UIStackView(arrangedSubviews: [statusLabel, start])
        col.axis = .vertical
        col.spacing = 11

        footer.backgroundColor = DS.bg
        footer.addSubview(sep)
        footer.addSubview(col)
        view.addSubview(footer)
        [sep, col, footer].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        footerBottom = footer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        NSLayoutConstraint.activate([
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerBottom,
            sep.topAnchor.constraint(equalTo: footer.topAnchor),
            sep.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            sep.heightAnchor.constraint(equalToConstant: 1),
            col.topAnchor.constraint(equalTo: footer.topAnchor, constant: 12),
            col.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 16),
            col.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -16),
            col.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                                        constant: -12),
        ])
    }

    // MARK: - 预估

    /// 稿子变化时更新时长和气口数。规则计算很快，直接同步做。
    private func refreshEstimate() {
        estStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let text = config.script
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let lines = segment(text)
        let sec = estimateDuration(lines)
        let slow = lines.filter { $0.pace == .slow }.count
        let fast = lines.filter { $0.pace == .fast }.count
        estStack.addArrangedSubview(Pill("约 \(formatDuration(sec))", tone: .green))
        estStack.addArrangedSubview(Pill("\(lines.count) 个气口"))
        if slow > 0 { estStack.addArrangedSubview(Pill("慢 \(slow)", tone: .orange)) }
        if fast > 0 { estStack.addArrangedSubview(Pill("快 \(fast)", tone: .blue)) }
        estStack.addArrangedSubview(UIView())   // 撑开左对齐
    }

    func setStatus(_ text: String, isError: Bool = false) {
        statusLabel.text = text
        statusLabel.textColor = isError ? UIColor(hex: 0xFB7185) : DS.ink3
    }

    @objc private func startTapped() {
        guard !config.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            setStatus("先粘贴稿子。", isError: true)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        view.endEditing(true)
        onStart?(config)
    }

    /// 打开独立编辑页。设置页不内嵌输入框，避免和键盘抢高度。
    @objc private func openEditor() {
        let ed = ScriptEditorViewController(text: config.script)
        ed.modalPresentationStyle = .fullScreen
        ed.onDone = { [weak self, weak ed] text in
            guard let self else { return }
            self.config.script = text
            self.refreshPreview()
            self.refreshEstimate()
            ed?.dismiss(animated: true)
        }
        present(ed, animated: true)
    }

    /// 入口行显示稿子前几句，空则显示提示。
    private func refreshPreview() {
        let t = config.script.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            preview.text = "点这里粘贴或输入稿子"
            preview.textColor = DS.ink3
        } else {
            preview.text = t.replacingOccurrences(of: "\n", with: " ")
            preview.textColor = DS.ink
        }
    }
}
