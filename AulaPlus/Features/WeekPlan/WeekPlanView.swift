import SwiftUI

struct WeekPlanView: View {
    @Environment(AppModel.self) private var app
    @Environment(DataStore.self) private var data
    @State private var weekDate = Date.now

    private var plan: Loadable<[WeekPlan]> { data.weekPlan(weekOf: weekDate) }
    private var tasks: Loadable<[SchoolTask]> { data.schoolTasks(weekOf: weekDate) }

    private var visibleTasks: [SchoolTask] {
        let all = tasks.value ?? []
        guard let id = app.selectedChildId, let child = app.child(id) else { return all }
        return all.filter { $0.childName.isEmpty || $0.childName.localizedCaseInsensitiveContains(child.firstName) }
    }

    private var supported: Bool {
        let w = app.session.value?.widgetIds ?? []
        return w.contains(AulaConfig.Widget.meebook)
            || w.contains(AulaConfig.Widget.muUgeplan)
            || w.contains(AulaConfig.Widget.muSSO)
    }

    private var visiblePlans: [WeekPlan] {
        let plans = plan.value ?? []
        guard let id = app.selectedChildId, let child = app.child(id) else { return plans }
        return plans.filter { $0.childName.isEmpty || $0.childName.localizedCaseInsensitiveContains(child.firstName) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ChildFilterBar().padding(.horizontal, -Theme.pad)
                    WeekSwitcher(date: $weekDate).cardStyle(padding: 6)
                    StaleBanner(error: plan.error, savedAt: plan.savedAt)

                    if !visibleTasks.isEmpty {
                        HStack(alignment: .center) {
                            SectionTitle(title: "Opgaver", systemImage: "checklist", tint: .green)
                            ProgressRing(done: visibleTasks.filter(\.isDone).count, total: visibleTasks.count, color: .green)
                        }
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(visibleTasks) { t in TaskRow(task: t, showChild: app.children.count > 1) }
                            }
                        }
                    }

                    if !supported && app.session.value != nil && visibleTasks.isEmpty {
                        ContentUnavailableView("Ugeplan ikke understøttet endnu",
                                               systemImage: "puzzlepiece.extension",
                                               description: Text("Din skole bruger en ugeplan-udbyder, som Aula+ ikke kender endnu (understøtter Meebook og Min Uddannelse)."))
                    } else if visiblePlans.allSatisfy({ $0.sections.isEmpty }) {
                        if plan.isLoading { ProgressView().frame(maxWidth: .infinity).padding(.top, 40) }
                        else { ContentUnavailableView("Ingen ugeplan for denne uge", systemImage: "doc.text") }
                    }

                    ForEach(visiblePlans, id: \.self) { p in
                        if !p.sections.isEmpty {
                            if !p.childName.isEmpty {
                                SectionTitle(title: "\(p.childName)", systemImage: "doc.richtext.fill")
                            }
                            ForEach(p.sections, id: \.self) { s in
                                Card {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(s.title).font(.headline).foregroundStyle(Color.brand)
                                        HTMLText(html: s.html)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .themedBackground()
            .navigationTitle("Ugeplan")
            .refreshable {
                async let a: () = plan.refresh()
                async let b: () = tasks.refresh()
                _ = await (a, b)
            }
            .task(id: Week.key(weekDate)) {
                async let a: () = plan.load(maxAge: 1800)
                async let b: () = tasks.load(maxAge: 1800)
                _ = await (a, b)
            }
        }
    }

    private func shift(_ days: Int) {
        weekDate = Calendar.week.date(byAdding: .day, value: days, to: weekDate) ?? weekDate
    }
}

struct TaskRow: View {
    let task: SchoolTask
    let showChild: Bool

    private var meta: String {
        var parts: [String] = []
        if let s = task.subject { parts.append(s) }
        if let d = task.due { parts.append(String(localized: "Afleveres \(d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")) }
        else if let w = task.weekday { parts.append(w) }
        if showChild, let first = task.childName.split(separator: " ").first { parts.append(String(first)) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(task.isDone ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).font(.body.weight(.medium))
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? Color.secondary : Color.primary)
                if !meta.isEmpty {
                    Text(meta).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(task.isDone ? "Færdig" : "Ikke færdig"))
    }
}
