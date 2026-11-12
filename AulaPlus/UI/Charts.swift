import Charts
import SwiftUI

private func timeOn(_ hhmm: String?, _ day: Date) -> Date? {
    guard let hhmm, AulaDate.shortTime(hhmm) != nil else { return nil }
    return DayPlanEditor.time(hhmm, on: day)
}

/// One-line timeline of a child's day: time at the institution, lessons, and "now".
struct DayTimeline: View {
    let presence: Presence?
    let events: [Event]
    let color: Color

    private var day: Date { Calendar.week.startOfDay(for: .now) }
    private var stay: (Date, Date)? {
        guard let p = presence,
              let start = timeOn(p.checkIn ?? p.plannedEntry, day),
              let end = timeOn(p.checkOut ?? p.plannedExit, day), end > start else { return nil }
        return (start, end)
    }
    private var domain: ClosedRange<Date> {
        let starts = events.map(\.start) + [stay?.0].compactMap { $0 }
        let ends = events.map(\.end) + [stay?.1].compactMap { $0 }
        let cal = Calendar.week
        let lo = min(starts.min() ?? cal.date(bySettingHour: 8, minute: 0, second: 0, of: day)!,
                     cal.date(bySettingHour: 8, minute: 0, second: 0, of: day)!)
        let hi = max(ends.max() ?? cal.date(bySettingHour: 16, minute: 0, second: 0, of: day)!,
                     cal.date(bySettingHour: 16, minute: 0, second: 0, of: day)!)
        let floor = cal.date(bySettingHour: cal.component(.hour, from: lo), minute: 0, second: 0, of: day)!
        let ceil = cal.date(bySettingHour: min(cal.component(.hour, from: hi) + 1, 23), minute: 0, second: 0, of: day)!
        return floor...ceil
    }

    var body: some View {
        let now = Date()
        Chart {
            if let st = stay {
                let s = st.0, e = st.1
                BarMark(xStart: .value("Fra", s), xEnd: .value("Til", e), y: .value("Række", "Dag"), height: 10)
                    .foregroundStyle(color.opacity(0.22))
                    .cornerRadius(9)
                if now > s {
                    BarMark(xStart: .value("Fra", s), xEnd: .value("Til", min(now, e)), y: .value("Række", "Dag"), height: 10)
                        .foregroundStyle(color.gradient)
                        .cornerRadius(9)
                }
            }
            ForEach(events) { ev in
                BarMark(xStart: .value("Fra", ev.start), xEnd: .value("Til", ev.end), y: .value("Række", "Skema"), height: 14)
                    .foregroundStyle(ev.end < now ? color.opacity(0.35) : color)
                    .cornerRadius(4)
            }
            if domain.contains(now) {
                RuleMark(x: .value("Nu", now))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
        .chartXScale(domain: domain)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .frame(height: events.isEmpty ? 40 : 58)
        .accessibilityElement()
        .accessibilityLabel(Text("Tidslinje for dagen"))
        .accessibilityValue(Text(stay.map { "\(Fmt.time($0.0)) – \(Fmt.time($0.1))" } ?? ""))
    }
}

/// The week's drop-off → pick-up ranges as horizontal bars, one per weekday.
struct WeekPlanChart: View {
    let plans: [DayPlan]
    let days: [Date]
    let color: Color

    private struct Row: Identifiable {
        let id: Date
        let label: String
        let start: Date
        let end: Date
        let vacation: Bool
    }

    /// All times are placed on one reference day so the x-axis is time of day.
    private static let ref = Calendar.week.startOfDay(for: Date(timeIntervalSince1970: 0))

    private var rows: [Row] {
        days.compactMap { d in
            let label = d.formatted(.dateTime.weekday(.abbreviated)).capitalized
            guard let p = plans.first(where: { Calendar.week.isDate($0.date, inSameDayAs: d) }) else { return nil }
            if p.isOnVacation {
                return Row(id: d, label: label, start: DayPlanEditor.time("08:00", on: Self.ref),
                           end: DayPlanEditor.time("16:00", on: Self.ref), vacation: true)
            }
            guard let e = p.entry, let x = p.exit else { return nil }
            return Row(id: d, label: label, start: DayPlanEditor.time(e, on: Self.ref),
                       end: DayPlanEditor.time(x, on: Self.ref), vacation: false)
        }
    }

    var body: some View {
        Chart(rows) { r in
            BarMark(xStart: .value("Afleveres", r.start), xEnd: .value("Hentes", r.end), y: .value("Dag", r.label), height: 18)
                .foregroundStyle(r.vacation ? AnyShapeStyle(Color.orange.opacity(0.35)) : AnyShapeStyle(color.gradient))
                .cornerRadius(9)
                .annotation(position: .trailing, spacing: 4) {
                    Text(r.vacation ? String(localized: "Fri") : Fmt.time(r.end))
                        .font(.caption2.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
        }
        .chartXScale(domain: DayPlanEditor.time("06:00", on: Self.ref)...DayPlanEditor.time("18:30", on: Self.ref))
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .frame(height: CGFloat(max(rows.count, 1)) * 30 + 24)
        .accessibilityElement(children: .combine)
    }
}

/// Small circular progress for tasks done.
struct ProgressRing: View {
    let done: Int
    let total: Int
    var color: Color = .green
    var size: CGFloat = 44

    var body: some View {
        let fraction = total == 0 ? 0 : Double(done) / Double(total)
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: 5)
            Circle().trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(done)/\(total)").font(.caption2.weight(.bold)).monospacedDigit()
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(Text("\(done) af \(total) færdige"))
    }
}
