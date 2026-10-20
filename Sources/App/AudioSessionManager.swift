import AVFoundation

/// 音频会话统一收口。
///
/// 这里踩过一个会崩溃的坑：`KeepAlive` 为了 PiP 后台保活把类别设成 `.playback`，
/// 而 `.playback` **不允许输入**。此时 `AVAudioEngine.inputNode.outputFormat`
/// 返回采样率 0 的无效格式，`installTap(onBus:)` 会直接抛 NSException 崩溃。
///
/// 语音跟读要录音、PiP 保活要播放，两者必须共存，所以统一用
/// `.playAndRecord + .mixWithOthers`：既能拿到麦克风，也不打断别人的音频。
/// 任何模块都不要自己 setCategory，一律走这里。
enum AudioSessionManager {

    /// 配置成可同时录音与播放。返回是否成功。
    @discardableResult
    static func activateForRecordAndPlayback() -> Bool {
        let s = AVAudioSession.sharedInstance()
        do {
            try s.setCategory(.playAndRecord, mode: .spokenAudio,
                              options: [.mixWithOthers, .defaultToSpeaker,
                                        .allowBluetooth])
            try s.setActive(true, options: [])
            return true
        } catch {
            NSLog("[Audio] 会话配置失败: \(error.localizedDescription)")
            return false
        }
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// 麦克风输入当前是否可用。`installTap` 之前必须查，
    /// 否则拿到采样率 0 的格式会崩。
    static var inputAvailable: Bool {
        AVAudioSession.sharedInstance().isInputAvailable
    }
}
