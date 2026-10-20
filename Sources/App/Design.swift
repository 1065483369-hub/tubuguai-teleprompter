import UIKit

/// 设计令牌。和 Web 端同一套配色与圆角，两端观感一致。
/// 设计令牌。用系统语义色而非自造色 —— 语义色会跟随用户的
/// 深浅模式、增强对比度、色调偏好等辅助功能设置，自造色不会。
/// Dreamcore 梦核美学设计令牌。
///
/// 粉紫甜梦配色，90 年代儿童绘本里的梦境感：淡粉到薰衣草紫的柔和渐变，
/// 棉花糖软云，模糊光斑，轻微胶片颗粒与柔焦光晕。
/// 关键词：soft dreamy, Y2K, nostalgic, pastel, VHS glow, liminal warmth。
///
/// 注意这是**浅色为主**的风格，和之前的深色语义色是两套体系 ——
/// 所以这里用固定色值而非 systemBackground，语义色会跟随深色模式反转，
/// 那会毁掉整个梦核氛围。
enum DS {
    // ── 梦核基色 ──
    static let pinkSoft   = UIColor(hex: 0xFFD9E8)   // 淡粉，背景起点
    static let lavender   = UIColor(hex: 0xD4C5F9)   // 薰衣草紫，背景终点
    static let pinkBright = UIColor(hex: 0xFFB6D9)   // 主按钮起点
    static let violet     = UIColor(hex: 0xC9B6FF)   // 主按钮终点
    static let cloudWhite = UIColor(hex: 0xFFFDFE)   // 云朵与卡片
    static let iconPink   = UIColor(hex: 0xE8B4D9)   // 图标粉
    static let iconViolet = UIColor(hex: 0xC9B6FF)   // 图标紫

    // ── 背景（渐变由 DreamBackgroundView 铺，这里给个兜底纯色）──
    static let bg     = UIColor(hex: 0xFBDCEC)
    /// 卡片：半透明磨砂玻璃。真实的模糊由 UIVisualEffectView 提供，
    /// 这个颜色只是叠在毛玻璃之上的白色薄膜（60% 透明度）。
    static let panel  = UIColor.white.withAlphaComponent(0.72)
    static let panel2 = UIColor.white.withAlphaComponent(0.58)
    static let line   = UIColor.white.withAlphaComponent(0.5)

    // ── 文字。浅粉白背景上要用深紫灰，纯黑太硬会破坏柔和感 ──
    // 浅粉紫底上必须够深才读得清。梦核要柔和，但可读性是底线。
    static let ink  = UIColor(hex: 0x463659)         // 标题：深紫
    static let ink2 = UIColor(hex: 0x6B5B85)         // 正文
    static let ink3 = UIColor(hex: 0x8F82A8)         // 提示

    // ── 强调色 ──
    static let brand    = UIColor(hex: 0xC9B6FF)     // 梦核紫
    static let brandInk = UIColor.white              // 主按钮文字：白色粗体
    static let warn     = UIColor(hex: 0xFFC48C)     // 柔橙
    static let info     = UIColor(hex: 0xA8D8F0)     // 柔蓝
    static let danger   = UIColor(hex: 0xFF9BB3)     // 柔粉红

    // ── 提词文字三档。提词页是深色底（取景画面），这里保持高对比 ──
    static let textRead  = UIColor(hex: 0xFFB6D9)    // 已读：亮粉，一路铺过去
    static let textNow   = UIColor.white             // 光标：纯白
    static let textNowBg = UIColor(hex: 0xC9B6FF, alpha: 0.34)
    static let textAhead = UIColor(hex: 0xE8DFF5, alpha: 0.42)  // 未读：淡紫白，退到背景

    // ── 圆角：梦核要圆润饱满，卡片 32、控件 20 ──
    static let radius: CGFloat = 32
    static let radiusSm: CGFloat = 20

    /// 柔和粉紫外发光。梦核的标志性质感，替代硬描边。
    static func applyDreamGlow(_ layer: CALayer, color: UIColor = violet,
                               opacity: Float = 0.45, radius: CGFloat = 18) {
        layer.shadowColor = color.cgColor
        layer.shadowOpacity = opacity
        layer.shadowRadius = radius
        layer.shadowOffset = CGSize(width: 0, height: 6)
        layer.masksToBounds = false
    }

