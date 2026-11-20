import AppIntents
import Foundation

/// A child, as the widgets and Siri know it (read from the app-group snapshot).
struct ChildEntity: AppEntity, Identifiable, Hashable {
    let id: Int
    let name: String

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Barn")
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    static let defaultQuery = ChildQuery()
}

struct ChildQuery: EntityQuery {
    private func all() -> [ChildEntity] {
        (WidgetSnapshot.load()?.children ?? []).compactMap { c in c.id.map { ChildEntity(id: $0, name: c.name) } }
    }
    func entities(for identifiers: [Int]) async throws -> [ChildEntity] {
        all().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [ChildEntity] { all() }
}

/// What a widget shows.
enum WidgetContent: String, AppEnum {
    case overview, status, events, todos, messages

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Indhold")
    static let caseDisplayRepresentations: [WidgetContent: DisplayRepresentation] = [
        .overview: DisplayRepresentation(title: "Overblik", image: .init(systemName: "square.grid.2x2")),
        .status: DisplayRepresentation(title: "Komme/gå-status", image: .init(systemName: "figure.walk")),
        .events: DisplayRepresentation(title: "Næste begivenheder", image: .init(systemName: "calendar")),
        .todos: DisplayRepresentation(title: "Husk", image: .init(systemName: "checklist")),
        .messages: DisplayRepresentation(title: "Ulæste beskeder", image: .init(systemName: "bubble.left.fill")),
    ]
}

/// Widget settings: which child (or all) and what to show.
struct ConfigureAulaWidget: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Aula+ widget"
    static let description = IntentDescription("Vælg barn og hvad widgetten viser.")

    @Parameter(title: "Barn", description: "Tom = alle børn")
    var child: ChildEntity?

    @Parameter(title: "Vis", default: .overview)
    var content: WidgetContent

    init() {}
}

extension WidgetSnapshot {
    /// The children a widget or Siri answer is about.
    func children(for child: ChildEntity?) -> [ChildLine] {
        guard let child else { return children }
        return children.filter { $0.id == child.id }
    }

    /// Coming events for these children, soonest first, without duplicates.
    func events(for lines: [ChildLine]) -> [(child: String, event: EventLine)] {
        var seen = Set<String>()
        return lines.flatMap { c in (c.events ?? []).map { (c.name, $0) } }
            .sorted { $0.1.start < $1.1.start }
            .filter { seen.insert("\($0.1.title)|\($0.1.start.timeIntervalSince1970)").inserted }
            .map { (child: $0.0, event: $0.1) }
    }
}
