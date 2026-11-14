import Foundation
import WidgetKit

/// Writes the widget snapshot from the app's current data and reloads widgets.
@MainActor
enum WidgetWriter {
    static func update() {
        let app = AppModel.shared
        let data = DataStore.shared
        let today = data.events(weekOf: .now).value ?? []
        let lines: [WidgetSnapshot.ChildLine] = app.children.enumerated().map { i, child in
            let p = data.presence.value?.first { $0.childId == child.id }
            let next = today.first {
                !$0.allDay && $0.end > .now && Calendar.week.isDateInToday($0.start)
                    && ($0.childIds.isEmpty || $0.childIds.contains(child.id))
            }
            var detail: String?
            if p?.isDayOff == true { detail = String(localized: Calendar.week.isDateInWeekend(.now) ? "Weekend" : "Fri i dag") }
            else if let exit = p?.plannedExit, p?.checkOut == nil, exit != "23:59" { detail = String(localized: "Hentes \(exit)") }
            else if let next { detail = "\(next.title) \(Fmt.time(next.start))" }
            let off = p?.isDayOff == true
            return .init(name: child.firstName, status: off ? nil : p?.status?.label, symbol: off ? "sun.max.fill" : p?.status?.symbol,
                         detail: detail, colorIndex: i)
        }
        let threads = data.threads.value ?? []
        let latestUnread = threads.first { !$0.isRead }
        WidgetSnapshot(children: lines, unread: threads.filter { !$0.isRead }.count,
                       latestSender: latestUnread?.sender, latestSubject: latestUnread?.subject,
                       updated: .now, theme: ThemeStore.shared.theme.rawValue).save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
