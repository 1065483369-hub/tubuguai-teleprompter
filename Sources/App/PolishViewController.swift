import UIKit

final class PolishViewController: UIViewController {
    private let originalText: String
    private let sceneControl = UISegmentedControl(items: PolishScene.allCases.map(\.rawValue))
    private let methodLabel = UILabel()
    private let originalLabel = UILabel()
    private let resultView = UITextView()
    private let resultInfo = UILabel()
    private let generateButton = UIButton(type: .system)
    private let applyButton = UIButton(type: .system)
    private let copyButton = UIButton(type: .system)
    private var generationTask: Task<Void, Never>?

    var onApply: ((String) -> Void)?

    init(text: String) {
        originalText = text
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DS.bg
        build()
        refreshMethod()
    }

    deinit {
        generationTask?.cancel()
    }

    private func build() {
        let closeButton = UIButton(type: .system)
        closeButton.setTitle("返回", for: .normal)
        closeButton.setTitleColor(DS.ink2, for: .normal)
        closeButton.titleLabel?.font = DS.font(.body)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let titleLabel = UILabel()
        titleLabel.text = "口播优化"
        titleLabel.font = DS.font(.body, weight: .semibold)
        titleLabel.textColor = DS.ink

        let bar = UIView()
        [closeButton, titleLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview($0)
        }
        NSLayoutConstraint.activate([
            bar.heightAnchor.constraint(equalToConstant: 42),
            closeButton.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            closeButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])

        let sceneTitle = UILabel()
        sceneTitle.text = "这段稿子要怎么讲？"
        sceneTitle.font = DS.font(.headline, weight: .semibold)
        sceneTitle.textColor = DS.ink

        sceneControl.selectedSegmentIndex = 0
        sceneControl.selectedSegmentTintColor = DS.violet
        sceneControl.accessibilityIdentifier = "polishScene"
        sceneControl.addTarget(self, action: #selector(sceneChanged), for: .valueChanged)

        methodLabel.font = DS.font(.footnote)
        methodLabel.textColor = DS.ink2
        methodLabel.numberOfLines = 0
        methodLabel.accessibilityIdentifier = "polishMethod"

        let sourceTitle = UILabel()
        sourceTitle.text = "原稿"
        sourceTitle.font = DS.font(.subheadline, weight: .semibold)
        sourceTitle.textColor = DS.ink

        originalLabel.text = originalText
        originalLabel.numberOfLines = 4
        originalLabel.font = DS.font(.subheadline)
        originalLabel.textColor = DS.ink2
        originalLabel.accessibilityIdentifier = "polishOriginal"

        generateButton.setTitle("生成优化稿", for: .normal)
        generateButton.titleLabel?.font = DS.font(.body, weight: .semibold)
        generateButton.setTitleColor(DS.brandInk, for: .normal)
        generateButton.backgroundColor = DS.violet
        generateButton.layer.cornerRadius = 14
        generateButton.heightAnchor.constraint(equalToConstant: 46).isActive = true
        generateButton.accessibilityIdentifier = "polishGenerate"
        generateButton.addTarget(self, action: #selector(generateTapped), for: .touchUpInside)

        let resultTitle = UILabel()
        resultTitle.text = "优化结果，可继续编辑"
        resultTitle.font = DS.font(.subheadline, weight: .semibold)
        resultTitle.textColor = DS.ink

        resultView.backgroundColor = DS.panel2
        resultView.textColor = DS.ink
        resultView.font = DS.font(.body)
        resultView.adjustsFontForContentSizeCategory = true
        resultView.layer.cornerRadius = 16
        resultView.textContainerInset = UIEdgeInsets(top: 14, left: 10, bottom: 14, right: 10)
        resultView.delegate = self
        resultView.accessibilityIdentifier = "polishResult"
        resultView.heightAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true

        resultInfo.font = DS.font(.footnote)
        resultInfo.textColor = DS.ink2
        resultInfo.numberOfLines = 0
        resultInfo.text = "原稿 \(originalText.count) 字。生成前不会改动原稿。"

        let caution = UILabel()
        caution.text = "请核对人名、数字、商品功效和承诺；优化结果不能保证平台过审。"
        caution.font = DS.font(.footnote)
        caution.textColor = DS.ink2
        caution.numberOfLines = 0

        let content = UIStackView(arrangedSubviews: [sceneTitle, sceneControl, methodLabel,
            sourceTitle, originalLabel, generateButton, resultTitle, resultView, resultInfo, caution])
        content.axis = .vertical
        content.spacing = 12
        content.isLayoutMarginsRelativeArrangement = true
        content.directionalLayoutMargins = .init(top: 10, leading: 16, bottom: 18, trailing: 16)

        let scroll = UIScrollView()
        scroll.keyboardDismissMode = .interactive
        scroll.addSubview(content)

        copyButton.setTitle("复制结果", for: .normal)
        copyButton.setTitleColor(DS.ink, for: .normal)
        copyButton.titleLabel?.font = DS.font(.subheadline, weight: .semibold)
        copyButton.backgroundColor = DS.panel2
        copyButton.layer.cornerRadius = 12
        copyButton.accessibilityIdentifier = "polishCopy"
        copyButton.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)

        applyButton.setTitle("应用到稿子", for: .normal)
        applyButton.setTitleColor(DS.brandInk, for: .normal)
        applyButton.titleLabel?.font = DS.font(.subheadline, weight: .semibold)
        applyButton.backgroundColor = DS.violet
        applyButton.layer.cornerRadius = 12
        applyButton.accessibilityIdentifier = "polishApply"
        applyButton.addTarget(self, action: #selector(applyTapped), for: .touchUpInside)

        let bottomRow = UIStackView(arrangedSubviews: [copyButton, applyButton])
        bottomRow.spacing = 10
        bottomRow.distribution = .fillEqually

        [bar, scroll, content, bottomRow].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        view.addSubview(bar)
        view.addSubview(scroll)
        view.addSubview(bottomRow)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: guide.topAnchor, constant: 6),
            bar.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            bar.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomRow.topAnchor, constant: -8),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            bottomRow.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            bottomRow.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            bottomRow.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor, constant: -8),
            bottomRow.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -8).withPriority(.defaultHigh),
            bottomRow.heightAnchor.constraint(equalToConstant: 44),
        ])
        refreshResult()
    }

    private func refreshMethod() {
        methodLabel.text = ScriptPolisher.hasOnDeviceModel
            ? "本机智能润色可用。稿件只在设备内处理，不会上传。"
            : "本机智能模型不可用。当前只做基础文字整理，不会假装生成完整的风格改写，也不会上传稿件。"
    }

    private func refreshResult() {
        let text = resultView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let available = !text.isEmpty
        copyButton.isEnabled = available
        applyButton.isEnabled = available && text != originalText
        copyButton.alpha = available ? 1 : 0.45
        applyButton.alpha = applyButton.isEnabled ? 1 : 0.45
    }

    @objc private func sceneChanged() {
        generationTask?.cancel()
        generateButton.isEnabled = true
        generateButton.setTitle("生成优化稿", for: .normal)
        resultView.text = ""
        resultInfo.text = "原稿 \(originalText.count) 字。选择场景后点生成。"
        refreshResult()
    }

    @objc private func generateTapped() {
        view.endEditing(true)
        generationTask?.cancel()
        generateButton.isEnabled = false
        generateButton.setTitle("正在整理…", for: .normal)
        let scene = PolishScene.allCases[sceneControl.selectedSegmentIndex]
        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await ScriptPolisher.polish(self.originalText, scene: scene)
                guard !Task.isCancelled else { return }
                self.resultView.text = result.text
                self.resultInfo.text = result.method == .onDeviceModel
                    ? "本机智能改写 · \(self.originalText.count) → \(result.text.count) 字。应用前请核对事实。"
                    : "基础整理 · \(self.originalText.count) → \(result.text.count) 字。此设备暂不支持本机深度改写。"
                self.refreshResult()
            } catch {
                guard !Task.isCancelled else { return }
                self.resultInfo.text = "本机智能改写失败。原稿没有变化。"
                let alert = UIAlertController(title: "暂时无法改写", message: "可以稍后重试，或使用不生成新事实的基础整理。", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "取消", style: .cancel))
                alert.addAction(UIAlertAction(title: "基础整理", style: .default) { [weak self] _ in
                    guard let self else { return }
                    let text = ScriptPolisher.basicCleanup(self.originalText, scene: scene)
                    self.resultView.text = text
                    self.resultInfo.text = "基础整理 · \(self.originalText.count) → \(text.count) 字。"
                    self.refreshResult()
                })
                self.present(alert, animated: true)
            }
            self.generateButton.isEnabled = true
            self.generateButton.setTitle("重新生成", for: .normal)
        }
    }

    @objc private func copyTapped() {
        UIPasteboard.general.string = resultView.text
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func applyTapped() {
        let text = resultView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != originalText else { return }
        onApply?(text)
        dismiss(animated: true)
    }

    @objc private func closeTapped() {
        generationTask?.cancel()
        dismiss(animated: true)
    }
}

extension PolishViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        refreshResult()
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ value: UILayoutPriority) -> NSLayoutConstraint {
        priority = value
        return self
    }
}
