import Foundation

struct SavedRecipeItem: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var text: String
    var createdAt: Int64

    init(id: String = UUID().uuidString, title: String, text: String, createdAt: Int64 = Int64(Date().timeIntervalSince1970)) {
        self.id = id
        self.title = title
        self.text = text
        self.createdAt = createdAt
    }
}

enum SavedRecipesStore {
    private static let fileName = "saved_recipes_v1.json"

    private static func fileURL(userId: String) -> URL? {
        let fm = FileManager.default
        guard let support = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            return nil
        }

        let uidTrimmed = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        let uid = uidTrimmed.isEmpty ? UserSessionStore.defaultUserId : uidTrimmed

        let dir = support
            .appendingPathComponent("users", isDirectory: true)
            .appendingPathComponent(uid, isDirectory: true)

        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    static func load(userId: String) -> [SavedRecipeItem] {
        guard let url = fileURL(userId: userId) else { return [] }
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let decoded = try? JSONDecoder().decode([SavedRecipeItem].self, from: data) else { return [] }
        return decoded.sorted { $0.createdAt > $1.createdAt }
    }

    static func add(userId: String, item: SavedRecipeItem) {
        var items = load(userId: userId)
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        save(userId: userId, items: items)
    }

    static func delete(userId: String, id: String) {
        var items = load(userId: userId)
        items.removeAll { $0.id == id }
        save(userId: userId, items: items)
    }

    private static func save(userId: String, items: [SavedRecipeItem]) {
        guard let url = fileURL(userId: userId) else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    // MARK: - Cloud stubs (optional)

    static func refreshFromCloud(userId: String) async -> [SavedRecipeItem] {
        // Пока просто возвращаем локальные данные.
        return load(userId: userId)
    }

    static func upsertToCloud(userId: String, item: SavedRecipeItem) async {
        // no-op by default
        _ = userId
        _ = item
    }

    static func deleteFromCloud(userId: String, id: String) async {
        // no-op by default
        _ = userId
        _ = id
    }
}