    // ── 字体：圆润无衬线。SF Rounded 是系统里最接近梦核气质的 ──
    static func font(_ style: UIFont.TextStyle, weight: UIFont.Weight = .regular) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        if let d = base.fontDescriptor.withDesign(.rounded)?
            .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]]) {
            return UIFont(descriptor: d, size: base.pointSize)
        }
        let d = base.fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight]])
        return UIFont(descriptor: d, size: base.pointSize)
    }

    /// 标题的白色外发光。梦核里标题要"浮"在梦境上。
    static func applyTitleGlow(_ label: UILabel) {
        label.layer.shadowColor = UIColor.white.cgColor
        label.layer.shadowOpacity = 0.9
        label.layer.shadowRadius = 8
        label.layer.shadowOffset = .zero
        label.layer.masksToBounds = false
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

// MARK: - 组件

/// 卡片容器，带小标题。设置页的基本单元。
final class Card: UIView {
    private let title = UILabel()
    let stack = UIStackView()
    private var glassBlur: UIVisualEffectView?
    private var glassFilm: UIView?

    init(_ label: String, action: UIButton? = nil) {
        super.init(frame: .zero)
        // 磨砂玻璃：真实模糊靠 UIVisualEffectView，上面叠 60% 白膜。
        // 梦核不用硬描边，靠柔和粉紫外发光分层。
        backgroundColor = .clear
        layer.cornerRadius = DS.radius
        layer.borderWidth = 0
        clipsToBounds = false

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialLight))
        blur.layer.cornerRadius = DS.radius
        blur.clipsToBounds = true
        blur.isUserInteractionEnabled = false
        addSubview(blur)
        glassBlur = blur

        let film = UIView()
        film.backgroundColor = DS.panel
        film.layer.cornerRadius = DS.radius
        film.isUserInteractionEnabled = false
        addSubview(film)
        glassFilm = film

        DS.applyDreamGlow(layer, color: DS.violet, opacity: 0.38, radius: 22)

        // 字距拉开，小标题才有层次
        title.attributedText = NSAttributedString(
            string: label, attributes: [.kern: 1.2,
                .font: DS.font(.subheadline, weight: .bold),
                .foregroundColor: DS.ink2])

        stack.axis = .vertical
        stack.spacing = 10

        // 标题行：左边标题，右边可选的动作按钮（如"粘贴"）
        let head = UIStackView(arrangedSubviews: [title])
        head.alignment = .center
        if let action {
            let gap = UIView()
            gap.setContentHuggingPriority(.defaultLow, for: .horizontal)
            head.addArrangedSubview(gap)
            head.addArrangedSubview(action)
        }

        let outer = UIStackView(arrangedSubviews: [head, stack])
        outer.axis = .vertical
        outer.spacing = 10
        addSubview(outer)
        outer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            outer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            outer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        glassBlur?.frame = bounds
        glassFilm?.frame = bounds
        // 玻璃垫在内容之下
        if let b = glassBlur { sendSubviewToBack(b) }
        if let f = glassFilm, let b = glassBlur {
            insertSubview(f, aboveSubview: b)
        }
    }
}

/// 开关块。选中时描边和底色都变，一眼看得出状态。
final class Toggle: UIControl {
    private let box = UIView()
    private let check = UIImageView()
    private let label = UILabel()
    var onChange: ((Bool) -> Void)?

    override var isSelected: Bool {
        didSet { refresh() }
    }

    private let iconView = UIImageView()

