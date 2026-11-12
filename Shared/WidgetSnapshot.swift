import Foundation

/// Small summary the app writes for the home-screen widget (via the app group).
struct WidgetSnapshot: Codable {
    struct ChildLine: Codable, Hashable {
        let name: String
        let status: String?
        let symbol: String?
        let detail: String?
        let colorIndex: Int
    }

    var children: [ChildLine]
    var unread: Int
    var latestSender: String?
    var latestSubject: String?
    var updated: Date

    static let appGroup = "group.com.majidkabir.aulaplus"

    private static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("widget.json")
    }

    static func load() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let url = Self.url, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static let placeholder = WidgetSnapshot(
        children: [
            .init(name: "Emma", status: "Til stede", symbol: "checkmark.circle.fill", detail: "Hentes 15:30", colorIndex: 0),
            .init(name: "Noah", status: "Ikke kommet", symbol: "circle.dashed", detail: "Matematik 08:00", colorIndex: 1),
        ],
        unread: 2, latestSender: "Lærer", latestSubject: "Tur i morgen", updated: .now)
}
