import XCTest

/// App 名称与图标的回归。
///
/// 图标那条尤其值得守：iOS 的 App 图标**不能带透明通道**，
/// 带了会在主屏渲染成黑底或白角。素材从设计稿导出时常常是透明底 PNG，
/// 很容易直接塞进 asset catalog 就完事。
final class BrandingTests: XCTestCase {

    private var bundle: Bundle { Bundle(for: BrandingTests.self) }

    func testDisplayName() {
        // 测试 bundle 读不到主 App 的 Info.plist，直接读源文件断言
        let yml = projectFile("project.yml")
        XCTAssertTrue(yml.contains("CFBundleDisplayName: 兔不乖的提词器"),
                      "App 显示名应为「兔不乖的提词器」")
    }

    func testAppIconIsOpaque1024() throws {
        let path = projectPath("Assets.xcassets/AppIcon.appiconset/icon-1024.png")
        let data = try Data(contentsOf: URL(fileURLWithPath: path))

        // PNG 签名
        XCTAssertEqual([UInt8](data.prefix(4)), [0x89, 0x50, 0x4E, 0x47], "不是 PNG")

        // IHDR: width(16..20) height(20..24) bitDepth(24) colorType(25)
        let width = data.subdata(in: 16..<20).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let height = data.subdata(in: 20..<24).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let colorType = data[25]

        XCTAssertEqual(width, 1024, "App 图标必须 1024x1024")
        XCTAssertEqual(height, 1024, "App 图标必须 1024x1024")
        // 0=灰度 2=RGB 3=索引 4=灰度+alpha 6=RGBA
        XCTAssertFalse(colorType == 4 || colorType == 6,
                       "App 图标不能带透明通道（colorType=\(colorType)），主屏会出现黑底或白角")
    }

    func testAppIconIsRegisteredInAssetCatalog() throws {
        let json = projectFile("Assets.xcassets/AppIcon.appiconset/Contents.json")
        XCTAssertTrue(json.contains("icon-1024.png"), "asset catalog 未引用图标文件")
        let yml = projectFile("project.yml")
        XCTAssertTrue(yml.contains("ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon"),
                      "构建设置未指定 AppIcon")
    }

    // MARK: -

    /// 从测试 bundle 往上找工程根目录。测试进程的 cwd 不可靠。
    private func projectRoot() -> String {
        var dir = URL(fileURLWithPath: #filePath)   // .../Prompter/Tests/AppTests/BrandingTests.swift
            .deletingLastPathComponent()            // AppTests
            .deletingLastPathComponent()            // Tests
            .deletingLastPathComponent()            // Prompter
        // 防御：万一层级变了，往上找到含 project.yml 的目录
        for _ in 0..<4 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("project.yml").path) {
                return dir.path
            }
            dir = dir.deletingLastPathComponent()
        }
        return dir.path
    }

    private func projectPath(_ rel: String) -> String {
        (projectRoot() as NSString).appendingPathComponent(rel)
    }

    private func projectFile(_ rel: String) -> String {
        (try? String(contentsOfFile: projectPath(rel), encoding: .utf8)) ?? ""
    }
}