    init(_ text: String, on: Bool, icon: UIImage? = nil) {
        super.init(frame: .zero)
        backgroundColor = DS.panel2
        layer.cornerRadius = DS.radiusSm
        layer.borderWidth = 1.5      // 选中时靠它变色，未选中透明

        if let icon {
            iconView.image = icon
            iconView.contentMode = .scaleAspectFit
            addSubview(iconView)
            iconView.translatesAutoresizingMaskIntoConstraints = false
        }

        box.layer.cornerRadius = 6
        box.layer.borderWidth = 1.5
        box.isUserInteractionEnabled = false

        check.image = UIImage(systemName: "checkmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold))
        check.tintColor = DS.brandInk
        check.contentMode = .center

        label.text = text
        label.font = DS.font(.subheadline, weight: .medium)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 2
        label.textColor = DS.ink

        addSubview(box); box.addSubview(check); addSubview(label)
        [box, check, label].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        var cons: [NSLayoutConstraint] = [
            check.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            check.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 52),
        ]
        if iconView.image != nil {
            // 梦核图标在左，勾选框缩到右侧当状态指示
            cons += [
                iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
                iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 28),
                iconView.heightAnchor.constraint(equalToConstant: 28),
                label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
                label.trailingAnchor.constraint(lessThanOrEqualTo: box.leadingAnchor, constant: -6),
                box.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
                box.centerYAnchor.constraint(equalTo: centerYAnchor),
                box.widthAnchor.constraint(equalToConstant: 18),
                box.heightAnchor.constraint(equalToConstant: 18),
            ]
        } else {
            cons += [
                box.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
                box.centerYAnchor.constraint(equalTo: centerYAnchor),
                box.widthAnchor.constraint(equalToConstant: 19),
                box.heightAnchor.constraint(equalToConstant: 19),
                label.leadingAnchor.constraint(equalTo: box.trailingAnchor, constant: 9),
                label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            ]
        }
        NSLayoutConstraint.activate(cons)
        isSelected = on
        addTarget(self, action: #selector(tap), for: .touchUpInside)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = text
        accessibilityIdentifier = "toggle." + text
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func tap() {
        isSelected.toggle()
        onChange?(isSelected)
        // 轻触反馈，开关类操作有回弹感更好确认
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func refresh() {
        box.backgroundColor = isSelected ? DS.brand : .clear
        box.layer.borderColor = (isSelected ? DS.brand : DS.ink3).cgColor
        check.isHidden = !isSelected
        // 未选中不画边框，选中才用绿边 —— 一眼看出哪些开着
        layer.borderColor = (isSelected ? DS.brand.withAlphaComponent(0.5)
                                        : UIColor.clear).cgColor
        backgroundColor = isSelected ? DS.brand.withAlphaComponent(0.10) : DS.panel2
    }
}

/// 滑块行：上方完整显示「名称 + 数值」，下方滑杆占满宽度。
/// 旧版把标题固定为 52pt，「提词位置」在圆体和动态字号下会被裁掉。
final class SliderRow: UIView {
    private let key = UILabel()
    private let value = UILabel()
    let slider = UISlider()
    private let format: (Float) -> String
    var onChange: ((Float) -> Void)?

    init(_ name: String, min: Float, max: Float, value v: Float,
         format: @escaping (Float) -> String) {
        self.format = format
        super.init(frame: .zero)
        key.text = name
        key.font = DS.font(.subheadline, weight: .medium)
        key.adjustsFontForContentSizeCategory = true
        key.textColor = DS.ink2

        value.font = DS.font(.footnote, weight: .semibold)
        value.adjustsFontForContentSizeCategory = true
        value.textColor = DS.ink
        value.textAlignment = .right

        slider.minimumValue = min
        slider.maximumValue = max
        slider.value = v
        slider.minimumTrackTintColor = DS.brand
        slider.maximumTrackTintColor = DS.line
        slider.addTarget(self, action: #selector(changed), for: .valueChanged)

        let labels = UIStackView(arrangedSubviews: [key, UIView(), value])
        labels.spacing = 8
        labels.alignment = .firstBaseline
        let row = UIStackView(arrangedSubviews: [labels, slider])
        row.axis = .vertical
        row.spacing = 3
        addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            value.widthAnchor.constraint(greaterThanOrEqualToConstant: 56),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
        ])
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func changed() { refresh(); onChange?(slider.value) }
    private func refresh() { value.text = format(slider.value) }
}

/// 信息胶囊，用于时长/气口数等预估。
final class Pill: UIView {
    enum Tone { case plain, green, orange, blue }

    init(_ text: String, tone: Tone = .plain) {
        super.init(frame: .zero)
        let (bg, fg, border): (UIColor, UIColor, UIColor) = {
            switch tone {
            case .plain:  return (DS.panel2, DS.ink2, DS.line)
            case .green:  return (DS.brand.withAlphaComponent(0.09), UIColor(hex: 0x86EFAC),
                                  DS.brand.withAlphaComponent(0.3))
            case .orange: return (DS.warn.withAlphaComponent(0.09), UIColor(hex: 0xFBBF24),
                                  DS.warn.withAlphaComponent(0.3))
            case .blue:   return (DS.info.withAlphaComponent(0.09), UIColor(hex: 0x7DD3FC),
                                  DS.info.withAlphaComponent(0.3))
            }
        }()
        backgroundColor = bg
        layer.cornerRadius = 13
        layer.borderWidth = 1
        layer.borderColor = border.cgColor

        let l = UILabel()
        l.text = text
        l.font = DS.font(.footnote, weight: .medium)
        l.adjustsFontForContentSizeCategory = true
        l.textColor = fg
        l.accessibilityIdentifier = "pill"
        addSubview(l)
        l.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            l.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            l.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            l.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            l.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// 底部主按钮。
final class PrimaryButton: UIButton {
    private let grad = CAGradientLayer()

    init(_ title: String) {
        super.init(frame: .zero)
        setTitle(title, for: .normal)
        titleLabel?.font = DS.font(.headline, weight: .bold)
        titleLabel?.adjustsFontForContentSizeCategory = true
        setTitleColor(DS.brandInk, for: .normal)

        // 粉紫渐变胶囊。梦核的主按钮要"甜"，不是纯色块。
        grad.colors = [DS.pinkBright.cgColor, DS.violet.cgColor]
        grad.startPoint = CGPoint(x: 0, y: 0.5)
        grad.endPoint = CGPoint(x: 1, y: 0.5)
        layer.insertSublayer(grad, at: 0)

        // 边缘淡粉发光
        DS.applyDreamGlow(layer, color: DS.pinkBright, opacity: 0.55, radius: 16)
        heightAnchor.constraint(equalToConstant: 56).isActive = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 胶囊形：圆角取高度一半
        let r = bounds.height / 2
        grad.frame = bounds
        grad.cornerRadius = r
        layer.cornerRadius = r
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.1) {
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.985, y: 0.985) : .identity
                self.alpha = self.isHighlighted ? 0.9 : 1
            }
        }
    }
}

/// HUD 上的胶囊按钮，毛玻璃底。
final class HUDButton: UIButton {
    enum Style { case normal, active, danger }
    private var style: Style = .normal
    private let blur = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemUltraThinMaterialDark))

    init(_ title: String) {
        super.init(frame: .zero)
        setTitle(title, for: .normal)
        titleLabel?.font = DS.font(.subheadline, weight: .semibold)
        titleLabel?.adjustsFontForContentSizeCategory = true
        titleLabel?.adjustsFontSizeToFitWidth = true
        titleLabel?.minimumScaleFactor = 0.85
        layer.cornerRadius = 16      // 比设置页克制，但仍圆润
        layer.borderWidth = 1      // Apple 的浮层描边是 hairline
        clipsToBounds = true

        // 毛玻璃垫在最底层。半透明纯色在取景画面上会显脏，
        // UIBlurEffect 真实折射底下内容，是 iOS 浮层的标准做法。
        blur.isUserInteractionEnabled = false
        insertSubview(blur, at: 0)
        apply(.normal)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        blur.frame = bounds
        // 录制工具栏的六个小按钮必须“图标在上、名称在下”。
        // 横排图标加文字会在窄屏上互相挤压，用户反而看不清动作名称。
        guard image(for: .normal) != nil else { return }
        let imageSide: CGFloat = 17
        imageView?.frame = CGRect(x: (bounds.width - imageSide) / 2, y: 6,
                                  width: imageSide, height: imageSide)
        titleLabel?.font = DS.font(.caption2, weight: .semibold)
        titleLabel?.textAlignment = .center
        titleLabel?.frame = CGRect(x: 2, y: 27, width: bounds.width - 4, height: 16)
    }
    required init?(coder: NSCoder) { fatalError() }

    func apply(_ s: Style) {
        style = s
        switch s {
        case .normal:
            backgroundColor = .clear          // 让毛玻璃透出来
            blur.isHidden = false
            // 提词页是深色取景底，按钮文字用白色才读得清
            setTitleColor(.white, for: .normal)
            layer.borderColor = UIColor.white.withAlphaComponent(0.22).cgColor
        case .active:
            blur.isHidden = true
            backgroundColor = DS.violet
            setTitleColor(.white, for: .normal)
            layer.borderColor = UIColor.clear.cgColor
        case .danger:
            blur.isHidden = true
            backgroundColor = DS.danger
            setTitleColor(.white, for: .normal)
            layer.borderColor = UIColor.clear.cgColor
        }
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.09) {
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.94, y: 0.94) : .identity
            }
        }
    }
}

