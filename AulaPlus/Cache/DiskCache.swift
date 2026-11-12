import Foundation

/// Tiny JSON-on-disk cache: screens render the last known data instantly,
/// then refresh in the background (stale-while-revalidate).
/// Stored in Caches/ with complete file protection; wiped on logout.
enum DiskCache {
    private static let dir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("aula", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private struct Box<T: Codable>: Codable {
        let savedAt: Date
        let value: T
    }

    private static func url(_ key: String) -> URL {
        let safe = key.replacingOccurrences(of: #"[^A-Za-z0-9_.-]"#, with: "_", options: .regularExpression)
        return dir.appendingPathComponent(safe + ".json")
    }

    static func load<T: Codable>(_ type: T.Type, key: String) -> (value: T, savedAt: Date)? {
        guard let data = try? Data(contentsOf: url(key)),
              let box = try? JSONDecoder().decode(Box<T>.self, from: data) else { return nil }
        return (box.value, box.savedAt)
    }

    static func save<T: Codable>(_ value: T, key: String) {
        let box = Box(savedAt: Date(), value: value)
        guard let data = try? JSONEncoder().encode(box) else { return }
        try? data.write(to: url(key), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func clear() {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
