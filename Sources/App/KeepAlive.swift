import AVFoundation

/// 无声音频保活。
///
/// PiP 窗口本身由系统渲染，切到别的 App（包括系统相机）后依然显示——
/// 这点不需要我们做什么。问题在于**内容要继续更新**：提词文字得随语音滚动，
/// 而 App 进入后台后默认会被挂起，就没法再往 display layer 推帧了。
///
/// `UIBackgroundModes: [audio]` 授予的后台执行权，前提是真的有音频在活动。
/// 所以这里播一条无声循环音轨：不出声、不打断别人（.mixWithOthers），
/// 但让音频会话保持 active，App 就能在后台继续渲染 PiP 帧。
final class KeepAlive {

    private var player: AVAudioPlayer?
    private var observing = false
    /// 被系统打断（相机开始录制、来电等）时回调，外层可据此提示用户。
    var onInterrupted: ((Bool) -> Void)?

    /// 生成一段极短的无声 PCM WAV。用代码生成而不是塞资源文件，
    /// 免得工程里多一个二进制。
    private static func silentWAV(seconds: Double = 0.5,
                                  sampleRate: Int = 44100) -> Data {
        let frames = Int(Double(sampleRate) * seconds)
        let dataBytes = frames * 2                 // 单声道 16bit
        var d = Data()
        func str(_ s: String) { d.append(s.data(using: .ascii)!) }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }

        str("RIFF"); u32(UInt32(36 + dataBytes)); str("WAVE")
        str("fmt "); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        str("data"); u32(UInt32(dataBytes))
        d.append(Data(count: dataBytes))           // 全零 = 静音
        return d
    }

    func start() {
        observeInterruptions()
        // 类别统一由 AudioSessionManager 管。这里不能设 .playback ——
        // 那会关掉麦克风输入，语音跟读的 installTap 会崩。
        AudioSessionManager.activateForRecordAndPlayback()

        guard player == nil else { player?.play(); return }
        do {
            let p = try AVAudioPlayer(data: Self.silentWAV())
            p.numberOfLoops = -1
            p.volume = 0
            p.prepareToPlay()
            p.play()
            player = p
        } catch {
            NSLog("[KeepAlive] 无声音轨启动失败: \(error.localizedDescription)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        // 不在这里 deactivate：语音识别可能还在用同一个会话。
        // 由 PrompterViewController 在全部停止后统一收。
    }

    /// 系统相机开始录制时会抢音频会话，我们的无声音轨会被打断。
    /// 打断结束后必须主动恢复，否则后台执行权没了、PiP 里的文字就冻住。
    private func observeInterruptions() {
        guard !observing else { return }
        observing = true
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            switch type {
            case .began:
                self.onInterrupted?(true)
            case .ended:
                // 重新激活并续播。相机录完/来电结束后走这里。
                AudioSessionManager.activateForRecordAndPlayback()
                self.player?.play()
                self.onInterrupted?(false)
            @unknown default: break
            }
        }
    }
}
