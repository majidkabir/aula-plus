import EventKit
import EventKitUI
import SwiftUI

/// Apple's own "new event" sheet, prefilled. Since iOS 17 this needs no
/// calendar permission: the sheet runs outside the app.
struct AddToCalendarSheet: UIViewControllerRepresentable {
    let event: Event
    let childNames: [String]
    @Environment(\.dismiss) private var dismiss

    private static let store = EKEventStore()

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: { dismiss() }) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let vc = EKEventEditViewController()
        vc.eventStore = Self.store
        let e = EKEvent(eventStore: Self.store)
        e.title = childNames.isEmpty ? event.title : "\(event.title) (\(childNames.joined(separator: ", ")))"
        e.startDate = event.start
        e.endDate = event.end > event.start ? event.end : event.start.addingTimeInterval(3600)
        e.isAllDay = event.allDay
        e.location = event.location
        e.notes = [event.teacher.map { "Lærer: \($0)" }, event.substitute.map { "Vikar: \($0)" }]
            .compactMap { $0 }.joined(separator: "\n")
        vc.event = e
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let dismiss: () -> Void
        init(dismiss: @escaping () -> Void) { self.dismiss = dismiss }
        func eventEditViewController(_ controller: EKEventEditViewController,
                                     didCompleteWith action: EKEventEditViewAction) {
            dismiss()
        }
    }
}
