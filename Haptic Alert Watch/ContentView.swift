//
//  ContentView.swift
//  Haptic Alert Watch
//
//  Created by Kevin Spang on 8/24/26.
//
//  The reminder list (SPEC §10 step 6).
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \Reminder.createdAt) private var reminders: [Reminder]
    @Query(sort: \ScheduledOccurrence.fireAt) private var occurrences: [ScheduledOccurrence]

    @State private var editing: Reminder?
    @State private var isCreating = false
    @State private var showingDebug = false
    @State private var capacityWarning: String?

    private let engine = ScheduleEngine()

    var body: some View {
        NavigationStack {
            List {
                if let capacityWarning {
                    Section {
                        Label(capacityWarning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                if reminders.isEmpty {
                    ContentUnavailableView(
                        "No reminders",
                        systemImage: "bell.slash",
                        description: Text("Add one to get started.")
                    )
                } else {
                    ForEach(reminders) { reminder in
                        Button {
                            editing = reminder
                        } label: {
                            ReminderRow(reminder: reminder, nextFire: nextFire(for: reminder))
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) { delete(reminder) }
                        }
                        .swipeActions(edge: .leading) {
                            // A fast way to silence something without losing
                            // its history — the 3am "stop, I'll fix it later".
                            Button(reminder.isEnabled ? "Pause" : "Resume") {
                                toggle(reminder)
                            }
                            .tint(reminder.isEnabled ? .orange : .green)
                        }
                    }
                }
            }
            .navigationTitle("Alerts")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Debug") { showingDebug = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add", systemImage: "plus") { isCreating = true }
                }
            }
            .sheet(isPresented: $isCreating) { ReminderEditor() }
            .sheet(item: $editing) { ReminderEditor(existing: $0) }
            .sheet(isPresented: $showingDebug) {
                SchedulerDebugView(occurrences: occurrences, reminders: reminders)
            }
            // SPEC §6: reconcile on foreground. Background execution can't be
            // trusted, so returning to the app is the reliable rebuild point.
            .task { await reconcile() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await reconcile() }
            }
        }
    }

    private func nextFire(for reminder: Reminder) -> Date? {
        guard reminder.isEnabled else { return nil }
        return occurrences
            .filter { $0.reminderID == reminder.id && $0.state == .scheduled }
            .map(\.fireAt)
            .min()
            ?? engine.nextFire(
                for: reminder.schedule,
                now: .now,
                anchor: reminder.lastAnchoringCompletion,
                createdAt: reminder.createdAt
            )
    }

    private func delete(_ reminder: Reminder) {
        context.delete(reminder)
        try? context.save()
        Task { await reconcile() }
    }

    private func toggle(_ reminder: Reminder) {
        reminder.isEnabled.toggle()
        try? context.save()
        Task { await reconcile() }
    }

    private func reconcile() async {
        let service = ReconciliationService(context: context)
        await service.reconcile()
        capacityWarning = service.capacityWarning
    }
}

struct ReminderRow: View {
    let reminder: Reminder
    let nextFire: Date?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(reminder.title)
                    .font(.body)
                    .foregroundStyle(reminder.isEnabled ? .primary : .secondary)
                Text(reminder.schedule.shortDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !reminder.isEnabled {
                    Text("Paused").font(.caption2).foregroundStyle(.orange)
                } else if let nextFire {
                    Text("Next \(nextFire.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

/// Scheduler internals. The alarm intents run out-of-process, so when
/// something misfires there's no console — this is where to look instead.
struct SchedulerDebugView: View {
    @Environment(\.dismiss) private var dismiss
    let occurrences: [ScheduledOccurrence]
    let reminders: [Reminder]

    private var completions: [CompletionEvent] {
        reminders.flatMap(\.completions).sorted { $0.resolvedAt > $1.resolvedAt }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Scheduled occurrences") {
                    if occurrences.isEmpty { Text("None").foregroundStyle(.secondary) }
                    ForEach(occurrences) { occurrence in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(occurrence.fireAt.formatted(date: .omitted, time: .standard))
                            Text("\(occurrence.state.rawValue) · alarm \(occurrence.alarmKitID == nil ? "none" : "registered")")
                                .font(.caption2)
                                .foregroundStyle(occurrence.state == .orphaned ? .red : .secondary)
                        }
                    }
                }
                Section("Completion history") {
                    if completions.isEmpty { Text("None").foregroundStyle(.secondary) }
                    ForEach(completions.prefix(20)) { event in
                        Text("\(event.action.rawValue) · \(event.resolvedAt.formatted(date: .omitted, time: .standard))")
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Scheduler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

extension ScheduleType {
    var shortDescription: String {
        switch self {
        case let .fixed(times, weekdays):
            let days = weekdays.isEmpty ? "every day" : "\(weekdays.count) days a week"
            let listed = times
                .compactMap { Calendar.current.date(from: $0) }
                .map { $0.formatted(date: .omitted, time: .shortened) }
                .joined(separator: ", ")
            return listed.isEmpty ? "Fixed · \(days)" : "\(listed) · \(days)"
        case let .relativeToCompletion(interval, reset):
            let hours = Int(interval) / 3600
            let minutes = (Int(interval) % 3600) / 60
            var text = hours > 0
                ? (minutes > 0 ? "Every \(hours)h \(minutes)m" : "Every \(hours)h")
                : "Every \(minutes)m"
            text += " after completion"
            if reset != nil { text += " · resets daily" }
            return text
        case let .oneOff(date):
            return "Once · \(date.formatted(date: .abbreviated, time: .shortened))"
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            Reminder.self, CompletionEvent.self,
            AlertCategory.self, ScheduledOccurrence.self,
        ], inMemory: true)
}
