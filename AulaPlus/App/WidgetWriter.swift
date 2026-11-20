import Foundation
import WidgetKit

/// Writes the widget snapshot from the app's current data and reloads widgets.
@MainActor
enum WidgetWriter {
    static func update() {
        let app = AppModel.shared
        let data = DataStore.shared
        let today = data.events(weekOf: .now).value ?? []
        let week = (today + (data.events(weekOf: .now.addingTimeInterval(7 * 86_400)).value ?? []))
            .filter { $0.end > .now && $0.start < .now.addingTimeInterval(7 * 86_400) }
            .sorted { $0.start < $1.start }
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
            let coming = week.filter { $0.childIds.isEmpty || $0.childIds.contains(child.id) }.prefix(5)
                .map { WidgetSnapshot.EventLine(title: $0.title, start: $0.start, allDay: $0.allDay) }
            return .init(name: child.firstName, status: off ? nil : p?.status?.label, symbol: off ? "sun.max.fill" : p?.status?.symbol,
                         detail: detail, colorIndex: i, id: child.id, events: Array(coming))
        }
        let threads = data.threads.value ?? []
        let latestUnread = threads.first { !$0.isRead }
        let tasks = ParentTaskFinder.shared.isEnabled ? ParentTaskFinder.shared.open.prefix(6)
            .map { WidgetSnapshot.TaskLine(title: $0.title, due: $0.due) } : []
        let unreadLines = threads.filter { !$0.isRead }.prefix(5)
            .map { WidgetSnapshot.MessageLine(sender: $0.sender, subject: $0.subject) }
        WidgetSnapshot(children: lines, unread: threads.filter { !$0.isRead }.count,
                       latestSender: latestUnread?.sender, latestSubject: latestUnread?.subject,
                       updated: .now, theme: ThemeStore.shared.theme.rawValue,
                       tasks: Array(tasks), unreadMessages: Array(unreadLines)).save()
        WidgetCenter.shared.reloadAllTimelines()
        AulaShortcuts.updateAppShortcutParameters()   // Siri learns the children's names
    }
}
