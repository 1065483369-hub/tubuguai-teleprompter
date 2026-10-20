import XCTest
@testable import Prompter

final class ScriptHistoryTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: ScriptHistoryStore!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ScriptHistoryTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = ScriptHistoryStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        suiteName = nil
        super.tearDown()
    }

    func testEmptyTextIsNotSaved() {
        XCTAssertNil(store.save(" \n "))
        XCTAssertTrue(store.all().isEmpty)
    }

    func testNewestScriptComesFirst() {
        store.save("第一篇稿子", now: Date(timeIntervalSince1970: 1))
        store.save("第二篇稿子", now: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(store.all().map(\.text), ["第二篇稿子", "第一篇稿子"])
    }

    func testDuplicateTextRefreshesInsteadOfDuplicating() {
        let first = store.save("同一篇稿子", now: Date(timeIntervalSince1970: 1))
        let second = store.save("\n同一篇稿子\n", now: Date(timeIntervalSince1970: 9))
        XCTAssertEqual(store.all().count, 1)
        XCTAssertEqual(first?.id, second?.id)
        XCTAssertEqual(store.all().first?.updatedAt, Date(timeIntervalSince1970: 9))
    }

    func testDeleteAndClear() {
        let item = store.save("准备删除")!
        store.save("保留一下")
        store.delete(id: item.id)
        XCTAssertEqual(store.all().map(\.text), ["保留一下"])
        store.removeAll()
        XCTAssertTrue(store.all().isEmpty)
    }

    func testKeepsOnlyThirtyMostRecentScripts() {
        for i in 0..<35 {
            store.save("稿子 \(i)", now: Date(timeIntervalSince1970: TimeInterval(i)))
        }
        XCTAssertEqual(store.all().count, 30)
        XCTAssertEqual(store.all().first?.text, "稿子 34")
        XCTAssertEqual(store.all().last?.text, "稿子 5")
    }

    func testTitleUsesFirstLineAndTruncates() {
        let item = ScriptHistoryItem(id: UUID(),
            text: "这是一个非常非常非常非常非常长的稿子标题\n第二行", updatedAt: Date())
        XCTAssertEqual(item.title, "这是一个非常非常非常非常非常长…")
    }
}
