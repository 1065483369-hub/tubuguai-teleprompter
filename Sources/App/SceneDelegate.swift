import UIKit

/// UIScene 生命周期。不采用 Scene 的 App 会被 iOS 按兼容模式运行 ——
/// 窗口被信箱化成 402x603（2:3 比例），上下各留 135pt 黑边。
/// 这就是"整个 App 的比例是 3:4"的原因。
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let w = UIWindow(windowScene: windowScene)
        w.rootViewController = PrompterViewController()
        w.makeKeyAndVisible()
        window = w
    }
}
