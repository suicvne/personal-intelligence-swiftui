// Goals: what you're aiming for, by priority, with target dates and what each one prioritizes.
// Mirrors `intel goal list|add|state`, plus changing a goal's priority, target date and what it prioritizes.
// The brief reminds you as a target date nears, and says when recent work goes elsewhere than a goal's.

import IntelKit
import SwiftUI

struct GoalsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var goals: [GoalView] = []
    @State private var includeClosed = false
    @State private var selection: GoalView.ID?
    @State private var isLoading = false
    @State private var adding = false
    @State private var message: String?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                Loadable(isLoading: isLoading, isEmpty: goals.isEmpty,
                         emptyTitle: includeClosed ? "No goals yet" : "No active goals", emptySymbol: "target") {
                    List(selection: $selection) {
                        if includeClosed {
                            Section("Active") {
                                ForEach(goals.filter(\.isActive)) { GoalRow(goal: $0).tag($0.id) }
                            }
                            Section("Achieved and abandoned") {
                                ForEach(goals.filter { !$0.isActive }) { GoalRow(goal: $0).tag($0.id) }
                            }
                        } else {
                            ForEach(goals) { GoalRow(goal: $0).tag($0.id) }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { MessageBar(message: message) }
            .frame(minWidth: 280, idealWidth: 340)

            Group {
                if let goal = goals.first(where: { $0.id == selection }) {
                    GoalDetailPane(goal: goal) { updated, done in
                        if let done { message = done }
                        await Load()
                        selection = goals.contains { $0.id == updated.id } ? updated.id : nil
                        await model.LoadStatus()        // the brief's reminders may have changed
                    }
                } else {
                    ContentUnavailableView("Select a goal", systemImage: "hand.point.left",
                                           description: Text("The brief reminds you as a goal's target date nears, and says when your work goes elsewhere."))
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Goals")
        .toolbar {
            ToolbarItem {
                Toggle("Show achieved & abandoned", isOn: $includeClosed).toggleStyle(.checkbox)
            }
            ToolbarItem {
                Button { adding = true } label: { Label("Add Goal", systemImage: "plus") }
                    .help("Add a goal: what it prioritizes, how much, and by when")
            }
        }
        .sheet(isPresented: $adding) {
            GoalSheet(goal: nil) { added in
                message = "Added \"\(added.statement)\""
                await Load()
                selection = added.id
                await model.LoadStatus()
            }
            .environment(model)
        }
        .task(id: "\(model.refreshToken)-\(includeClosed)") { await Load() }
    }

    private func Load() async {
        isLoading = true
        defer { isLoading = false }
        if let result = await model.Run({ try await $0.Goals(includeClosed: includeClosed) }) {
            goals = result
        }
    }
}

private struct GoalRow: View {
    let goal: GoalView

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            PriorityBadge(priority: goal.priority)
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.statement).lineLimit(2)
                HStack(spacing: 4) {
                    if !goal.isActive {
                        Text(goal.state)
                    } else if let day = goal.targetDate {
                        Text(Formatting.Due(day)).foregroundStyle(DueColor(day))
                    }
                    if !goal.prioritizes.isEmpty {
                        Text((goal.isActive && goal.targetDate == nil ? "" : "· ")
                             + goal.prioritizes.map(\.name).joined(separator: ", "))
                    }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .opacity(goal.isActive ? 1 : 0.6)
    }
}

private struct PriorityBadge: View {
    let priority: Int

    var body: some View {
        Text("P\(priority)")
            .font(.caption2.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Tint.opacity(0.18), in: Capsule())
            .foregroundStyle(Tint)
            .help(priority == 1 ? "Priority 1 (highest)" : priority == 3 ? "Priority 3 (lowest)" : "Priority \(priority)")
    }

    private var Tint: Color {
        switch priority {
        case 1: .orange
        case 2: .blue
        default: .secondary
        }
    }
}

/// Overdue in red, due today or tomorrow in orange.
private func DueColor(_ day: String) -> Color {
    guard let days = Formatting.DaysUntil(day) else { return .secondary }
    return days < 0 ? .red : days <= 1 ? .orange : .secondary
}

private struct GoalDetailPane: View {
    @Environment(AppModel.self) private var model
    let goal: GoalView
    /// After a change: the goal as it is now, and what to say about it (nil: nothing).
    let changed: (GoalView, String?) async -> Void
    @State private var editing = false
    @State private var isWorking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        PriorityBadge(priority: goal.priority)
                        Text(goal.statement).font(.title2.weight(.semibold)).textSelection(.enabled)
                    }
                    Text(Summary).foregroundStyle(.secondary)
                    if let day = goal.targetDate {
                        Text(DueText(day)).foregroundStyle(goal.isActive ? DueColor(day) : .secondary)
                    }
                }

                HStack {
                    if goal.isActive {
                        Button { SetState("achieved") } label: { Label("Achieved", systemImage: "checkmark.circle") }
                            .buttonStyle(.borderedProminent)
                            .help("Mark it achieved: its reminders end")
                        Button("Abandon") { SetState("abandoned") }
                            .help("You're no longer after it; its reminders end (you can reactivate it)")
                    } else {
                        Button("Reactivate") { SetState("active") }
                    }
                    Button("Edit…") { editing = true }
                        .help("Change its priority, target date and what it prioritizes")
                    if isWorking { ProgressView().controlSize(.small) }
                }
                .disabled(isWorking)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Prioritizes").font(.headline)
                    if goal.prioritizes.isEmpty {
                        Text("Nothing yet. A goal that prioritizes a project lets the brief say when your work goes elsewhere.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(goal.prioritizes) { target in
                        HStack(alignment: .firstTextBaseline) {
                            Text(target.name)
                            Text(target.type).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(target.lastActivityAt.map { "last activity \(Formatting.RelativeAge($0))" } ?? "no recorded activity")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                ForEach(goal.observations) { observation in
                    ObservationCard(observation: observation) { await changed(goal, nil) }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $editing) {
            GoalSheet(goal: goal) { updated in await changed(updated, "Changed \"\(updated.statement)\"") }
                .environment(model)
        }
    }

    private var Summary: String {
        let priority = goal.priority == 1 ? "Priority 1 (highest)" : goal.priority == 3 ? "Priority 3 (lowest)" : "Priority 2"
        return "\(priority) · \(goal.state)" + (goal.targetDate == nil ? " · no target date" : "")
    }

    private func DueText(_ day: String) -> String {
        let date = Formatting.LocalDate(day)?.formatted(.dateTime.weekday(.wide).month(.wide).day().year()) ?? day
        return goal.isActive ? "Target \(date): \(Formatting.Due(day))" : "Target \(date)"
    }

    private func SetState(_ state: String) {
        isWorking = true
        Task {
            defer { isWorking = false }
            if let updated = await model.Run({ try await $0.SetGoalState(id: goal.id, state: state) }) {
                let done = ["achieved": "Achieved", "abandoned": "Abandoned", "active": "Reactivated"][state] ?? state
                await changed(updated, "\(done): \(updated.statement)")
            }
        }
    }
}

// MARK: - Adding and changing a goal

/// A new goal (`goal` nil), or a goal's priority, target date and what it prioritizes.
private struct GoalSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let goal: GoalView?
    let saved: (GoalView) async -> Void

    private struct Target: Identifiable, Hashable {
        let id: Int
        let name: String
        let type: String
    }

    @State private var statement = ""
    @State private var priority = 2
    @State private var hasTargetDate = false
    @State private var targetDate = Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now
    @State private var targets: [Target] = []
    @State private var choice: EntitySummary?
    @State private var isWorking = false
    @State private var failure: String?

    var body: some View {
        EditForm(title: goal == nil ? "Add a goal" : "Change this goal",
                 footnote: "The brief reminds you as the target date nears, and says when your recent work goes to something else than what the goal prioritizes.",
                 action: goal == nil ? "Add" : "Save", canSave: goal != nil || !Trimmed(statement).isEmpty,
                 isWorking: isWorking, failure: failure, save: Save) {
            if let goal {
                LabeledContent("Goal") { Text(goal.statement) }
            } else {
                TextField("Goal", text: $statement, prompt: Text("e.g. Ship the Crawler demo"), axis: .vertical)
                    .lineLimit(1...3)
            }
            Picker("Priority", selection: $priority) {
                Text("1 · highest").tag(1)
                Text("2").tag(2)
                Text("3 · lowest").tag(3)
            }
            .pickerStyle(.segmented)
            Toggle("Has a target date", isOn: $hasTargetDate)
            if hasTargetDate {
                DatePicker("Target date", selection: $targetDate, displayedComponents: .date)
            }
            LabeledContent("Prioritizes") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(targets) { target in
                        HStack {
                            Text(target.name)
                            Text(target.type).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button { targets.removeAll { $0.id == target.id } } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Stop prioritizing \(target.name)")
                        }
                    }
                    EntityChooser(excluding: Set(targets.map(\.id)), excludingTypes: ["goal", "decision", "task"],
                                  selection: $choice)
                }
            }
        }
        .onChange(of: choice) {
            guard let choice else { return }
            targets.append(Target(id: choice.id, name: choice.name, type: choice.type))
            self.choice = nil
        }
        .onAppear {
            guard let goal else { return }
            priority = goal.priority
            if let day = goal.targetDate, let date = Formatting.LocalDate(day) {
                hasTargetDate = true
                targetDate = date
            }
            targets = goal.prioritizes.map { Target(id: $0.id, name: $0.name, type: $0.type) }
        }
    }

    private func Save() {
        let day = hasTargetDate ? Formatting.CalendarDay(targetDate) : nil
        let prioritizes = targets.map { String($0.id) }
        isWorking = true
        failure = nil
        Task {
            defer { isWorking = false }
            let result = await model.Submit({ client in
                if let goal {
                    return try await client.UpdateGoal(id: goal.id, priority: priority, targetDate: day,
                                                       prioritizes: prioritizes)
                }
                return try await client.AddGoal(statement: Trimmed(statement), prioritizes: prioritizes,
                                                priority: priority, targetDate: day)
            }, failed: { failure = $0 })
            guard let result else { return }
            dismiss()
            await saved(result)
        }
    }

    private func Trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
}
