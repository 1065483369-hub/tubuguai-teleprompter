import Foundation
import Speech
import AVFoundation

/// 语音识别 + 位置跟踪。用系统 SFSpeechRecognizer：
/// 中文支持好、可要求端上识别（requiresOnDeviceRecognition），
/// 不需要服务端中继，也不用把密钥放进 App。
///
/// 系统识别有个已知行为：会话会自行结束（静音、超时、限额），
/// 所以重启后必须调 Tracker.resync() 放宽窗口，否则光标会卡死。
final class SpeechTracker {

    /// partial 每次只喂尾部这么多字。Tracker 的匹配窗口是 12 个音节，
    /// 给 20 字左右的余量足够覆盖，再多就是稀释噪音。
    private static let partialTailChars = 20
    /// final 新增部分的上限。同理，关心的是"念到哪"而非"念过什么"。
    private static let finalTailChars = 30

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private var tracker: Tracker?
    private var index: ScriptIndex?
    private var tokens: [Token] = []
    private var lastFinalLength = 0    // 已计入 history 的 final 字符数

    /// (已读字符偏移, 预测字符偏移, 原因)
    var onPosition: ((Int, Int, String) -> Void)?
    var onHeard: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private(set) var isRunning = false
    private var isPaused = false

    func load(script: String) {
        tokens = tokenize(script)
        let idx = buildScriptIndex(tokens)
        index = idx
        tracker = Tracker(syllables: idx.syllables)
        lastFinalLength = 0
    }

