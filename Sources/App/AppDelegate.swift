import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    // 窗口由 SceneDelegate 创建 —— 采用 UIScene 才能拿到真正的全屏尺寸，
    // 否则 iOS 按兼容模式把窗口信箱化。
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions:
                     [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        true
    }
}
