import UIKit

// PrompterCore 的源码被 App target 直接编译（见 project.yml 的 sources），
// 不是独立模块，所以不 import——Align/Prep 也是这么用的。

/// 敏感词检测页。从稿子页点「查敏感词」进来。
///
/// 检测全在本机跑，稿子不出设备。词库与 Web 版同一套口径
/// （见 PrompterCore/Sensitive.swift）。
///
/// 改完的稿子通过 onApply 回传——不在这里直接写回 textView，
/// 免得两个页面各持一份文本互相覆盖。
final class SensitiveViewController: UIViewController {

    private let scroll = UIScrollView()
    private let content = UIStackView()
    private let summary = UIStackView()
    private let hitList = UIStackView()
    private let platRow = UIStackView()
    private let sceneHint = UILabel()
    private let sceneSeg = UISegmentedControl(
        items: ScanScene.allCases.map(\.label))
    private let wordField = UITextField()
    private let repField = UITextField()
    private let customList = UIStackView()
    private let bulkRow = UIStackView()

    private var text: String
    private var hits: [Hit] = []
    private var platforms: Set<Platform> = Set(Platform.allCases)
    private var custom: [CustomWord] = SensitivePrefs.loadCustom()

    /// 回传改好的稿子。可能被多次调用（逐条改一次回传一次）。
    var onApply: ((String) -> Void)?

    init(text: String) {
        self.text = text
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DS.bg
        sceneSeg.selectedSegmentIndex =
            ScanScene.allCases.firstIndex(of: SensitivePrefs.loadScene()) ?? 0
        build()
        rescan()
    }

    // MARK: - 布局

    private func build() {
        let cancel = UIButton(type: .system)
        cancel.setTitle("返回", for: .normal)
        cancel.titleLabel?.font = DS.font(.body)
        cancel.titleLabel?.adjustsFontForContentSizeCategory = true
        cancel.setTitleColor(DS.ink2, for: .normal)
        cancel.accessibilityIdentifier = "sensitiveBack"
        cancel.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let title = UILabel()
        title.text = "敏感词"
        title.font = DS.font(.body, weight: .semibold)
        title.adjustsFontForContentSizeCategory = true
        title.textColor = DS.ink

        let bar = UIView()
        [cancel, title].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview($0)
        }
        NSLayoutConstraint.activate([
            bar.heightAnchor.constraint(equalToConstant: 40),
            cancel.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            cancel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            title.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])

        content.axis = .vertical
        content.spacing = 12
        content.isLayoutMarginsRelativeArrangement = true
        content.directionalLayoutMargins = .init(top: 4, leading: 0, bottom: 24, trailing: 0)

        summary.axis = .horizontal
        summary.spacing = 7
        summary.alignment = .center

        bulkRow.axis = .horizontal
        bulkRow.spacing = 8
        bulkRow.distribution = .fillEqually
        bulkRow.heightAnchor.constraint(equalToConstant: 40).isActive = true

        hitList.axis = .vertical
        hitList.spacing = 8

        content.addArrangedSubview(summary)
        content.addArrangedSubview(bulkRow)
        // 命中列表紧跟摘要——那是用户进来要看的东西。
        // 检测范围、自定义词、词库说明都是配置，排在结果之后。
        content.addArrangedSubview(hitList)
        content.addArrangedSubview(platformCard())
        content.addArrangedSubview(customCard())
        content.addArrangedSubview(basisCard())

        scroll.alwaysBounceVertical = true
        scroll.keyboardDismissMode = .interactive
        scroll.addSubview(content)