    func requestPermission(_ done: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { auth in
            let granted = { (mic: Bool) in
                DispatchQueue.main.async { done(auth == .authorized && mic) }
            }
            // AVAudioApplication 是 iOS 17 才有的，低版本回落到 AVAudioSession
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission(completionHandler: granted)
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission(granted)
            }
        }
    }

    func start() {
        guard let recognizer, recognizer.isAvailable else {
            onError?("中文语音识别不可用（检查系统语言与网络）"); return
        }
        stopAudioOnly()

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // 不强制端上识别。中文端上模型常常没下载好，
        // requiresOnDeviceRecognition = true 时会静默不出任何结果——
        // 看起来就是「识别不了我说的话」。交给系统自己选。
        req.requiresOnDeviceRecognition = false
        // 口播是连续长句，告诉系统别按短命令来断句
        if #available(iOS 16.0, *) { req.addsPunctuation = false }
        req.taskHint = .dictation
        request = req

        // 必须先把会话配成可录音。若类别是 .playback（PiP 保活曾这么设），
        // inputNode 的格式采样率会是 0，installTap 直接抛 NSException 崩溃。
        guard AudioSessionManager.activateForRecordAndPlayback() else {
            onError?("音频会话不可用"); return
        }

        let node = engine.inputNode
        let format = node.outputFormat(forBus: 0)
        // 双保险：采样率或声道数为 0 说明没有可用输入（模拟器无麦克风、
        // 设备被别的 App 独占）。此时装 tap 必崩，直接报错退出。
        guard format.sampleRate > 0, format.channelCount > 0 else {
            onError?("麦克风不可用（模拟器可能没有音频输入）")
            return
        }

        // 注意：installTap 失败抛的是 NSException（Objective-C），
        // Swift 的 do/catch 接不住，所以上面的 format 校验才是真正的防线。
        //
        // 必须用 inputNode 的原生格式装 tap（否则抛异常），但 SFSpeech
        // 要 16kHz 单声道。硬件通常给 48kHz 立体声，直接 append 原始 buffer
        // 识别率会很差甚至没结果，所以中间加一层重采样。
        let target = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                   sampleRate: 16000, channels: 1, interleaved: true)
        let converter = target.flatMap { AVAudioConverter(from: format, to: $0) }
        node.installTap(onBus: 0, bufferSize: 2048, format: format) { buf, _ in
            guard let target, let converter else { req.append(buf); return }
            let ratio = target.sampleRate / format.sampleRate
            let cap = AVAudioFrameCount(Double(buf.frameLength) * ratio) + 1024
            guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: cap) else {
                req.append(buf); return
            }
            var fed = false
            var err: NSError?
            converter.convert(to: out, error: &err) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true
                status.pointee = .haveData
                return buf
            }
            if err == nil, out.frameLength > 0 { req.append(out) } else { req.append(buf) }
        }
        engine.prepare()
        do { try engine.start() } catch {
            engine.inputNode.removeTap(onBus: 0)
            onError?("麦克风启动失败：\(error.localizedDescription)"); return
        }
        isRunning = true

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                self.onHeard?(text)
                self.feed(text: text, isFinal: result.isFinal)
            }
            if let error {
                // 把真实错误报出来。之前静默重启，用户只看到「识别不了」。
                let ns = error as NSError
                // 1110 = 没听到语音（正常，静音超时）；203 = 服务不可用
                if ns.code != 1110 && ns.code != 216 {
                    self.onError?("识别中断：\(ns.localizedDescription)（\(ns.code)）")
                }
            }
            if error != nil || result?.isFinal == true {
                // 会话自然结束（静音/超时/限额）。重启并 resync，
                // 否则新会话的文本对不上旧位置，光标会永久卡死。
                if self.isRunning { self.restart() }
            }
        }
    }

    /// 系统识别每次回调给的是整段累积文本，而我们的 Tracker 要增量。
    /// 所以 final 时只喂新增的部分，partial 整段替换。
    private func feed(text: String, isFinal: Bool) {
        guard !isPaused else { return }        // 暂停期间不推进位置
        guard let tracker, let index else { return }
        let chars = Array(text)
        let syllables: [String]
        if isFinal {
            var fresh = lastFinalLength < chars.count
                ? String(chars[lastFinalLength...]) : ""
            // 新增部分也可能很长（一次 final 涵盖整段）。截尾部，
            // 因为 Tracker 关心的是"现在念到哪"，不是"刚才念过什么"。
            let f = Array(fresh)
            if f.count > Self.finalTailChars {
                fresh = String(f[(f.count - Self.finalTailChars)...])
            }
            syllables = textToSyllables(fresh)
            if syllables.isEmpty { return }
            // 只在真的吃下内容后才推进游标。原来这行写在 guard 之前：
            // 若某次 final 的累积文本比上一次短，游标会被拉回到更小的值，
            // 之后的 partial 会从那里重放已经计入 history 的内容，
            // 造成音节重复、位置被拽偏。
            lastFinalLength = max(lastFinalLength, chars.count)
        } else {
            // 只喂尾部一小段，不喂 lastFinalLength 之后的全部内容。
            // partial 是整句累积重写，会越来越长；而 Tracker 的匹配窗口
            // 只看最后十几个音节，多余的部分纯粹是噪音，会把位置拖死。
            // 实测喂整条尾巴时，超过 ~57 音节后光标永久卡住。
            let recent = chars.count > Self.partialTailChars
                ? String(chars[(chars.count - Self.partialTailChars)...])
                : String(chars)
            syllables = textToSyllables(recent)
        }
        let r = tracker.update(syllables: syllables, isFinal: isFinal)
        let anchorChar = charOffset(forSyllable: r.anchor, index: index)
        let softChar = charOffset(forSyllable: r.soft, index: index)
        DispatchQueue.main.async { self.onPosition?(anchorChar, softChar, r.reason) }
    }

    private func charOffset(forSyllable pos: Int, index: ScriptIndex) -> Int {
        if pos <= 0 { return 0 }
        if pos >= index.sylToToken.count { return tokens.last?.end ?? 0 }
        return tokens[index.sylToToken[pos]].start
    }

    private func restart() {
        stopAudioOnly()
        lastFinalLength = 0
        tracker?.resync()          // 关键：放宽窗口，让光标重新咬住位置
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.isRunning else { return }
            self.start()
        }
    }

    private func stopAudioOnly() {
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
    }

    func stop() {
        isRunning = false
        stopAudioOnly()
    }

    /// 暂停：只停止喂词给对齐引擎，识别任务和麦克风都留着。
    /// 不拆会话是关键 —— 重启 ASR 会有明显空档，"继续"就不无缝了。
    func pause() { isPaused = true }

    func resume() {
        isPaused = false
        // 暂停期间说的话不该被计入。清掉累积游标，
        // 让恢复后的第一条 partial 从当前位置重新咬。
        tracker?.resync()
        lastFinalLength = 0
    }

    /// 手动点词后校准
    func seek(toChar char: Int) {
        guard let tracker, let index else { return }
        var ti = tokens.firstIndex { $0.start >= char } ?? tokens.count
        ti = min(ti, index.tokenToSyl.count - 1)
        tracker.seek(index.tokenToSyl[ti])
        lastFinalLength = 0
    }
}
