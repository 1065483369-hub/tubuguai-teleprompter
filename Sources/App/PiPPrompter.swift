import UIKit
import AVKit
import AVFoundation

/// 画中画提词浮窗。
///
/// 做法是把提词文字渲染成视频帧推给 AVSampleBufferDisplayLayer，
/// 再用 AVPictureInPictureController 的 ContentSource（iOS 15+）把这个 layer
/// 变成画中画内容源。这是公开 API 路线。
///
/// 网上流传的另一种 hack 是 `UIApplication.shared.windows.first?.addSubview(...)`
/// 把 UIView 叠在 PiP 宿主 window 上。它不编码进视频流，所以：
///   - 在别的 App（包括系统相机）之上无效——那是另一个进程
///   - 还要配私有 KVC `setValue(1, forKey:"controlsStyle")` 藏控件，有拒审风险
/// 这里不走那条路。文字真的进了视频帧，PiP 显示的就是内容本身。
///
/// 注意：PiP 在模拟器上不可用（isPictureInPictureSupported() 返回 false）。
final class PiPPrompter: NSObject {

    // 竖排窄条，贴在镜头下方最合适。太宽会挡取景。
    private let frameSize = CGSize(width: 480, height: 270)

    private let displayLayer = AVSampleBufferDisplayLayer()
    private var controller: AVPictureInPictureController?
    /// 推帧时钟。**不能用 CADisplayLink**——它在 App 进后台时被系统暂停，
    /// 而「切到系统相机」正是后台场景，一切过去推帧就停、PiP 立刻黑掉。
    /// 用 DispatchSourceTimer，配合 UIBackgroundModes:[audio] 的后台执行权继续跑。
    private var timer: DispatchSourceTimer?
    private var lastRenderedKey: String = ""
    private let keepAlive = KeepAlive()
    /// 后台每隔几帧补推一次相同内容。PiP 的 layer 队列空了系统就显示黑窗，
    /// 所以即便文字没变也要有帧在流动。
    private var idleTicks = 0

    /// 提词内容由外部驱动：整篇文字 + 当前已读位置。
    var script: String = ""
    var readChar: Int = 0
    var showPace: Pace? = nil          // 当前行的语速标记
    var onStateChange: ((Bool) -> Void)?
    /// 浮窗里点「上一句/下一句」时回调（正=往后，负=往前）。
    /// PiP 窗口内不能放自定义按钮，但系统的快退/快进控件可以借用。
    var onSkip: ((Int) -> Void)?
    /// 音频会话被打断（系统相机开始录制、来电等）。true=开始，false=已恢复。
    var onInterrupted: ((Bool) -> Void)?

