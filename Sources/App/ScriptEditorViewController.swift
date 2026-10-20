import UIKit

/// 稿子编辑页。独立成页，不和设置表单挤在一起。
///
/// 之前把输入框塞进设置页的滚动表单里，键盘一弹就没地方站：
/// 可视区只剩 351pt，而输入框顶部在 395pt，整体被推出屏幕，只露出 21pt。
/// 根因是「长表单 + 输入框 + 键盘」三者抢同一块高度。
///
/// 这里让输入框独占整页：键盘来了它自己收缩，永远可见、永远能编辑。
final class ScriptEditorViewController: UIViewController {

    private let textView = UITextView()
    private let checkButton = UIButton(type: .system)
    private let placeholder = UILabel()
    private let countLabel = UILabel()
    private let estStack = UIStackView()
    private var textBottom: NSLayoutConstraint!

    var onDone: ((String) -> Void)?
    private var initialText: String

    init(text: String) {
        self.initialText = text
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DS.bg
        build()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 不自动聚焦。稿子基本是粘贴进来的，一进页面就弹键盘会把
        // 粘贴/示例按钮挤掉——那正是「没办法粘贴」的由来。
        // 想打字的用户点一下输入框即可。
    }

    private func build() {
        // ── 顶部栏：取消 / 标题 / 完成 ──
        let cancel = UIButton(type: .system)
        cancel.setTitle("取消", for: .normal)
        cancel.titleLabel?.font = DS.font(.body)
        cancel.titleLabel?.adjustsFontForContentSizeCategory = true
        cancel.setTitleColor(DS.ink2, for: .normal)
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let title = UILabel()
        title.text = "稿子"
        title.font = DS.font(.body, weight: .semibold)
        title.adjustsFontForContentSizeCategory = true
        title.textColor = DS.ink

        let done = UIButton(type: .system)
        done.setTitle("完成", for: .normal)
        done.titleLabel?.font = DS.font(.body, weight: .bold)
        done.titleLabel?.adjustsFontForContentSizeCategory = true
        done.setTitleColor(DS.brand, for: .normal)
        done.accessibilityIdentifier = "editorDone"
        done.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

        // 顶部栏不用 stack + 空 UIView 间隔件：裸 UIView 没有内在尺寸，
        // 在 .fill 下会把整行高度拉成 0（实测 bar 高度 = 0，内容全不可见）。
        // 直接用容器 + 三个约束，标题居中，两侧按钮贴边。
        let bar = UIView()
        [cancel, title, done].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview($0)
        }
        NSLayoutConstraint.activate([
            bar.heightAnchor.constraint(equalToConstant: 40),
            cancel.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            cancel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            title.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            done.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            done.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])

