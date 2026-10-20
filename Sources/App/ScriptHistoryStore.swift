import Foundation

/// 本机稿子历史。只保存用户明确点过「完成」的稿子，避免把半截输入、
/// 剪贴板误粘内容也悄悄写进历史。相同正文只保留一份并更新最近使用时间。
struct ScriptHistoryItem: Codable, Equatable, Identifiable {
    let id: UUID
    var text: String
    var updatedAt: Date

    var title: String {
        let first = text.split(whereSeparator: \.isNewline)
            .first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "未命名稿子"
        guard first.count > 18 else { return first.isEmpty ? "未命名稿子" : first }
        return String(first.prefix(18)) + "…"
    }

    var preview: String {
        text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class ScriptHistoryStore {
    static let shared = ScriptHistoryStore()
    static let storageKey = "prompter.scriptHistory.v1"
    static let limit = 30

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func all() -> [ScriptHistoryItem] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? decoder.decode([ScriptHistoryItem].self, from: data)
        else { return [] }
        return decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    func save(_ rawText: String, now: Date = Date()) -> ScriptHistoryItem? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        var items = all()
        let normalized = Self.normalized(text)
        if let old = items.first(where: { Self.normalized($0.text) == normalized }) {
            items.removeAll { $0.id == old.id }
            let refreshed = ScriptHistoryItem(id: old.id, text: text, updatedAt: now)
            items.insert(refreshed, at: 0)
            persist(Array(items.prefix(Self.limit)))
            return refreshed
        }

        let item = ScriptHistoryItem(id: UUID(), text: text, updatedAt: now)
        items.insert(item, at: 0)
        persist(Array(items.prefix(Self.limit)))
        return item
    }

    func delete(id: UUID) {
        persist(all().filter { $0.id != id })
    }

    func removeAll() {
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func persist(_ items: [ScriptHistoryItem]) {
        guard let data = try? encoder.encode(items) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r\n", with: "\n")
    }
}
