//
//  ContentView.swift
//  Haptic Alert Watch
//
//  Created by Kevin Spang on 8/24/26.
//
//  Placeholder shell. The real create/list/edit UI is SPEC §10 step 6.
//  Until then this surfaces the scheduler's internal state so the alarm
//  loop can be verified on device without a debugger attached — the intents
//  run out-of-process, so a console isn't available when they matter most.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \Reminder.createdAt) private var reminders: [Reminder]
    @Query(sort: \AlertCategory.name) private var categories: [AlertCategory]
    @Query(sort: \ScheduledOccurrence.fireAt) private var occurrences: [ScheduledOccurrence]

    @State private var showingAlarmKitSpike = false
    @State private var capacityWarning: String?

    private var completions: [CompletionEvent] {
        reminders.flatMap(\.completions).sorted { $0.resolvedAt > $1.resolvedAt }
    }

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

                Section("Reminders") {
                    if reminders.isEmpty {
                        Text("No reminders yet").foregroundStyle(.secondary)
                    }
                    ForEach(reminders) { reminder in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reminder.title)
                            Text(reminder.schedule.shortDescription)
                                .font(.caption).foregroundStyle(.secondary)
                            if let anchor = reminder.lastAnchoringCompletion {
                                Text("anchor \(anchor.formatted(date: .omitted, time: .standard))")
                                    .font(.caption2).foregroundStyle(.blue)
                            }
                        }
                    }
                    .onDelete(perform: deleteReminders)
                }

                // The live scheduler state. If an alarm doesn't fire, this is
                // the first place to look: no row means reconciliation never
                // planned it, and a nil alarm ID means AlarmKit refused it.
                Section("Scheduled occurrences") {
                    if occurrences.isEmpty {
                        Text("None").foregroundStyle(.secondary)
                    }
                    ForEach(occurrences) { occurrence in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(occurrence.fireAt.formatted(date: .omitted, time: .standard))
                                .font(.callout)
                            Text("\(occurrence.state.rawValue) · alarm \(occurrence.alarmKitID == nil ? "none" : "registered")")
                                .font(.caption2)
                                .foregroundStyle(occurrence.state == .orphaned ? .red : .secondary)
                        }
                    }
                }

                // Proves the out-of-process intent reached the store. If an
                // alarm was resolved but nothing appears here, the intent ran
                // but its SwiftData write didn't land.
                Section("Completion history") {
                    if completions.isEmpty {
                        Text("None").foregroundStyle(.secondary)
                    }
                    ForEach(completions) { event in
                        Text("\(event.action.rawValue) · \(event.resolvedAt.formatted(date: .omitted, time: .standard))")
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Alerts")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Spike") { showingAlarmKitSpike = true }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Test loop", action: addTwoMinuteLoop)
                    Button("Reconcile") { Task { await reconcile() } }
                }
            }
            .sheet(isPresented: $showingAlarmKitSpike) {
                AlarmKitSpikeView()
            }
            // SPEC §6: reconcile on foreground. Background execution can't be
            // trusted, so returning to the app is the reliable moment to
            // rebuild the window.
            .task { await reconcile() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await reconcile() }
            }
        }
    }

    /// Creates a completion-relative reminder on a 2-minute interval, so the
    /// full loop — fire, resolve from the Watch, re-anchor, reschedule — can
    /// be observed in a couple of minutes instead of hours.
    private func addTwoMinuteLoop() {
        let category = categories.first ?? {
            let new = AlertCategory(
                name: "Test",
                symbolName: "pills.fill",
                colorHex: "#FF375F",
                existingCount: categories.count
            )
            context.insert(new)
            return new
        }()

        context.insert(Reminder(
            title: "Test loop",
            categoryID: category.id,
            schedule: .relativeToCompletion(interval: 120, anchorReset: nil)
        ))
        Task { await reconcile() }
    }

    private func deleteReminders(at offsets: IndexSet) {
        for index in offsets { context.delete(reminders[index]) }
        Task { await reconcile() }
    }

    private func reconcile() async {
        let service = ReconciliationService(context: context)
        await service.reconcile()
        capacityWarning = service.capacityWarning
    }
}

extension ScheduleType {
    var shortDescription: String {
        switch self {
        case let .fixed(times, weekdays):
            let days = weekdays.isEmpty ? "every day" : "\(weekdays.count) days/wk"
            return "Fixed · \(times.count) time(s) · \(days)"
        case let .relativeToCompletion(interval, _):
            let minutes = Int(interval / 60)
            return minutes < 60
                ? "Every \(minutes)m after completion"
                : "Every \(Int(interval / 3600))h after completion"
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