        // ── 快捷动作：粘贴 / 导入 / 历史 / 清空 / 示例 ──
        let paste = chip("粘贴", primary: true, #selector(pasteTapped), id: "pasteButton")
        let clear = chip("清空", primary: false, #selector(clearTapped), id: "clearButton")
        let importB = chip("导入", primary: false, #selector(importTapped), id: "importButton")
        let history = chip("历史", primary: false, #selector(historyTapped), id: "historyButton")
        let sample = chip("示例稿", primary: false, #selector(sampleTapped), id: "sampleButton")
        // 同样避开裸 UIView 间隔件：左对齐即可，不需要撑满
        let actions = UIStackView(arrangedSubviews: [paste, importB, history, clear, sample])
        actions.spacing = 6
        // 不用 .fillProportionally + .center：按钮内在高度未确定时
        // 这个组合会把整行算成 0 高（探针实测 194x0，按钮全隐形）。
        // 给行一个明确高度、按钮纵向填满，最可靠。
        actions.alignment = .fill
        actions.distribution = .fillEqually
        actions.heightAnchor.constraint(equalToConstant: 38).isActive = true

        // ── 输入框：独占剩余空间 ──
        textView.backgroundColor = DS.panel2
        textView.textColor = DS.ink
        textView.font = DS.font(.body)
        textView.adjustsFontForContentSizeCategory = true
        textView.layer.cornerRadius = DS.radiusSm
        textView.textContainerInset = UIEdgeInsets(top: 14, left: 10, bottom: 14, right: 10)
        textView.text = initialText
        textView.delegate = self
        textView.keyboardAppearance = .dark
        textView.accessibilityIdentifier = "scriptInput"
        textView.accessibilityLabel = "稿子输入框"
        // 系统自带的滚动就够，不需要外层再套 scrollView
        textView.alwaysBounceVertical = true

        placeholder.text = "把稿子粘贴到这里。\n\n会自动标出气口和语速：\n数字、「关键」「但是」标慢，\n「那么」「接下来」标快。"
        placeholder.font = DS.font(.body)
        placeholder.adjustsFontForContentSizeCategory = true
        placeholder.textColor = DS.ink3
        placeholder.numberOfLines = 0
        placeholder.isUserInteractionEnabled = false
        textView.addSubview(placeholder)

        // ── 查敏感词：放输入框下方 ──
        // 这是「写完之后才做的事」，和粘贴/导入/清空（写之前的准备动作）
        // 不是同一类，挤在输入框上方那行属于位置错误。
        checkButton.setTitle("查敏感词", for: .normal)
        checkButton.titleLabel?.font = DS.font(.subheadline, weight: .semibold)
        checkButton.titleLabel?.adjustsFontForContentSizeCategory = true
        checkButton.setTitleColor(DS.ink, for: .normal)
        checkButton.backgroundColor = DS.panel2
        checkButton.layer.cornerRadius = 10
        checkButton.layer.borderWidth = 1
        checkButton.layer.borderColor = DS.line.cgColor
        checkButton.accessibilityIdentifier = "sensitiveButton"
        checkButton.addTarget(self, action: #selector(checkTapped), for: .touchUpInside)

        // ── 底部信息：字数 + 时长预估 ──
        countLabel.font = DS.font(.footnote)
        countLabel.adjustsFontForContentSizeCategory = true
        countLabel.textColor = DS.ink3
        estStack.spacing = 6
        estStack.alignment = .center
        let info = UIStackView(arrangedSubviews: [countLabel, estStack])
        info.spacing = 10
        info.alignment = .center

        [bar, actions, textView, placeholder, checkButton, info].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        view.addSubview(bar); view.addSubview(actions)
        view.addSubview(textView); view.addSubview(checkButton); view.addSubview(info)

        let g = view.safeAreaLayoutGuide
        // 底边同时受两条约束：信息栏之上、且不越过键盘顶部。
        // 手工算键盘几何很容易错（viewDidLoad 时 safeAreaInsets 还是 0，
        // 我算出过 -232 的偏移把输入框压成 13pt）。交给 keyboardLayoutGuide。
        textBottom = textView.bottomAnchor.constraint(equalTo: checkButton.topAnchor, constant: -10)
        let aboveKeyboard = textView.bottomAnchor.constraint(
            lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor, constant: -52)
        aboveKeyboard.priority = .required
        textBottom.priority = .defaultHigh   // 键盘约束优先
        // 保底高度：键盘占了下半屏时也要能看到 5~6 行，
        // 否则粘贴长稿完全没法核对。不够就让输入框自己滚。
        let minH = textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 150)
        minH.priority = .required
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: g.topAnchor, constant: 6),
            bar.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 16),
            bar.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -16),

            actions.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 10),
            actions.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 16),
            actions.trailingAnchor.constraint(lessThanOrEqualTo: g.trailingAnchor, constant: -16),

