// swift-tools-version:5.9
import PackageDescription

// 核心算法单独成包，这样能脱离 Xcode / 设备跑测试。
// App 目标（相机、PiP、语音）另建 Xcode 工程引用它。
let package = Package(
    name: "PrompterCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "PrompterCore", targets: ["PrompterCore"]),
    ],
    targets: [
        .target(name: "PrompterCore", path: "Sources/PrompterCore"),
        .testTarget(name: "PrompterCoreTests", dependencies: ["PrompterCore"],
                    path: "Tests/PrompterCoreTests"),
    ]
)
