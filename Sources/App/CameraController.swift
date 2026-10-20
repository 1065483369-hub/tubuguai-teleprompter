import AVFoundation
import UIKit
import Photos

/// App 内相机取景与录制。用 AVCaptureSession 走系统采集，
/// 画质和防抖都是原生级别，比网页里的 MediaRecorder 强。
///
/// 提词文字不参与录制——它是给你看的，不该进成片。
final class CameraController: NSObject {

    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private let queue = DispatchQueue(label: "camera.session")

    var isRecording: Bool { movieOutput.isRecording }
    var onRecordFinished: ((URL?, Error?) -> Void)?
    private(set) var position: AVCaptureDevice.Position = .front

    /// 配置会话。麦克风是否接进来由 useMic 决定：
    /// 语音识别独占麦克风时不要重复占用，否则会互相打断。
    func configure(useMic: Bool) {
        queue.async { [self] in
            session.beginConfiguration()
            session.sessionPreset = .high

            if let cur = videoInput { session.removeInput(cur); videoInput = nil }
            if let device = camera(for: position),
               let input = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(input) {
                session.addInput(input)
                videoInput = input
            }

            if useMic, audioInput == nil,
               let mic = AVCaptureDevice.default(for: .audio),
               let input = try? AVCaptureDeviceInput(device: mic),
               session.canAddInput(input) {
                session.addInput(input)
                audioInput = input
            } else if !useMic, let a = audioInput {
                session.removeInput(a); audioInput = nil
            }

            if !session.outputs.contains(movieOutput), session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            }
            session.commitConfiguration()
        }
    }

    private func camera(for pos: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video, position: pos
        ).devices.first
    }

    func start() { queue.async { [self] in if !session.isRunning { session.startRunning() } } }
    func stop() { queue.async { [self] in if session.isRunning { session.stopRunning() } } }

    func flip(useMic: Bool) {
        position = position == .front ? .back : .front
        configure(useMic: useMic)
    }

    func startRecording() {
        guard !movieOutput.isRecording else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("prompt-\(Int(Date().timeIntervalSince1970)).mov")

        if let c = movieOutput.connection(with: .video) {
            // 前置摄像头录出来默认是镜像反的，人看着别扭
            if c.isVideoMirroringSupported {
                c.automaticallyAdjustsVideoMirroring = false
                c.isVideoMirrored = (position == .front)
            }
            // 方向必须显式设置。用户抱怨「横屏录制录出来的是竖屏视频」——
            // AVCaptureConnection 默认不跟设备方向转，不设就永远按固定方向录。
            if #available(iOS 17.0, *) {
                let angle = Self.rotationAngle(for: UIDevice.current.orientation)
                if c.isVideoRotationAngleSupported(angle) {
                    c.videoRotationAngle = angle
                }
            } else if c.isVideoOrientationSupported {
                c.videoOrientation = Self.legacyOrientation(UIDevice.current.orientation)
            }
        }
        movieOutput.startRecording(to: url, recordingDelegate: self)
    }

    /// 设备方向 → 视频旋转角（iOS 17+ 的新 API）。
    private static func rotationAngle(for o: UIDeviceOrientation) -> CGFloat {
        switch o {
        case .landscapeLeft:      return 0      // home 键在右
        case .landscapeRight:     return 180
        case .portraitUpsideDown: return 270
        default:                  return 90     // 竖屏（含 faceUp/unknown）
        }
    }

    private static func legacyOrientation(_ o: UIDeviceOrientation) -> AVCaptureVideoOrientation {
        switch o {
        case .landscapeLeft:      return .landscapeRight   // 注意是反的
        case .landscapeRight:     return .landscapeLeft
        case .portraitUpsideDown: return .portraitUpsideDown
        default:                  return .portrait
        }
    }

    func stopRecording() {
        guard movieOutput.isRecording else { return }
        movieOutput.stopRecording()
    }

    /// 存进相册。需要 NSPhotoLibraryAddUsageDescription。
    func saveToPhotos(_ url: URL, done: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { done(false); return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { ok, _ in
                DispatchQueue.main.async { done(ok) }
            }
        }
    }
}

extension CameraController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.onRecordFinished?(error == nil ? outputFileURL : nil, error)
        }
    }
}