        [bar, scroll].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        let g = view.safeAreaLayoutGuide
        // 内容高度必须由内容自己决定：钉在 scroll.bottomAnchor 上等于
        // 强制「内容高 = 可视高」，长列表滚不动。用 contentLayoutGuide。
        let cl = scroll.contentLayoutGuide
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: g.topAnchor, constant: 6),
            bar.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 16),
            bar.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -16),

            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: g.bottomAnchor),

            content.topAnchor.constraint(equalTo: cl.topAnchor),
            content.leadingAnchor.constraint(equalTo: cl.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: cl.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: cl.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
    }

    private func platformCard() -> UIView {
        let card = Card("检测范围")

        platRow.axis = .horizontal
        platRow.spacing = 6
        platRow.distribution = .fillEqually
        platRow.heightAnchor.constraint(equalToConstant: 36).isActive = true
        for p in Platform.allCases {
            let b = UIButton(type: .system)
            b.setTitle(p.label, for: .normal)
            b.titleLabel?.font = DS.font(.caption1, weight: .semibold)
            b.titleLabel?.adjustsFontForContentSizeCategory = true
            b.layer.cornerRadius = 12
            b.accessibilityIdentifier = "plat_\(p.rawValue)"
            b.tag = Platform.allCases.firstIndex(of: p) ?? 0
            b.addTarget(self, action: #selector(platTapped(_:)), for: .touchUpInside)
            platRow.addArrangedSubview(b)
        }
        card.stack.addArrangedSubview(platRow)

        // 检测档位。一个「严格模式」开关表达不了真实需求 ——
        // 「养胃」在科普稿里完全正常、在带货稿里违反《广告法》第十七条。
        // 同一个词两种结论，只能按稿子用途分档。
        let lbl = UILabel()
        lbl.text = "稿子类型"
        lbl.font = DS.font(.subheadline, weight: .semibold)
        lbl.adjustsFontForContentSizeCategory = true
        lbl.textColor = DS.ink

        sceneSeg.selectedSegmentTintColor = DS.brand
        sceneSeg.backgroundColor = DS.panel2
        sceneSeg.accessibilityIdentifier = "sceneSeg"
        sceneSeg.setTitleTextAttributes([.foregroundColor: DS.ink2], for: .normal)
        sceneSeg.setTitleTextAttributes([.foregroundColor: DS.brandInk,
            .font: DS.font(.subheadline, weight: .semibold)], for: .selected)
        sceneSeg.addTarget(self, action: #selector(sceneChanged), for: .valueChanged)

        sceneHint.font = DS.font(.caption2)
        sceneHint.adjustsFontForContentSizeCategory = true
        sceneHint.textColor = DS.ink3
        sceneHint.numberOfLines = 0

        let sceneCol = UIStackView(arrangedSubviews: [lbl, sceneSeg, sceneHint])
        sceneCol.axis = .vertical
        sceneCol.spacing = 7
        card.stack.addArrangedSubview(sceneCol)
        refreshSceneHint()
        refreshPlatButtons()
        return card
    }

    /// 说清词库到底是什么。四个平台都不公开敏感词清单，
    /// 用户看到平台勾选很容易以为这是官方词库——必须在界面上讲明白，
    /// 否则会被当成"过审检查"来用。
    private func basisCard() -> UIView {
        let card = Card("这份词库是什么")
        let body = UILabel()
        body.text = """
        依据《广告法》第九条（绝对化用语）、第十七条（非医疗广告不得宣称疗效），\
        以及四个平台公开的审核口径说明（社区公约、医疗与财经行业公约），\
        人工整理约 130 个词并标注适用平台。

        平台都不公开敏感词清单，所以这里不是官方词库。\
        它能挡住典型的广告法违规，但不等于过审，发布前仍要自己判断。

        检测在本机跑，稿子不出这台手机。
        """
        body.font = DS.font(.caption2)
        body.adjustsFontForContentSizeCategory = true
        body.textColor = DS.ink2
        body.numberOfLines = 0
        body.accessibilityIdentifier = "lexiconBasis"
        card.stack.addArrangedSubview(body)
        return card
    }

    private func customCard() -> UIView {
        let card = Card("自己的词")

        let hint = UILabel()
        hint.text = "加进去后按你设的替换，同词会覆盖内置建议。留空替换＝建议删除。"
        hint.font = DS.font(.caption2)
        hint.adjustsFontForContentSizeCategory = true
        hint.textColor = DS.ink3
        hint.numberOfLines = 0
        card.stack.addArrangedSubview(hint)

        styleField(wordField, placeholder: "敏感词", id: "customWord")
        styleField(repField, placeholder: "换成（可空）", id: "customReplacement")
        let add = UIButton(type: .system)
        add.setTitle("添加", for: .normal)
        add.titleLabel?.font = DS.font(.subheadline, weight: .semibold)
        add.titleLabel?.adjustsFontForContentSizeCategory = true
        add.setTitleColor(DS.ink, for: .normal)
        add.backgroundColor = DS.panel2
        add.layer.cornerRadius = 10
        add.layer.borderWidth = 1
        add.layer.borderColor = DS.line.cgColor
        add.accessibilityIdentifier = "customAdd"
        add.addTarget(self, action: #selector(addCustom), for: .touchUpInside)
        add.widthAnchor.constraint(equalToConstant: 58).isActive = true

        let row = UIStackView(arrangedSubviews: [wordField, repField, add])
        row.axis = .horizontal
        row.spacing = 6
        row.alignment = .fill
        row.heightAnchor.constraint(equalToConstant: 38).isActive = true
        card.stack.addArrangedSubview(row)

        customList.axis = .vertical
        customList.spacing = 6
        card.stack.addArrangedSubview(customList)
        refreshCustomList()
        return card
    }

    private func styleField(_ f: UITextField, placeholder: String, id: String) {
        f.placeholder = placeholder
        f.font = DS.font(.subheadline)
        f.adjustsFontForContentSizeCategory = true
        f.textColor = DS.ink
        f.backgroundColor = DS.panel2
        f.layer.cornerRadius = 10
        f.layer.borderWidth = 1
        f.layer.borderColor = DS.line.cgColor
        f.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        f.leftViewMode = .always
        f.autocorrectionType = .no
        f.accessibilityIdentifier = id
        f.returnKeyType = .done
        f.delegate = self
    }

    // MARK: - 检测与渲染

    private func rescan() {
        hits = Sensitive.scan(text, platforms: platforms,
                              scene: currentScene, custom: custom)
        renderSummary()
        renderHits()
    }

    private func renderSummary() {
        summary.arrangedSubviews.forEach { $0.removeFromSuperview() }
        bulkRow.arrangedSubviews.forEach { $0.removeFromSuperview() }

        guard !hits.isEmpty else {
            summary.addArrangedSubview(Pill("未检出", tone: .green))
            let note = UILabel()
            note.text = currentScene == .audit
                ? "全量自查也没检出" : "换成「全量自查」可以再严一遍"
            note.font = DS.font(.caption2)
            note.adjustsFontForContentSizeCategory = true
            note.textColor = DS.ink3
            summary.addArrangedSubview(note)
            bulkRow.isHidden = true
            return
        }
        bulkRow.isHidden = false
        summary.addArrangedSubview(Pill("检出 \(hits.count)", tone: .orange))
        let high = hits.filter { $0.severity == .high }.count
        if high > 0 { summary.addArrangedSubview(Pill("高风险 \(high)")) }

        let replaceable = hits.filter(\.canReplace).count
        let repAll = actionButton("一键替换\(replaceable > 0 ? " \(replaceable)" : "")",
                                  danger: false, id: "replaceAll",
                                  sel: #selector(replaceAllTapped))
        repAll.isEnabled = replaceable > 0
        repAll.alpha = replaceable > 0 ? 1 : 0.45
        bulkRow.addArrangedSubview(repAll)
        bulkRow.addArrangedSubview(actionButton("一键删除", danger: true, id: "deleteAll",
                                                sel: #selector(deleteAllTapped)))
    }

    private func renderHits() {
        hitList.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, h) in hits.enumerated() {
            hitList.addArrangedSubview(hitCard(h, index: i))
        }
    }

    private func hitCard(_ h: Hit, index: Int) -> UIView {
        let box = UIView()
        box.backgroundColor = DS.panel2
        box.layer.cornerRadius = DS.radiusSm

        let word = UILabel()
        word.text = h.word
        word.font = DS.font(.body, weight: .bold)
        word.adjustsFontForContentSizeCategory = true
        word.textColor = DS.ink
        word.accessibilityIdentifier = "hitWord_\(index)"

        let tag = Pill(h.severity == .high ? "建议改" : "建议核",
                       tone: h.severity == .high ? .plain : .orange)
        let cat = Pill(h.category.label)

        let head = UIStackView(arrangedSubviews: [word, tag, cat, UIView()])
        head.axis = .horizontal
        head.spacing = 7
        head.alignment = .center

        let why = UILabel()
        why.text = "\(h.reason) · \(h.platformLabel)"
        why.font = DS.font(.caption2)
        why.adjustsFontForContentSizeCategory = true
        why.textColor = DS.ink2
        why.numberOfLines = 0

        // 上下文里把命中词标出来。用 NSRange 定位，emoji 稿子也不会切错。
        let ctx = UILabel()
        let snippet = Sensitive.snippet(text, range: h.nsRange)
        let attr = NSMutableAttributedString(
            string: snippet,
            attributes: [.font: DS.font(.caption1), .foregroundColor: DS.ink3])
        let local = (snippet as NSString).range(of: h.word)
        if local.location != NSNotFound {
            attr.addAttributes([.foregroundColor: DS.danger,
                                .font: DS.font(.caption1, weight: .bold)], range: local)
        }
        ctx.attributedText = attr
        ctx.adjustsFontForContentSizeCategory = true
        ctx.numberOfLines = 0

        let acts = UIStackView()
        acts.axis = .horizontal
        acts.spacing = 6
        acts.distribution = .fillEqually
        acts.heightAnchor.constraint(equalToConstant: 36).isActive = true
        if h.canReplace {
            let b = actionButton("换成「\(h.replacement)」", danger: false,
                                 id: "replaceHit_\(index)", sel: #selector(replaceOne(_:)))
            b.tag = index
            acts.addArrangedSubview(b)
        }
        let del = actionButton("删除", danger: true, id: "deleteHit_\(index)",
                               sel: #selector(deleteOne(_:)))
        del.tag = index
        acts.addArrangedSubview(del)

        let stack = UIStackView(arrangedSubviews: [head, why, ctx, acts])
        stack.axis = .vertical
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: box.topAnchor, constant: 11),
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -11),
        ])
        return box
    }

    /// 胶囊按钮。用 UIButton.Configuration —— contentEdgeInsets 在 iOS 26
    /// 已失效，按钮算不出内在尺寸会整个不进无障碍树。
    private func actionButton(_ t: String, danger: Bool, id: String, sel: Selector) -> UIButton {
        var c = UIButton.Configuration.filled()
        c.title = t
        c.baseBackgroundColor = DS.panel
        c.baseForegroundColor = danger ? DS.danger : DS.ink
        c.background.cornerRadius = 10
        c.background.strokeColor = DS.line
        c.background.strokeWidth = 1
        c.contentInsets = .init(top: 7, leading: 8, bottom: 7, trailing: 8)
        c.titleTextAttributesTransformer = .init { attrs in
            var a = attrs
            a.font = DS.font(.caption1, weight: .semibold)
            return a
        }
        let b = UIButton(configuration: c)
        b.accessibilityIdentifier = id
        b.addTarget(self, action: sel, for: .touchUpInside)
        return b
    }

    private func refreshPlatButtons() {
        for (i, p) in Platform.allCases.enumerated() {
            guard let b = platRow.arrangedSubviews[i] as? UIButton else { continue }
            let on = platforms.contains(p)
            b.backgroundColor = on ? DS.brand.withAlphaComponent(0.55) : DS.panel2
            b.setTitleColor(on ? DS.ink : DS.ink3, for: .normal)
            b.layer.borderWidth = 1
            b.layer.borderColor = (on ? DS.brand : DS.line).cgColor
            b.accessibilityValue = on ? "已选" : "未选"
        }
    }

    private func refreshCustomList() {
        customList.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, c) in custom.enumerated() {
            let lbl = UILabel()
            lbl.text = c.replacement.isEmpty ? "\(c.word) → 删除" : "\(c.word) → \(c.replacement)"
            lbl.font = DS.font(.caption1, weight: .medium)
            lbl.adjustsFontForContentSizeCategory = true
            lbl.textColor = DS.ink2
            lbl.accessibilityIdentifier = "customItem_\(i)"
            let rm = UIButton(type: .system)
            rm.setTitle("移除", for: .normal)
            rm.titleLabel?.font = DS.font(.caption1)
            rm.setTitleColor(DS.ink3, for: .normal)
            rm.accessibilityIdentifier = "customRemove_\(i)"
            rm.tag = i
            rm.addTarget(self, action: #selector(removeCustom(_:)), for: .touchUpInside)
            rm.widthAnchor.constraint(equalToConstant: 44).isActive = true
            let row = UIStackView(arrangedSubviews: [lbl, rm])
            row.axis = .horizontal
            row.spacing = 8
            row.alignment = .center
            customList.addArrangedSubview(row)
        }
    }

    // MARK: - 动作

    @objc private func platTapped(_ b: UIButton) {
        let p = Platform.allCases[b.tag]
        if platforms.contains(p) {
            // 不允许全部取消：一个都不选等于没有检测口径
            guard platforms.count > 1 else { return }
            platforms.remove(p)
        } else {
            platforms.insert(p)
        }
        refreshPlatButtons()
        rescan()
    }

    @objc private func sceneChanged() {
        SensitivePrefs.saveScene(currentScene)
        refreshSceneHint()
        rescan()
    }

    /// 当前档位。
    private var currentScene: ScanScene {
        let all = ScanScene.allCases
        let i = sceneSeg.selectedSegmentIndex
        return all.indices.contains(i) ? all[i] : .story
    }

    private func refreshSceneHint() {
        sceneHint.text = currentScene.hint
    }

    @objc private func addCustom() {
        let w = (wordField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty else { return }
        let r = (repField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let i = custom.firstIndex(where: { $0.word == w }) {
            custom[i] = CustomWord(word: w, replacement: r)
        } else {
            custom.append(CustomWord(word: w, replacement: r))
        }
        SensitivePrefs.saveCustom(custom)
        wordField.text = ""
        repField.text = ""
        view.endEditing(true)
        refreshCustomList()
        rescan()
    }

    @objc private func removeCustom(_ b: UIButton) {
        guard custom.indices.contains(b.tag) else { return }
        custom.remove(at: b.tag)
        SensitivePrefs.saveCustom(custom)
        refreshCustomList()
        rescan()
    }

    @objc private func replaceOne(_ b: UIButton) { apply(.replace, only: b.tag) }
    @objc private func deleteOne(_ b: UIButton) { apply(.delete, only: b.tag) }
    @objc private func replaceAllTapped() { apply(.replace, only: nil) }
    @objc private func deleteAllTapped() { apply(.delete, only: nil) }

    private func apply(_ mode: ApplyMode, only index: Int?) {
        let next = Sensitive.apply(text, hits: hits, mode: mode, only: index)
        guard next != text else { return }
        text = next
        onApply?(next)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        rescan()
    }

    @objc private func closeTapped() {
        view.endEditing(true)
        dismiss(animated: true)
    }
}

extension SensitiveViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === wordField {
            repField.becomeFirstResponder()
        } else {
            addCustom()
        }
        return true
    }
}

/// 严格模式与自定义词存本机。检测本身不联网，这些偏好也没必要上云。
enum SensitivePrefs {
    private static let strictKey = "sensitive.strict"
    private static let customKey = "sensitive.custom"

    /// 检测档位。记住用户上次选的 —— 同一个人的稿子类型通常不变，
    /// 每次都要重选很烦。
    static func loadScene() -> ScanScene {
        guard let raw = UserDefaults.standard.string(forKey: "sens.scene"),
              let s = ScanScene(rawValue: raw) else { return .story }
        return s
    }

    static func saveScene(_ s: ScanScene) {
        UserDefaults.standard.set(s.rawValue, forKey: "sens.scene")
    }

    static func loadStrict() -> Bool {
        UserDefaults.standard.bool(forKey: strictKey)
    }
    static func saveStrict(_ v: Bool) {
        UserDefaults.standard.set(v, forKey: strictKey)
    }
    static func loadCustom() -> [CustomWord] {
        guard let d = UserDefaults.standard.data(forKey: customKey),
              let list = try? JSONDecoder().decode([CustomWord].self, from: d) else { return [] }
        return list
    }
    static func saveCustom(_ list: [CustomWord]) {
        guard let d = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(d, forKey: customKey)
    }
}