/// 录制页里的即时文字设置。它只是一层轻薄半浮窗，正文预览始终留在背后。
final class RecordingSettingsSheet: UIView {
    var onChange: ((Float, Float, Float) -> Void)?
    var onDismiss: (() -> Void)?

    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    private let size: UISlider
    private let opacity: UISlider
    private let spacing: UISlider

    init(config: SetupViewController.Config) {
        size = Self.slider(min: 18, max: 64, value: config.fontSize)
        opacity = Self.slider(min: 35, max: 100, value: config.textOpacity)
        spacing = Self.slider(min: 100, max: 210, value: config.lineSpacing)
        super.init(frame: .zero)

        layer.cornerRadius = 26
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        clipsToBounds = true
        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: 24)
        addSubview(blur)
        blur.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: topAnchor), blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            blur.leadingAnchor.constraint(equalTo: leadingAnchor), blur.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        let grabber = UIView()
        grabber.backgroundColor = UIColor.white.withAlphaComponent(0.35)
        grabber.layer.cornerRadius = 2.5
        grabber.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = "文字显示"
        title.font = DS.font(.headline, weight: .bold)
        title.textColor = .white

        let done = UIButton(type: .system)
        done.setTitle("完成", for: .normal)
        done.titleLabel?.font = DS.font(.body, weight: .bold)
        done.setTitleColor(DS.pinkBright, for: .normal)
        done.addTarget(self, action: #selector(close), for: .touchUpInside)

        let heading = UIStackView(arrangedSubviews: [title, UIView(), done])
        heading.alignment = .center

        let rows = [
            row("字号", slider: size, value: { "\(Int($0))" }),
            row("文字透明度", slider: opacity, value: { "\(Int($0))%" }),
            row("行距", slider: spacing, value: { "\(Int($0))%" }),
        ]
        let content = UIStackView(arrangedSubviews: [heading] + rows)
        content.axis = .vertical
        content.spacing = 18
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grabber); addSubview(content)
        NSLayoutConstraint.activate([
            grabber.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            grabber.centerXAnchor.constraint(equalTo: centerXAnchor),
            grabber.widthAnchor.constraint(equalToConstant: 42), grabber.heightAnchor.constraint(equalToConstant: 5),
            content.topAnchor.constraint(equalTo: grabber.bottomAnchor, constant: 18),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
        ])
        [size, opacity, spacing].forEach { $0.addTarget(self, action: #selector(changed), for: .valueChanged) }
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        UIView.animate(withDuration: 0.22, delay: 0, options: .curveEaseOut) {
            self.alpha = 1
            self.transform = .identity
        }
    }

    @objc private func changed() { onChange?(size.value, opacity.value, spacing.value) }

    @objc private func close() {
        UIView.animate(withDuration: 0.18, animations: {
            self.alpha = 0
            self.transform = CGAffineTransform(translationX: 0, y: 24)
        }) { _ in
            self.removeFromSuperview()
            self.onDismiss?()
        }
    }

    private static func slider(min: Float, max: Float, value: Float) -> UISlider {
        let slider = UISlider()
        slider.minimumValue = min
        slider.maximumValue = max
        slider.value = value
        slider.minimumTrackTintColor = DS.pinkBright
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.22)
        return slider
    }

    private func row(_ name: String, slider: UISlider, value: @escaping (Float) -> String) -> UIStackView {
        let key = UILabel()
        key.text = name
        key.font = DS.font(.subheadline, weight: .semibold)
        key.textColor = UIColor.white.withAlphaComponent(0.9)
        let amount = UILabel()
        amount.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        amount.textColor = UIColor.white.withAlphaComponent(0.72)
        amount.textAlignment = .right
        amount.text = value(slider.value)
        slider.addAction(UIAction { _ in amount.text = value(slider.value) }, for: .valueChanged)
        let labels = UIStackView(arrangedSubviews: [key, UIView(), amount])
        let row = UIStackView(arrangedSubviews: [labels, slider])
        row.axis = .vertical
        row.spacing = 6
        return row
    }
}

/// 状态徽章，右上角。
final class Badge: UIView {
    private let label = UILabel()

    init() {
        super.init(frame: .zero)
        layer.cornerRadius = 11
        layer.borderWidth = 1
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        blur.layer.cornerRadius = 11
        blur.clipsToBounds = true
        addSubview(blur)
        label.font = DS.font(.caption1, weight: .medium)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        addSubview(label)
        blur.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
        ])
        set("待机", live: false)
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(_ text: String, live: Bool) {
        label.text = text
        accessibilityIdentifier = "badge"
        accessibilityLabel = text
        label.textColor = live ? UIColor(hex: 0xFFC2DE) : UIColor(white: 1, alpha: 0.75)
        layer.borderColor = (live ? DS.pinkBright.withAlphaComponent(0.5)
                                  : UIColor.white.withAlphaComponent(0.18)).cgColor
    }
}