    var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }
    var isActive: Bool { controller?.isPictureInPictureActive ?? false }

    override init() {
        super.init()
        keepAlive.onInterrupted = { [weak self] began in
            guard let self else { return }
            // 打断结束后必须救画面，不只是救音频。KeepAlive 只做了
            // setActive + player.play()，layer 那边该 flush 该补帧没人管，
            // 于是音频活着、浮窗黑着。
            if !began { self.recoverAfterInterruption() }
            self.onInterrupted?(began)
        }
        displayLayer.videoGravity = .resizeAspect
        displayLayer.frame = CGRect(origin: .zero, size: frameSize)
    }

    /// 必须在能拿到 UIWindow 之后调用：PiP 要求 layer 在视图层级里。
    /// 幂等：viewDidLayoutSubviews 每次都会调，不能每次都重建控制器。
    /// 重建会丢掉正在进行的 PiP 会话——系统浮窗还在屏幕上，
    /// 但新控制器的 isPictureInPictureActive 是 false，按钮语义就反了
    /// （该收浮窗时却去 start）。旋转屏幕、键盘弹出都会触发布局。
    func attach(to host: UIView) {
        if displayLayer.superlayer === host.layer, controller != nil {
            return                      // 已经挂在同一个宿主上，什么都不做
        }
        displayLayer.removeFromSuperlayer()
        // 放在层级里但不可见——PiP 需要它 attached，用户看的是浮窗
        displayLayer.isHidden = true
        host.layer.addSublayer(displayLayer)
        if controller == nil { setupController() }
    }

    private func setupController() {
        guard isSupported else { return }
        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer, playbackDelegate: self)
        let c = AVPictureInPictureController(contentSource: source)
        c.delegate = self
        c.canStartPictureInPictureAutomaticallyFromInline = true
        // 显示快退/快进控件——在 PiP 里它们是「上一句/下一句」。
        // 这是窗口内唯一被系统允许的自定义交互。
        c.requiresLinearPlayback = false
        controller = c
    }

    func start() {
        guard let c = controller, !c.isPictureInPictureActive else { return }
        // 先起保活再开 PiP：切到相机 App 后要靠它维持后台执行，
        // 否则 App 被挂起，PiP 里的文字就冻住不动了。
        keepAlive.start()
        renderFrame(force: true)          // 先垫一帧，否则 PiP 可能显示空白
        c.startPictureInPicture()
        startTicking()
    }

    func stop() {
        controller?.stopPictureInPicture()
        stopTicking()
        keepAlive.stop()
    }

    private func startTicking() {
        stopTicking()
        // 提词文字变化不频繁，10fps 足够且省电。
        // 关键是这条时钟必须在后台继续走：用户开着浮窗切去系统相机时，
        // App 在后台，CADisplayLink 会被暂停，DispatchSourceTimer 不会。
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: .milliseconds(100), leeway: .milliseconds(20))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    private func stopTicking() {
        timer?.cancel()
        timer = nil
        idleTicks = 0
    }

    private func tick() { renderFrame(force: false) }

    /// 只在内容真的变了才重绘——滚动位置不动时白烧 CPU 没意义。
    /// 但完全不推帧也不行：PiP 的 layer 队列见底后系统会显示黑窗，
    /// 所以内容没变时每 1 秒补推一帧，把队列续上。
    private func renderFrame(force: Bool) {
        let key = "\(readChar)|\(showPace?.rawValue ?? "")|\(script.count)"
        let changed = key != lastRenderedKey
        if !force, !changed {
            idleTicks += 1
            guard idleTicks >= 10 else { return }   // 10 tick × 100ms = 1s
        }
        idleTicks = 0
        lastRenderedKey = key

        guard let buffer = PromptRenderer.makeSampleBuffer(
            script: script, readChar: readChar, pace: showPace, size: frameSize
        ) else { return }

        // status 只在这里检查。之前 flush 也只在 tick 里跑，
        // 时钟一停就永远恢复不了——这是黑屏后再也回不来的原因之一。
        if displayLayer.status == .failed { displayLayer.flush() }
        displayLayer.enqueue(buffer)
    }

    /// 音频会话被系统相机抢走后调用。重激活音频只恢复了后台执行权，
    /// 画面还得自己救：layer 可能已被判 failed，必须 flush 并强制重推一帧。
    func recoverAfterInterruption() {
        guard isActive else { return }
        displayLayer.flush()
        lastRenderedKey = ""          // 让下一帧一定被当成「变了」
        renderFrame(force: true)
        if timer == nil { startTicking() }
    }
}

// MARK: - PiP 代理

extension PiPPrompter: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ c: AVPictureInPictureController) {
        onStateChange?(true)
    }
    func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) {
        stopTicking()
        onStateChange?(false)
    }
    func pictureInPictureController(_ c: AVPictureInPictureController,
                                   failedToStartPictureInPictureWithError error: Error) {
        NSLog("PiP 启动失败: \(error.localizedDescription)")
        onStateChange?(false)
    }
}

// 提词器不是播放器，但 ContentSource 要求实现这个协议。
// 报一个"正在播放的无限流"，这样 PiP 不会显示进度条也不会自动停。
extension PiPPrompter: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(_ c: AVPictureInPictureController,
                                   setPlaying playing: Bool) {}
    func pictureInPictureControllerTimeRangeForPlayback(
        _ c: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }
    func pictureInPictureControllerIsPlaybackPaused(
        _ c: AVPictureInPictureController) -> Bool { false }
    func pictureInPictureController(_ c: AVPictureInPictureController,
                                   didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}
    /// 系统的快退/快进在这里落地成「上下一句」。
    /// skipInterval 的正负告诉我们方向，具体跳几个字由外层按气口算。
    func pictureInPictureController(_ c: AVPictureInPictureController,
                                   skipByInterval skipInterval: CMTime) async {
        let secs = CMTimeGetSeconds(skipInterval)
        await MainActor.run { onSkip?(secs >= 0 ? 1 : -1) }
    }
}
