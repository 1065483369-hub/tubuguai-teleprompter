import UIKit
import AVFoundation

/// 主界面：相机取景铺底，提词文字浮在上面，可切到画中画。
final class PrompterViewController: UIViewController {

    private let camera = CameraController()
    private let speech = SpeechTracker()
    private let pip = PiPPrompter()

    private var previewLayer: AVCaptureVideoPreviewLayer!
    private let textView = UITextView()
    private let guideLine = UIView()
    /// 锚定线右端的小竖条，提示"这条线能拖"。
    private let guideHandle = UIView()
    /// 拖拽热区。1pt 的线按不准，给它一条 44pt 高的透明抓手（Apple 的最小触控尺寸）。
    private let guideGrip = UIView()
    private let frameGuide = UIView()
    private let heardLabel = UILabel()
    private let badge = Badge()
    private let recPill = UIView()
    private let recTime = UILabel()
    private let progressTrack = UIView()
    private let progressBar = UIView()
    private let percentLabel = UILabel()
    /// 上一帧高亮的区间，用于精准清除而不误伤语速标记的底色。
    private var lastNowRange: NSRange?
    private var hudHideWork: DispatchWorkItem?
    private var lastTickTime: CFTimeInterval = 0
    private var autoScrollAccum: Double = 0
    private var countdownLabel: UILabel?
    private var paused = false
    private var countdownCancelled = false
    /// 语速标记在显示串里占的区间。着色时要跳过，否则它们的黑字被染灰。
    private var paceRanges: [NSRange] = []
    private var bar = UIStackView()
    private var actionRow = UIStackView()
    private let controlBackdrop = UIView()
    private let controlGradient = CAGradientLayer()
    private var buttons: [HUDButton] = []
    private var settingsSheet: RecordingSettingsSheet?
    /// 返回键：导航动作，独立放左上角，不混在念稿操作里。
    private let backButton = HUDButton("‹ 返回")
    /// 唯一的录制状态入口：开始录制后才进入暂停/继续跟读状态。
    private let recordButton = HUDButton("开始录制")
    /// 浮窗是配系统相机使用时最重要的出口，固定在底部正中。
    private let pipButton = HUDButton("浮窗")
    private var cfg = SetupViewController.Config()

    private var script = ""
    private var lines: [Line] = []
    /// 原文字符下标 -> 显示串 UTF-16 偏移。渲染时一次建好，
    /// 高亮和点词都查这张表。末尾多一位表示"全文末尾"。
    ///
    /// 为什么必须建表而不是现算：Character 数与 UTF-16 长度并不相等。
    /// "\r\n" 是 1 个 Character 但占 2 个 UTF-16 单元，emoji 同理。
    /// 按 Character 累加会和 NSAttributedString.length 逐渐错位，
    /// 表现是读到后面高亮整体偏移。
    private var charToVisual: [Int] = []
    private var readChar = 0
    private var softChar = 0
    private var running = false
    private var camEnabled = true                 // 关掉它就是「只做 PiP，配系统相机用」
    private var yieldUntil: Date = .distantPast   // 手动滚动后让位

    // 弹簧滚动状态。离散的位置更新直接 setContentOffset 会一跳一跳，
    // 用临界阻尼弹簧融成连续滑动 —— 手感基本都来自这一层。
    private var curY: CGFloat = 0
    private var targetY: CGFloat = 0
    private var vel: CGFloat = 0
    private var ticker: CADisplayLink?
    /// 当前行停在屏幕高度的这个比例处。三处（内边距、锚定线、弹簧目标）必须一致。
    /// 当前行停在屏幕高度的这个比例处。用户可调（设置页「提词位置」）——
    /// 手机架多高、视线角度多少每次都不一样，固定 40% 不够用。
    private var ANCHOR_RATIO: CGFloat { CGFloat(cfg.promptTop) / 100 }

    private func recordingIcon(_ name: String, fallback: UIImage) -> UIImage {
        UIImage(named: name) ?? fallback
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupPreview()
        setupText()
        setupChrome()
        setupBar()
        // 首帧布局完成后再弹设置页，否则 present 时机太早会闪
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // 调试/测试用：注入稿子并直接进提词页，跳过手动输入
            let env = ProcessInfo.processInfo.environment
            // 注入稿子与"自动进提词页"拆开：只给 UITEST_SCRIPT 时
            // 稿子进设置页但停在那儿，这样才能测编辑页和敏感词检测。
            if let injected = env["UITEST_SCRIPT"], !injected.isEmpty {
                var c = self.cfg
                c.script = injected
                c.camOn = env["UITEST_NOCAM"] != "1"
                self.cfg = c
                self.applyConfig(c)
            }
            if let injected = env["UITEST_SCRIPT"], !injected.isEmpty,
               env["UITEST_AUTOSTART"] == "1" {
                // 调试用：直接落到指定位置，方便验证中段的高亮与进度
                if let rc = env["UITEST_READCHAR"], let n = Int(rc) {
                    self.readChar = min(max(0, n), self.script.count)
                    // softChar 可单独指定，用于验证「逐字高亮走在 anchor 之前」
                    let soft = Int(env["UITEST_SOFTCHAR"] ?? "") ?? self.readChar
                    self.softChar = min(max(0, soft), self.script.count)
                    self.paint()
                }
                self.startRun()
                return
            }
            self.showEditor()
        }

