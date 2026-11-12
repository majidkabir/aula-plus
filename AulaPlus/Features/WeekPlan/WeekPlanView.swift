import SwiftUI

struct WeekPlanView: View {
    @Environment(AppModel.self) private var app
    @Environment(DataStore.self) private var data
    @State private var weekDate = Date.now

    private var plan: Loadable<[WeekPlan]> { data.weekPlan(weekOf: weekDate) }

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
                    ChildFilterBar().padding(.horizontal, -16)
                    weekSwitcher
                    StaleBanner(error: plan.error, savedAt: plan.savedAt)

                    if !supported && app.session.value != nil {
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
                                Text(p.childName).font(.title3.bold()).padding(.top, 6)
                            }
                            ForEach(p.sections, id: \.self) { s in
                                Card {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(s.title).font(.headline)
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
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Ugeplan")
            .refreshable { await plan.refresh() }
            .task(id: Week.key(weekDate)) { await plan.load(maxAge: 1800) }
        }
    }

    private var weekSwitcher: some View {
        HStack {
            Button { shift(-7) } label: { Image(systemName: "chevron.left") }
            Spacer()
            let w = Week.isoWeek(weekDate)
            Text("Uge \(w.week)").font(.headline)
            Spacer()
            Button { shift(7) } label: { Image(systemName: "chevron.right") }
        }
        .padding(.vertical, 4)
    }

    private func shift(_ days: Int) {
        weekDate = Calendar.week.date(byAdding: .day, value: days, to: weekDate) ?? weekDate
    }
}
