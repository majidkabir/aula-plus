import Foundation

/// Small summary the app writes for the widgets and Siri (via the app group).
struct WidgetSnapshot: Codable {
    struct EventLine: Codable, Hashable {
        let title: String
        let start: Date
        let allDay: Bool
    }

    struct ChildLine: Codable, Hashable {
        let name: String
        let status: String?
        let symbol: String?
        let detail: String?
        let colorIndex: Int
        /// Institution profile id (for choosing a child in a widget or in Siri).
        var id: Int? = nil
        /// Coming events for this child, soonest first (next 7 days).
        var events: [EventLine]? = nil
    }

    struct TaskLine: Codable, Hashable {
        let title: String
        let due: Date?
    }

    struct MessageLine: Codable, Hashable {
        let sender: String
        let subject: String
    }

    var children: [ChildLine]
    var unread: Int
    var latestSender: String?
    var latestSubject: String?
    var updated: Date
    var theme: String? = nil
    /// Open "To do" items, soonest first.
    var tasks: [TaskLine]? = nil
    /// Newest unread messages.
    var unreadMessages: [MessageLine]? = nil

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
            .init(name: "Emma", status: "Til stede", symbol: "checkmark.circle.fill", detail: "Hentes 15:30", colorIndex: 0,
                  id: 1, events: [.init(title: "Skovtur", start: .now.addingTimeInterval(86_400), allDay: false)]),
            .init(name: "Noah", status: "Ikke kommet", symbol: "circle.dashed", detail: "Matematik 08:00", colorIndex: 1,
                  id: 2, events: [.init(title: "Matematik", start: .now.addingTimeInterval(3_600), allDay: false)]),
        ],
        unread: 2, latestSender: "Lærer", latestSubject: "Tur i morgen", updated: .now,
        tasks: [.init(title: "Medbring gummistøvler", due: .now.addingTimeInterval(86_400)),
                .init(title: "Tilmeld juletræsfest", due: nil)],
        unreadMessages: [.init(sender: "Lærer", subject: "Tur i morgen")])

    func child(_ id: Int?) -> ChildLine? {
        guard let id else { return nil }
        return children.first { $0.id == id }
    }
}