        camera.onRecordFinished = { [weak self] url, err in
            guard let self else { return }
            self.recPill.isHidden = true
            self.updateRecordingControl()
            guard let url else { self.toast("录制失败：\(err?.localizedDescription ?? "未知")"); return }
            self.camera.saveToPhotos(url) { ok in
                self.toast(ok ? "已存入相册" : "存相册失败（检查相册权限）")
            }
        }
        speech.onPosition = { [weak self] anchor, soft, _ in
            guard let self, self.running, !self.paused else { return }
            self.readChar = anchor
            self.softChar = soft
            self.paint()
        }
        speech.onHeard = { [weak self] t in
            self?.heardLabel.text = String(t.suffix(24))
        }
        speech.onError = { [weak self] m in self?.toast(m) }
        pip.onStateChange = { [weak self] active in
            guard let self else { return }
            self.badge.set(active ? "浮窗已开 · 可切系统相机"
                                  : (self.running ? "跟读中" : "待机"),
                           live: active || self.running)
            self.pipButton.setTitle(active ? "收起浮窗" : "浮窗", for: .normal)
            self.pipButton.apply(active ? .active : .normal)
        }
        // 系统相机一开始录制就会抢音频会话，把我们的后台保活打断。
        // 恢复是自动的（见 KeepAlive），这里只是让用户知道发生了什么。
        // 浮窗里点上下一句：按气口分段移动，比按固定字数自然
        pip.onSkip = { [weak self] dir in
            guard let self else { return }
            self.skipLine(dir)
        }
        pip.onInterrupted = { [weak self] began in
            guard let self, self.pip.isActive else { return }
            self.badge.set(began ? "音频被占用 · 恢复中" : "浮窗已开 · 可切系统相机",
                           live: !began)
        }
        pip.onPlaybackPausedChange = { [weak self] isPaused in
            self?.setPaused(isPaused)
        }
    }

    // MARK: - 视图

    private func setupPreview() {
        previewLayer = AVCaptureVideoPreviewLayer(session: camera.session)
        // gravity 在 applyConfig 里按选定比例设置：
        // 铺满 = resizeAspectFill（裁边），锁比例 = resizeAspect（看全画面）
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
    }

    /// 预览层始终铺满全屏。之前支持锁比例，结果上下留出大黑边，
    /// 看起来就是"比例不对、不是满屏"。取景要沉浸，边缘裁一点可以接受。

    private func setupText() {
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.showsVerticalScrollIndicator = false
        textView.contentInsetAdjustmentBehavior = .never
        // 文字压在画面上，必须有阴影，否则浅色背景看不清
        textView.layer.shadowColor = UIColor.black.cgColor
        textView.layer.shadowOpacity = 0.95
        textView.layer.shadowRadius = 6
        textView.layer.shadowOffset = CGSize(width: 0, height: 1)
        textView.delegate = self
        textView.accessibilityIdentifier = "prompterText"
        view.addSubview(textView)

        // 视线锚定线：眼睛盯这条线，不用追字
        // 锚定线：淡到几乎看不见，起到定位作用但不干扰阅读
        guideLine.backgroundColor = DS.pinkBright.withAlphaComponent(0.22)
        view.addSubview(guideLine)

        // 锚定线可直接拖。设置页里那个「提词位置」滑块要退出念稿才能调，
        // 而架好手机后想微调高低是当场的事——在这儿拖最直接。
        // 手柄比线本身宽得多：1pt 的线没法用手指准确按住。
        guideHandle.backgroundColor = DS.pinkBright.withAlphaComponent(0.9)
        guideHandle.layer.cornerRadius = 2.5
        guideHandle.layer.zPosition = 11
        guideHandle.isUserInteractionEnabled = false
        view.addSubview(guideHandle)

        guideGrip.layer.zPosition = 11
        guideGrip.accessibilityIdentifier = "guideGrip"
        guideGrip.accessibilityLabel = "跟读线位置"
        guideGrip.isAccessibilityElement = true
        guideGrip.accessibilityTraits = .adjustable
        view.addSubview(guideGrip)
        guideGrip.addGestureRecognizer(
            UIPanGestureRecognizer(target: self, action: #selector(dragGuide(_:))))

        // 取景框：标出真正会被录进视频的范围。
        // 预览是 aspectFill（铺满屏、裁掉边缘），录制却保留全画幅，
        // 用户抱怨「录制时镜头显示范围比录成视频显示范围小」就是这个错位。
        frameGuide.layer.borderColor = DS.violet.withAlphaComponent(0.42).cgColor
        frameGuide.layer.borderWidth = 1
        frameGuide.isUserInteractionEnabled = false
        frameGuide.isHidden = true
        view.addSubview(frameGuide)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapText(_:)))
        textView.addGestureRecognizer(tap)
    }

    private func setupChrome() {
        view.addSubview(badge)

        // 录制指示：红色胶囊 + 闪烁圆点 + 计时
        recPill.backgroundColor = DS.danger.withAlphaComponent(0.94)
        recPill.layer.cornerRadius = 11
        recPill.isUserInteractionEnabled = true
        recPill.accessibilityLabel = "录制中，点此结束并保存"
        recPill.accessibilityHint = "双击结束视频录制"
        recPill.isHidden = true
        let dot = UIView()
        dot.backgroundColor = .white
        dot.layer.cornerRadius = 3.5
        recTime.text = "录制中 · 点此结束"
        recTime.font = .monospacedDigitSystemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize, weight: .semibold)
        recTime.textColor = .white
        let row = UIStackView(arrangedSubviews: [dot, recTime])
        row.spacing = 6
        row.alignment = .center
        recPill.addSubview(row)
        view.addSubview(recPill)
        [dot, row].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 7),
            dot.heightAnchor.constraint(equalToConstant: 7),
            row.topAnchor.constraint(equalTo: recPill.topAnchor, constant: 5),
            row.bottomAnchor.constraint(equalTo: recPill.bottomAnchor, constant: -5),
            row.leadingAnchor.constraint(equalTo: recPill.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: recPill.trailingAnchor, constant: -10),
        ])
        // 闪烁靠动画，不用定时器
        let blink = CABasicAnimation(keyPath: "opacity")
        blink.fromValue = 1; blink.toValue = 0.2
        blink.duration = 0.55
        blink.autoreverses = true
        blink.repeatCount = .infinity
        dot.layer.add(blink, forKey: "blink")
        recPill.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(stopRecording)))

        // 顶部细进度条：绿色高亮说明"念到哪个字"，进度条说明"整篇走了多少"
        progressTrack.backgroundColor = UIColor(hex: 0x232936, alpha: 0.9)
        progressBar.backgroundColor = DS.pinkBright
        progressBar.layer.shadowColor = DS.pinkBright.cgColor
        progressBar.layer.shadowOpacity = 0.7
        progressBar.layer.shadowRadius = 4
        progressBar.layer.shadowOffset = .zero
        progressTrack.addSubview(progressBar)
        view.addSubview(progressTrack)

        percentLabel.font = .monospacedDigitSystemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .caption2).pointSize, weight: .semibold)
        percentLabel.textColor = UIColor(white: 1, alpha: 0.7)
        percentLabel.textAlignment = .left
        view.addSubview(percentLabel)

        heardLabel.font = DS.font(.caption2)
        heardLabel.adjustsFontForContentSizeCategory = true
        heardLabel.textColor = UIColor(white: 1, alpha: 0.45)
        heardLabel.textAlignment = .right
        view.addSubview(heardLabel)
    }

    private func setupBar() {
        controlBackdrop.isUserInteractionEnabled = false
        controlGradient.colors = [UIColor.clear.cgColor,
                                  UIColor.black.withAlphaComponent(0.56).cgColor,
                                  UIColor.black.withAlphaComponent(0.88).cgColor]
        controlGradient.locations = [0, 0.28, 1]
        controlBackdrop.layer.addSublayer(controlGradient)
        view.addSubview(controlBackdrop)

        // 常用工具集中在主按钮上方；图标与名称一起出现，避免靠猜。
        let topSpecs: [(String, UIImage, Selector)] = [
            ("文字", recordingIcon("RecordingTextIcon", fallback: DreamIcon.textControls), #selector(showTextSettings)),
            ("左右翻转", recordingIcon("RecordingMirrorHorizontalIcon", fallback: DreamIcon.mirrorHorizontal), #selector(toggleHorizontalMirror)),
            ("上下翻转", recordingIcon("RecordingMirrorVerticalIcon", fallback: DreamIcon.mirrorVertical), #selector(toggleVerticalMirror)),
            ("镜头翻转", recordingIcon("RecordingFlipCameraIcon", fallback: DreamIcon.flipCamera), #selector(flipCam)),
        ]
        let navigationSpecs: [(String, UIImage, Selector)] = [
            ("上一句", recordingIcon("RecordingPreviousIcon", fallback: DreamIcon.navigation(forward: false)), #selector(prevLine)),
            ("下一句", recordingIcon("RecordingNextIcon", fallback: DreamIcon.navigation(forward: true)), #selector(nextLine)),
        ]
        buttons = topSpecs.map { title, icon, sel in
            let b = HUDButton(title)
            b.setImage(icon, for: .normal)
            b.accessibilityIdentifier = "hud." + title
            b.addTarget(self, action: sel, for: .touchUpInside)
            return b
        }
        let navigationButtons = navigationSpecs.map { title, icon, sel in
            let b = HUDButton(title)
            b.setImage(icon, for: .normal)
            b.accessibilityIdentifier = "hud." + title
            b.addTarget(self, action: sel, for: .touchUpInside)
            return b
        }
        buttons += navigationButtons
        // 轻点相机翻转前后镜头；长按切换到“只做浮窗”模式，仍可配系统相机录制。
        button(for: "镜头翻转")?.addGestureRecognizer(
            UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:))))
        let topRow = UIStackView(arrangedSubviews: Array(buttons.prefix(topSpecs.count)))
        topRow.spacing = 6
        topRow.distribution = .fillEqually
        topRow.heightAnchor.constraint(equalToConstant: 52).isActive = true

        bar = topRow
        view.addSubview(bar)

        // 返回：左上角。accessibilityIdentifier 沿用 "hud." 前缀，
        // 现有 UI 测试按这个名字找它。
        backButton.accessibilityIdentifier = "hud.‹ 返回"
        backButton.addTarget(self, action: #selector(showEditor), for: .touchUpInside)
        view.addSubview(backButton)

        // 底部主按钮负责单一状态流：开始录制后才显示暂停/继续。
        recordButton.accessibilityIdentifier = "hud.跟读控制"
        recordButton.setImage(recordingIcon("RecordingRecordIcon", fallback: DreamIcon.record), for: .normal)
        recordButton.addTarget(self, action: #selector(toggleRecordingControl), for: .touchUpInside)

        actionRow = UIStackView(arrangedSubviews: [navigationButtons[0], recordButton, navigationButtons[1]])
        actionRow.spacing = 8
        actionRow.distribution = .fillEqually
        view.addSubview(actionRow)

        pipButton.accessibilityIdentifier = "hud.浮窗"
        pipButton.setImage(recordingIcon("RecordingFloatingIcon", fallback: DreamIcon.floatingWindow), for: .normal)
        pipButton.addTarget(self, action: #selector(togglePiP), for: .touchUpInside)
        view.addSubview(pipButton)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds        // 始终满屏
        layoutFrameGuide()
        let safe = view.safeAreaInsets
        textView.frame = view.bounds
        // 上下留白各半屏，让当前行能停在屏幕 40% 处
        textView.textContainerInset = UIEdgeInsets(
            top: view.bounds.height * ANCHOR_RATIO, left: 18,
            bottom: view.bounds.height * 0.6, right: 18)
        let guideY = view.bounds.height * ANCHOR_RATIO
        guideLine.frame = CGRect(x: 0, y: guideY, width: view.bounds.width, height: 1)
        // 手柄贴右边，避开左侧正文起始位置
        guideHandle.frame = CGRect(x: view.bounds.width - 34, y: guideY - 9, width: 5, height: 19)
        // 抓手横跨右侧一段、纵向 44pt，手指好按又不挡住左边的字
        guideGrip.frame = CGRect(x: view.bounds.width - 76, y: guideY - 22, width: 76, height: 44)
        // 徽章按内容自适应宽度，靠右
        let bw = min(view.bounds.width * 0.62, badge.systemLayoutSizeFitting(
            UIView.layoutFittingCompressedSize).width)
        badge.frame = CGRect(x: view.bounds.width - bw - 12, y: safe.top + 8,
                             width: bw, height: 22)
        let rw = recPill.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width
        recPill.frame = CGRect(x: 12, y: safe.top + 8, width: rw, height: 22)

        // 进度条压在安全区顶边，不挡内容
        progressTrack.frame = CGRect(x: 0, y: safe.top, width: view.bounds.width, height: 2)
        // 百分比挪到右上，和状态徽章同一行，不再单独占一行
        percentLabel.frame = CGRect(x: view.bounds.width - 46, y: safe.top + 34,
                                    width: 36, height: 13)
        percentLabel.textAlignment = .right
        updateProgress()

        // 返回键：左上角。和录制胶囊同一行高度，但录制胶囊在 x=12 只在
        // 录制时才显示，所以两者错开——返回贴左，录制胶囊往右挪。
        let backW: CGFloat = 76, backH: CGFloat = 38
        backButton.frame = CGRect(x: 12, y: safe.top + 30, width: backW, height: backH)
        // 录制中时把红色计时胶囊挪到返回键右边，别叠在一起
        if !recPill.isHidden {
            recPill.frame = CGRect(x: 12 + backW + 8, y: safe.top + 8, width: rw, height: 22)
        }

        // 最底部是浮窗；上一句、录制/暂停、下一句位于它正上方同一行。
        let pipW: CGFloat = 116, pipH: CGFloat = 52
        pipButton.frame = CGRect(x: view.bounds.midX - pipW / 2,
                                 y: view.bounds.height - safe.bottom - pipH - 12,
                                 width: pipW, height: pipH)
        pipButton.layer.cornerRadius = pipH / 2
        let actionH: CGFloat = 56
        actionRow.frame = CGRect(x: 12, y: pipButton.frame.minY - actionH - 8,
                                 width: view.bounds.width - 24, height: actionH)

        // 工具栏位于录制控制上方，顶部不放会遮镜头的操作。
        let barH: CGFloat = 52
        bar.frame = CGRect(x: 12, y: actionRow.frame.minY - barH - 10,
                           width: view.bounds.width - 24, height: barH)
        controlBackdrop.frame = CGRect(x: 0, y: bar.frame.minY - 28,
                                       width: view.bounds.width,
                                       height: view.bounds.height - bar.frame.minY + 28)
        controlGradient.frame = controlBackdrop.bounds
        // 识别回显放在 HUD 上方，别被两行按钮压住
        heardLabel.frame = CGRect(x: 20, y: bar.frame.minY - 18,
                                  width: view.bounds.width - 40, height: 14)
        pip.attach(to: view)
    }

    // MARK: - 稿子

    @objc private func showEditor() {
        // 防重入。已有 presented controller 时 present 会被静默忽略，
        // 于是"返回键点了没反应"。先把旧的收掉再弹。
        if let shown = presentedViewController {
            shown.dismiss(animated: false) { [weak self] in self?.showEditor() }
            return
        }
        stopRun()
        cfg.script = script
        let setup = SetupViewController(config: cfg)
        setup.modalPresentationStyle = .fullScreen
        setup.onStart = { [weak self, weak setup] c in
            guard let self else { return }
            self.cfg = c
            self.applyConfig(c)
            setup?.dismiss(animated: true) { self.startRun() }
        }
        present(setup, animated: true)
    }

    /// 应用设置页带回的配置。
    private func applyConfig(_ c: SetupViewController.Config) {
        script = c.script
        lines = segment(script)
        speech.load(script: script)
        readChar = 0; softChar = 0
        curY = 0; targetY = 0; vel = 0

        camEnabled = c.camOn
        previewLayer.isHidden = !c.camOn
        // 始终 resizeAspectFill：铺满屏幕、裁掉边缘。
        previewLayer.videoGravity = .resizeAspectFill
        view.setNeedsLayout()
        textView.alpha = CGFloat(c.textOpacity) / 100

        // 镜像用 transform 组合，两个方向可同时开
        var t = CGAffineTransform.identity
        if c.mirrorX { t = t.scaledBy(x: -1, y: 1) }
        if c.mirrorY { t = t.scaledBy(x: 1, y: -1) }
        textView.transform = t

        // 当前摄像头方向和设置不一致就翻转
        if camEnabled, (camera.position == .front) != c.front {
            camera.flip(useMic: false)
        }
        renderScript()
        let sec = estimateDuration(lines)
        badge.set(lines.isEmpty ? "待机" : "约 \(formatDuration(sec))", live: false)
    }

    /// 渲染稿子。气口按强度撑间距，语速标记加色块。
    private func renderScript() {
        let attr = NSMutableAttributedString()
        let chars = Array(script)
        var paceAt: [Int: Pace] = [:]
        for ln in lines {
            if ln.pace != .normal { paceAt[ln.start] = ln.pace }
        }
        let para = NSMutableParagraphStyle()
        // 行距按倍数换算成额外间距
        para.lineSpacing = CGFloat(cfg.fontSize) * (CGFloat(cfg.lineSpacing) / 100 - 1)
        para.paragraphSpacing = 0
        let font = UIFont.systemFont(ofSize: CGFloat(cfg.fontSize), weight: .semibold)

        charToVisual = []
        charToVisual.reserveCapacity(chars.count + 1)
        paceRanges = []
        for i in chars.indices {
            if let p = paceAt[i] {
                // 语速提示用小字符，不用彩色方块 —— 色块又大又跳，
                // 会抢走本该属于跟读高亮的注意力。
                let badge = NSAttributedString(
                    string: p == .slow ? "▸" : "»",
                    attributes: [
                        .font: UIFont.systemFont(ofSize: CGFloat(cfg.fontSize) * 0.5,
                                                 weight: .semibold),
                        .foregroundColor: (p == .slow ? DS.warn : DS.info)
                            .withAlphaComponent(0.55),
                        .baselineOffset: CGFloat(cfg.fontSize) * 0.12,
                    ])
                paceRanges.append(NSRange(location: attr.length, length: badge.length))
                attr.append(badge)
            }
            // 这个字符在显示串里的起点。语速标记已插在它前面，所以先记后追加。
            charToVisual.append(attr.length)
            attr.append(NSAttributedString(string: String(chars[i]),
                                           attributes: [.font: font,
                                                        .paragraphStyle: para]))
        }
        charToVisual.append(attr.length)   // 末位 = 全文末尾
        textView.attributedText = attr
        paint()
    }

    /// 已读置灰、当前提亮。charIndex 到 attributedText 位置要跳过气口和标记，
    /// 所以按 dataMap 换算而不是直接当下标用。
    private func paint() {
        guard let attr = textView.attributedText, attr.length > 0 else { return }
        let m = NSMutableAttributedString(attributedString: attr)
        // 用 softChar 而非 readChar 做高亮。readChar(anchor) 只在 ASR 出
        // final 时推进，往往几秒一次，高亮就一顿一顿跳大段；
        // softChar 由 partial 驱动、逐字更新，才是用户眼里的"读到哪"。
        // 两者原来一个驱动高亮一个驱动滚动，所以还互相不同步。
        let visualRead = visualOffset(forChar: max(readChar, softChar), in: m)
        // 只清上一帧高亮过的那一段。不能整篇 removeAttribute(.backgroundColor) ——
        // 语速标记（慢/快）的橙蓝底色也是 backgroundColor，会被一起抹掉。
        if let prev = lastNowRange,
           prev.location + prev.length <= m.length {
            m.removeAttribute(.backgroundColor, range: prev)
        }

        // 分段着色，跳过语速标记 —— 它们有自己的黑字+橙蓝底，不能被染色
        paintSkippingBadges(m, NSRange(location: 0, length: min(visualRead, m.length)),
                            color: DS.textRead)
        if visualRead < m.length {
            paintSkippingBadges(m, NSRange(location: visualRead,
                                           length: m.length - visualRead),
                                color: DS.textAhead)
            // 当前位置用绿色 + 底色。原来是白字 2 个，和未读的浅灰几乎分不出，
            // 用户反馈「看不到跟读进度」。绿色底块扫一眼就知道念到哪。
            let nowLen = min(2, m.length - visualRead)
            let nowRange = NSRange(location: visualRead, length: nowLen)
            m.addAttribute(.foregroundColor, value: DS.textNow, range: nowRange)
            m.addAttribute(.backgroundColor, value: DS.textNowBg, range: nowRange)
            lastNowRange = nowRange
        } else {
            lastNowRange = nil
        }
        textView.attributedText = m
        updateProgress()
        pip.script = script
        pip.readChar = max(readChar, softChar)   // 浮窗高亮同样要逐字
        pip.showPace = currentPace()
        springTo(char: softChar)
    }

    /// 原文字符偏移 -> 显示串 UTF-16 偏移。查渲染时建好的表，不重算。
    private func visualOffset(forChar char: Int, in s: NSAttributedString) -> Int {
        guard !charToVisual.isEmpty else { return 0 }
        let i = max(0, min(char, charToVisual.count - 1))
        return min(charToVisual[i], s.length)
    }

    /// 显示串 UTF-16 偏移 -> 原文字符偏移。表是单调的，二分查找。
    private func charOffset(forVisual visual: Int) -> Int {
        guard !charToVisual.isEmpty else { return 0 }
        var lo = 0, hi = charToVisual.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if charToVisual[mid] <= visual { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    private func currentPace() -> Pace? {
        lines.first { readChar >= $0.start && readChar < $0.end }?.pace
    }

    // MARK: - 弹簧滚动

    private func springTo(char: Int) {
        guard textView.attributedText?.length ?? 0 > 0 else { return }
        let visual = visualOffset(forChar: char, in: textView.attributedText!)
        let pos = textView.position(from: textView.beginningOfDocument, offset: min(visual, textView.attributedText!.length))
        guard let pos, let rect = textView.caretRect(for: pos) as CGRect? else { return }
        // rect.minY 已含 textContainerInset.top，减去锚定线高度即为目标滚动量。
        // （原来这里多写了 +inset-inset 一对自相抵消的项，纯噪音。）
        targetY = max(0, rect.minY - view.bounds.height * ANCHOR_RATIO)
    }

    private func startTicker() {
        stopTicker()
        let l = CADisplayLink(target: self, selector: #selector(tick))
        l.add(to: .main, forMode: .common)
        ticker = l
    }
    private func stopTicker() { ticker?.invalidate(); ticker = nil }

    @objc private func tick() {
        guard running else { return }
        advanceAutoScroll()
        if Date() < yieldUntil {          // 手动滚动期间不抢方向盘
            curY = textView.contentOffset.y
            vel = 0
            return
        }
        let d = targetY - curY
        if abs(d) < 0.4, abs(vel) < 0.4 { vel = 0; return }
        // 临界阻尼，半隐式欧拉。0.35s 时间常数在跟手和不晃之间最平衡。
        let dt: CGFloat = 1.0 / 60, omega: CGFloat = 2 / 0.35
        vel = (vel + omega * omega * d * dt) / (1 + 2 * omega * dt)
        curY += vel * dt
        textView.setContentOffset(CGPoint(x: 0, y: max(0, curY)), animated: false)
    }

    // MARK: - 操作

    @objc private func toggleRun() {
        running ? stopRun() : startRun()
    }

    private func startRun() {
        guard !script.isEmpty else { toast("先粘贴稿子"); return }
        // 倒计时：点开始不该立刻滚 —— 要留几秒调整坐姿、看镜头、深呼吸。
        guard cfg.countdown <= 0 else { runCountdown(cfg.countdown) { [weak self] in
            self?.beginRun()
        }; return }
        beginRun()
    }

    /// 全屏倒计时。数字每秒缩放淡出，最后一声"开始"。
    private func runCountdown(_ from: Int, done: @escaping () -> Void) {
        let label = UILabel()
        label.font = .systemFont(ofSize: 108, weight: .thin)
        label.textColor = .white
        label.textAlignment = .center
        label.shadowColor = UIColor.black.withAlphaComponent(0.6)
        label.shadowOffset = CGSize(width: 0, height: 2)
        label.frame = view.bounds
        label.accessibilityIdentifier = "countdown"
        // 倒计时期间轻点可取消 —— 之前一旦开始只能干等数完
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(cancelCountdown)))
        view.addSubview(label)
        countdownLabel = label
        countdownCancelled = false

        var n = from
        func step() {
            if self.countdownCancelled {
                label.removeFromSuperview()
                self.countdownLabel = nil
                return
            }
            guard n > 0 else {
                label.text = "开始"
                label.font = .systemFont(ofSize: 52, weight: .semibold)
                UIView.animate(withDuration: 0.45, animations: {
                    label.alpha = 0
                    label.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
                }) { _ in
                    label.removeFromSuperview()
                    self.countdownLabel = nil
                    done()
                }
                return
            }
            label.text = "\(n)"
            label.alpha = 1
            label.transform = CGAffineTransform(scaleX: 1.35, y: 1.35)
            UIView.animate(withDuration: 0.75, delay: 0, options: .curveEaseOut) {
                label.alpha = 0.15
                label.transform = .identity
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            n -= 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: step)
        }
        step()
    }

    @objc private func cancelCountdown() {
        countdownCancelled = true
        countdownLabel?.removeFromSuperview()
        countdownLabel = nil
        badge.set("已取消", live: false)
        scheduleHUDHide()
    }

    private func beginRun() {
        speech.requestPermission { [weak self] ok in
            guard let self else { return }
            guard ok else { self.toast("需要麦克风和语音识别权限"); return }
            // 语音识别独占麦克风，所以相机这边先不接音频，
            // 录制时再切进来（见 toggleRecordingControl）。
            if self.camEnabled {
                self.camera.configure(useMic: false)
                self.camera.start()
            }
            self.speech.start()
            self.running = true
            self.startTicker()
            self.lastTickTime = 0
            self.autoScrollAccum = 0
            self.setPaused(false)
            self.badge.set(self.cfg.scrollMode == .voice ? "跟读中" : "滚动中", live: true)
            self.scheduleHUDHide()
            self.updateRecordingControl()
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }

    private func stopRun() {
        countdownLabel?.removeFromSuperview()
        countdownLabel = nil
        running = false
        pip.setPlaybackPaused(false)
        paused = false
        speech.stop()
        stopTicker()
        badge.set("待机", live: false)
        updateRecordingControl()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    @objc private func toggleRecordingControl() {
        scheduleHUDHide()
        if camera.isRecording {
            togglePause()
        } else if countdownLabel != nil {
            cancelCountdown()
        } else {
            startRecordingFlow()
        }
    }

    @objc private func stopRecording() {
        guard camera.isRecording else { return }
        camera.stopRecording()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        scheduleHUDHide()
    }

    @objc private func togglePiP() {
        scheduleHUDHide()
        guard pip.isSupported else {
            toast("此设备/模拟器不支持画中画（PiP 需真机）")
            return
        }
        guard !script.isEmpty else { toast("先粘贴稿子"); return }
        pip.isActive ? pip.stop() : pip.start()
    }

    /// 给区间着色，但跳过语速标记（它们自带配色）。
    private func paintSkippingBadges(_ m: NSMutableAttributedString,
                                     _ range: NSRange, color: UIColor) {
        guard range.length > 0 else { return }
        var cursor = range.location
        let end = range.location + range.length
        for badge in paceRanges where badge.location < end
                                   && badge.location + badge.length > range.location {
            if badge.location > cursor {
                m.addAttribute(.foregroundColor, value: color,
                               range: NSRange(location: cursor,
                                              length: badge.location - cursor))
            }
            cursor = max(cursor, badge.location + badge.length)
        }
        if cursor < end {
            m.addAttribute(.foregroundColor, value: color,
                           range: NSRange(location: cursor, length: end - cursor))
        }
    }

    /// 匀速与定时模式下自动推进位置。语音跟随模式不动 —— 那由 ASR 驱动。
    private func advanceAutoScroll() {
        guard cfg.scrollMode != .voice, !script.isEmpty, !paused else { return }
        let now = CACurrentMediaTime()
        defer { lastTickTime = now }
        guard lastTickTime > 0 else { return }
        let dt = min(0.1, now - lastTickTime)     // 掉帧时不要跳一大步

        // 每秒该念多少字
        let charsPerSec: Double
        switch cfg.scrollMode {
        case .manual:
            // 滑块值 ×10 = 字/分钟。40 → 400 字/分，接近中文口播常速
            charsPerSec = Double(cfg.manualSpeed) * 10 / 60
        case .timed:
            // 按剩余字数与剩余时间反推，保证按点读完
            let total = max(1, estimateDuration(lines))
            charsPerSec = Double(script.count) / Double(total)
        case .voice:
            return
        }

        autoScrollAccum += charsPerSec * dt
        guard autoScrollAccum >= 1 else { return }
        let step = Int(autoScrollAccum)
        autoScrollAccum -= Double(step)
        let next = min(script.count, softChar + step)
        guard next != softChar else { return }
        softChar = next
        readChar = next
        paint()
    }

    /// 开始录制。关键是**不关语音跟读** —— 边录边跟读是这个 App 的核心价值，
    /// 之前录制会 speech.stop()，等于二选一。
    ///
    /// 两条音频路径能共存：SFSpeech 走 AVAudioEngine 的 tap，
    /// 录制走 AVCaptureDeviceInput，会话是 .playAndRecord + .mixWithOthers，
    /// 系统把同一物理麦克风分发给两者。
    private func startRecordingFlow() {
        guard camEnabled else {
            toast("请先在设置里打开相机取景")
            return
        }
        // 倒计时：用户抱怨「延迟3秒拍摄的阶段一样会被录像，后期还要剪辑」。
        // 录制前的倒计时不该进成片。
        let lead = cfg.recordAfterCountdown ? cfg.countdown : 0
        if lead > 0 {
            runCountdown(lead) { [weak self] in self?.actuallyStartRecording() }
        } else {
            actuallyStartRecording()
        }
    }

    private func actuallyStartRecording() {
        camera.configure(useMic: true)
        camera.start()
        // 采集会话重配需要一点时间才稳定，太早 startRecording 会丢头几帧
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self else { return }
            self.camera.startRecording()
            self.recPill.isHidden = false
            self.updateRecordingControl()
            // 跟读继续跑。若之前没在跟读，录制时顺便起来 —— 用户按下录制
            // 就是要开始念了，不该再多点一次「开始」。
            if !self.running {
                self.beginRun()
            } else if self.paused {
                self.setPaused(false)
            }
            self.badge.set("录制中 · 跟读中", live: true)
        }
    }

    /// 算出「真正会被录进视频的范围」并画框。
    /// 传感器是 4:3，屏幕约 19.5:9 —— aspectFill 铺满屏会裁掉画面上下，
    /// 而录制保留全画幅。这个框让用户知道构图边界在哪，不必等录完才发现。
    private func layoutFrameGuide() {
        guard camEnabled, cfg.showFrameGuide else { frameGuide.isHidden = true; return }
        let b = view.bounds
        guard b.width > 0, b.height > 0 else { return }
        // 画幅比例按「长边 : 短边」表示，和屏幕同一口径才好比较
        let capture: CGFloat = 4.0 / 3.0        // sessionPreset .high
        frameGuide.isHidden = false

        // 相机画幅铺满屏幕的短边（aspectFill 的行为），长边按比例推出来
        let shortSide = min(b.width, b.height)
        let longSide = shortSide * capture
        if b.height > b.width {
            // 竖屏：短边是宽，画幅高度 = 宽 × 4/3
            frameGuide.frame = CGRect(x: 0, y: (b.height - longSide) / 2,
                                      width: b.width, height: longSide)
        } else {
            // 横屏：短边是高，画幅宽度 = 高 × 4/3
            frameGuide.frame = CGRect(x: (b.width - longSide) / 2, y: 0,
                                      width: longSide, height: b.height)
        }
    }

    /// 刷新进度条与百分比。
    private func updateProgress() {
        let total = max(1, script.count)
        // 同高亮：用 soft 才逐字跟手
        let pos = max(readChar, softChar)
        let ratio = min(1, max(0, CGFloat(pos) / CGFloat(total)))
        progressBar.frame = CGRect(x: 0, y: 0,
                                   width: progressTrack.bounds.width * ratio,
                                   height: progressTrack.bounds.height)
        percentLabel.text = "\(Int(ratio * 100))%"
    }

    /// 按气口分段跳一句。浮窗控件和 App 内按钮共用这个逻辑。
    private func skipLine(_ dir: Int) {
        guard !lines.isEmpty else { return }
        // 找当前所在的那一行
        let cur = lines.firstIndex { readChar >= $0.start && readChar < $0.end }
            ?? (readChar >= (lines.last?.end ?? 0) ? lines.count - 1 : 0)
        let next = max(0, min(lines.count - 1, cur + dir))
        let target = lines[next].start
        readChar = target
        softChar = target
        yieldUntil = .distantPast
        speech.seek(toChar: target)
        paint()
        scrollToRead()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func flipCam() {
        scheduleHUDHide()
        guard camEnabled else { toast("已关闭自带相机（只做浮窗）"); return }
        camera.flip(useMic: camera.isRecording)
    }

    @objc private func showTextSettings() {
        if settingsSheet != nil { return }
        let sheet = RecordingSettingsSheet(config: cfg)
        sheet.onChange = { [weak self] size, opacity, spacing in
            guard let self else { return }
            self.cfg.fontSize = size
            self.cfg.textOpacity = opacity
            self.cfg.lineSpacing = spacing
            self.textView.alpha = CGFloat(opacity) / 100
            self.renderScript()
            self.scrollToRead(animated: false)
        }
        sheet.onDismiss = { [weak self] in self?.settingsSheet = nil }
        settingsSheet = sheet
        view.addSubview(sheet)
        sheet.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sheet.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            sheet.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            sheet.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])
        sheet.show()
    }

    @objc private func toggleHorizontalMirror() {
        cfg.mirrorX.toggle()
        applyMirroring()
        toast(cfg.mirrorX ? "已左右镜像" : "已关闭左右镜像")
        scheduleHUDHide()
    }

    @objc private func toggleVerticalMirror() {
        cfg.mirrorY.toggle()
        applyMirroring()
        toast(cfg.mirrorY ? "已上下镜像" : "已关闭上下镜像")
        scheduleHUDHide()
    }

    private func applyMirroring() {
        var transform = CGAffineTransform.identity
        if cfg.mirrorX { transform = transform.scaledBy(x: -1, y: 1) }
        if cfg.mirrorY { transform = transform.scaledBy(x: 1, y: -1) }
        textView.transform = transform
    }

    @objc private func showMoreActions() {
        let menu = UIAlertController(title: "更多控制", message: nil, preferredStyle: .actionSheet)
        menu.addAction(UIAlertAction(title: "打开/关闭浮窗", style: .default) { [weak self] _ in self?.togglePiP() })
        menu.addAction(UIAlertAction(title: "切换相机取景", style: .default) { [weak self] _ in self?.toggleCamMode() })
        menu.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(menu, animated: true)
    }

    /// 长按「翻转」切换：自带相机 <-> 只做浮窗（配系统相机用）。
    /// 只做浮窗时必须释放摄像头，否则系统相机可能打不开。
    @objc private func toggleCamMode() {
        camEnabled.toggle()
        if camEnabled {
            camera.configure(useMic: false)
            camera.start()
            previewLayer.isHidden = false
            toast("自带相机已开")
        } else {
            camera.stopRecording()
            camera.stop()
            previewLayer.isHidden = true
            view.backgroundColor = .black
            toast("只做浮窗 · 用系统相机录")
        }
    }

    /// 拖动跟读线。位置实时写回 cfg.promptTop，所以退出念稿后设置页里
    /// 那个「提词位置」滑块也跟着变，两处是同一个值。
    @objc private func dragGuide(_ g: UIPanGestureRecognizer) {
        let y = g.location(in: view).y
        // 15%~65% 和设置页滑块同一范围：太靠顶看不到前文，太靠底后文没地方显示
        let ratio = min(max(0.15, y / view.bounds.height), 0.65)
        cfg.promptTop = Float(ratio * 100)

        switch g.state {
        case .began:
            // 拖的时候把线点亮，让用户看清自己在动什么
            guideLine.backgroundColor = DS.pinkBright.withAlphaComponent(0.75)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            hudHideWork?.cancel()      // 别在拖拽中途把 HUD 收走
        case .ended, .cancelled, .failed:
            guideLine.backgroundColor = DS.pinkBright.withAlphaComponent(0.22)
            UISelectionFeedbackGenerator().selectionChanged()
            scheduleHUDHide()
        default: break
        }

        // 锚定线动了，文字的上下留白和滚动目标都要跟着重算
        view.setNeedsLayout()
        // 立刻把当前行重新对到新线位，否则要等下一次语音更新才归位
        scrollToRead(animated: false)
        toast("跟读线 \(Int(ratio * 100))%")
    }

    @objc private func tapText(_ g: UITapGestureRecognizer) {
        // HUD 已隐藏时，第一次轻点只负责唤回按钮 —— 用户此刻想要的是
        // 操作入口，不是跳转位置。跳位置容易误触，代价也大。
        // HUD 处于淡出态时，第一次轻点只负责唤回 —— 用户此刻想要的是
        // 完整的操作入口，不是跳转位置（跳错了代价大）。
        if bar.alpha < 0.9 {
            scheduleHUDHide()
            return
        }
        let p = g.location(in: textView)
        guard let tp = textView.closestPosition(to: p) else { return }
        let visual = textView.offset(from: textView.beginningOfDocument, to: tp)
        // 显示偏移 -> 原文偏移：查同一张映射表，不再逐字回推。
        // 之前那套回推按 Character 累加，遇到 CRLF/emoji 会和 UTF-16 错位。
        let counted = charOffset(forVisual: visual)
        readChar = counted; softChar = counted
        scheduleHUDHide()          // 点屏幕就唤回 HUD 并重新计时
        yieldUntil = .distantPast
        speech.seek(toChar: counted)
        paint()
        scrollToRead()
    }

    /// 硬跳到当前朗读位置。
    ///
    /// 必须同步弹簧状态（curY/vel），否则弹簧会从旧位置再拉一次 ——
    /// 表现是画面先跳到位、又被慢慢拽回去。
    /// 这段逻辑原先在点字定位、跳句、拖锚定线三处各写了一遍。
    private func scrollToRead(animated: Bool = true) {
        springTo(char: max(readChar, softChar))
        curY = targetY
        vel = 0
        textView.setContentOffset(CGPoint(x: 0, y: max(0, curY)), animated: animated)
    }

    /// 按标题取 HUD 按钮。之前用下标，加一个按钮就全错位。
    private func button(for title: String) -> HUDButton? {
        buttons.first { $0.accessibilityIdentifier == "hud." + title }
    }

    /// HUD 自动隐藏。念稿时按钮不该一直占着底部空间，
    /// 轻点屏幕任意处唤回。
    private func scheduleHUDHide() {
        hudHideWork?.cancel()
        showHUD(true)
        let work = DispatchWorkItem { [weak self] in self?.showHUD(false) }
        hudHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
    }

    private func showHUD(_ show: Bool) {
        UIView.animate(withDuration: 0.28) {
            // 不再整条隐藏。用户反馈「没有返回键也没有录制键」——
            // 其实都在，但淡到 0 就等于功能消失，而且没有任何提示。
            // 现在最低降到 0.5：念稿时不抢注意力，但随时看得见、点得到。
            self.bar.alpha = show ? 1 : 0.92
            // 返回和录制已抽成独立按钮，得一起淡——否则念稿时它们始终全亮，
            // 反而比之前更抢注意力。
            self.backButton.alpha = show ? 1 : 0.5
            self.actionRow.alpha = show ? 1 : 0.92
            self.pipButton.alpha = show ? 1 : 0.92
            self.heardLabel.alpha = show ? 1 : 0
        }
    }

    /// 暂停 / 继续。关键是**不拆会话** —— 说错一句想重来，
    /// 之前只能停掉整个会话再从头开始（还要等 ASR 重新起来）。
    /// 现在只冻结位置更新，麦克风和识别任务都留着，继续时无缝衔接。
    @objc private func togglePause() {
        guard running else { startRun(); return }
        setPaused(!paused)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        scheduleHUDHide()
    }

    private func setPaused(_ shouldPause: Bool) {
        guard paused != shouldPause else { return }
        paused = shouldPause
        pip.setPlaybackPaused(shouldPause)
        if paused {
            speech.pause()
            badge.set("已暂停", live: false)
        } else {
            speech.resume()
            badge.set(cfg.scrollMode == .voice ? "跟读中" : "滚动中", live: true)
        }
        updateRecordingControl()
    }

    private func updateRecordingControl() {
        let title: String
        let style: HUDButton.Style
        if camera.isRecording {
            title = paused ? "继续跟读" : "暂停跟读"
            let fallback = paused ? DreamIcon.play : DreamIcon.pause
            let asset = paused ? "RecordingNextIcon" : "RecordingPauseIcon"
            recordButton.setImage(recordingIcon(asset, fallback: fallback), for: .normal)
            style = paused ? .active : .normal
        } else {
            title = "开始录制"
            recordButton.setImage(recordingIcon("RecordingRecordIcon", fallback: DreamIcon.record), for: .normal)
            style = .danger
        }
        recordButton.setTitle(title, for: .normal)
        recordButton.apply(style)
    }

    /// 提词页直接调字号。念到一半发现太小，不该退回设置页。
    @objc private func biggerFont() { bumpFont(+3) }
    @objc private func smallerFont() { bumpFont(-3) }

    private func bumpFont(_ delta: Float) {
        let next = min(64, max(18, cfg.fontSize + delta))
        guard next != cfg.fontSize else { return }
        cfg.fontSize = next
        renderScript()                  // 重排并保持当前位置
        springTo(char: max(readChar, softChar))
        curY = targetY; vel = 0
        textView.setContentOffset(CGPoint(x: 0, y: max(0, curY)), animated: false)
        badge.set("字号 \(Int(next))", live: running)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        scheduleHUDHide()
    }

    @objc private func prevLine() { skipLine(-1); scheduleHUDHide() }
    @objc private func nextLine() { skipLine(1); scheduleHUDHide() }

    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        if g.state == .began { toggleCamMode() }
    }

    private func toast(_ m: String) {
        badge.set(m, live: false)
        NSLog("[Prompter] \(m)")
    }

}

extension PrompterViewController: UITextViewDelegate {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        yieldUntil = Date().addingTimeInterval(3)   // 手动看稿时让位 3 秒
    }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate: Bool) {
        yieldUntil = Date().addingTimeInterval(3)
    }
}