            textView.topAnchor.constraint(equalTo: actions.bottomAnchor, constant: 10),
            textView.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -12),
            textBottom,
            aboveKeyboard,
            minH,

            checkButton.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 12),
            checkButton.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -12),
            checkButton.bottomAnchor.constraint(equalTo: info.topAnchor, constant: -10),
            checkButton.heightAnchor.constraint(equalToConstant: 42),

            placeholder.topAnchor.constraint(equalTo: textView.topAnchor, constant: 14),
            placeholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 14),
            placeholder.trailingAnchor.constraint(equalTo: textView.trailingAnchor, constant: -14),

            info.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 16),
            info.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -16),
            info.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -10),
            info.heightAnchor.constraint(equalToConstant: 26),
        ])
        refresh()
    }

    /// 胶囊按钮。用 UIButton.Configuration —— contentEdgeInsets 在 iOS 26
    /// 已失效，按钮算不出内在尺寸，会整个不进无障碍树（UI 测试查不到、
    /// VoiceOver 也读不到）。
    private func chip(_ t: String, primary: Bool, _ sel: Selector, id: String) -> UIButton {
        var c = UIButton.Configuration.filled()
        c.title = t
        c.baseBackgroundColor = primary ? DS.brand : DS.panel2
        c.baseForegroundColor = primary ? DS.brandInk : DS.ink
        c.background.cornerRadius = 9
        c.contentInsets = .init(top: 8, leading: 9, bottom: 8, trailing: 9)
        c.titleTextAttributesTransformer = .init { attrs in
            var a = attrs
            a.font = DS.font(.subheadline, weight: .semibold)
            return a
        }
        if !primary {
            c.background.strokeColor = DS.line
            c.background.strokeWidth = 1
        }
        let b = UIButton(configuration: c)
        b.accessibilityIdentifier = id
        b.addTarget(self, action: sel, for: .touchUpInside)
        return b
    }

    @objc private func pasteTapped() {
        guard let t = UIPasteboard.general.string, !t.isEmpty else {
            countLabel.text = "剪贴板是空的"
            countLabel.textColor = UIColor(hex: 0xFB7185)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        textView.text = t
        refresh()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// 导入 txt / rtf / html / pdf。docx 是 zip 容器读不了，不做半成品。
    @objc private func importTapped() {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: ScriptImporter.types, asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    @objc private func clearTapped() {
        textView.text = ""
        refresh()
    }

    @objc private func historyTapped() {
        view.endEditing(true)
        let vc = ScriptHistoryViewController()
        vc.modalPresentationStyle = .pageSheet
        if let sheet = vc.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        vc.onSelect = { [weak self] text in
            self?.textView.text = text
            self?.refresh()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        present(vc, animated: true)
    }

    /// 示例稿：新用户不用自己找内容就能试。
    @objc private func sampleTapped() {
        textView.text = [
            "大家好，欢迎使用兔不乖的提词器。",
            "第一步，粘贴或输入你的稿子。长稿会自动分段，方便阅读和跟读。",
            "第二步，调整字号、行距、文字透明度和倒计时。把提词位置调到接近镜头的位置，念稿时眼神会更自然。",
            "第三步，选择滚动方式。第一次使用，推荐语音跟随：念到哪里，文字就亮到哪里；读错、回读或跳过一两句，也会尽量跟上你。",
            "点击开始后，完成倒计时再自然开口。拖动右侧的小手柄，可以调整粉色跟读线的高低；轻点稿子的任意位置，可以从那里重新开始跟读。",
            "说错时点暂停，整理好后再继续；也可以用上一句、下一句快速调整位置。",
            "点击录制，可以边录边跟读，视频会保存到相册。需要用系统相机拍摄时，打开浮窗后切到系统相机，也能继续看稿。",
            "第一次使用时，请允许麦克风、语音识别、相机和相册权限。建议先用一小段稿子试读，调好字号、提词位置和语速后再正式录制。",
        ].joined(separator: "\n")
        refresh()
    }

    /// 敏感词检测。改动通过 onApply 回传写回输入框——不让检测页
    /// 直接持有 textView，免得两边各存一份文本互相覆盖。
    @objc private func checkTapped() {
        let t = textView.text ?? ""
        guard !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            countLabel.text = "先粘贴稿子"
            countLabel.textColor = UIColor(hex: 0xFB7185)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        view.endEditing(true)
        let vc = SensitiveViewController(text: t)
        vc.onApply = { [weak self] next in
            guard let self else { return }
            self.textView.text = next
            self.refresh()
        }
        present(vc, animated: true)
    }

    @objc private func cancelTapped() {
        view.endEditing(true)
        dismiss(animated: true)
    }

    @objc private func doneTapped() {
        view.endEditing(true)
        let text = textView.text ?? ""
        ScriptHistoryStore.shared.save(text)
        onDone?(text)
    }

    private func refresh() {
        let t = textView.text ?? ""
        placeholder.isHidden = !t.isEmpty
        countLabel.textColor = DS.ink3
        countLabel.text = "\(t.count) 字"

        estStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let lines = segment(t)
        let sec = estimateDuration(lines)
        estStack.addArrangedSubview(Pill("约 \(formatDuration(sec))", tone: .green))
        estStack.addArrangedSubview(Pill("\(lines.count) 气口"))
        let slow = lines.filter { $0.pace == .slow }.count
        if slow > 0 { estStack.addArrangedSubview(Pill("慢 \(slow)", tone: .orange)) }
    }
}

extension ScriptEditorViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) { refresh() }
}

extension ScriptEditorViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        guard let text = ScriptImporter.read(url), !text.isEmpty else {
            countLabel.text = "这个文件读不出文字"
            countLabel.textColor = UIColor(hex: 0xFB7185)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        textView.text = text
        refresh()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
