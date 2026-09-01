//
//  ContentView.swift
//  Haptic Alert Watch
//
//  Created by Kevin Spang on 8/24/26.
//
//  Placeholder shell. The real create/list/edit UI is SPEC §10 step 6;
//  this exists so the model layer is inspectable on device in the meantime.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Reminder.createdAt) private var reminders: [Reminder]
    @Query(sort: \AlertCategory.name) private var categories: [AlertCategory]

    @State private var showingAlarmKitSpike = false
    @State private var capacityWarning: String?

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
                        Text("No reminders yet")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(reminders) { reminder in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reminder.title)
                            Text(reminder.schedule.shortDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: deleteReminders)
                }

                Section("Categories") {
                    ForEach(categories) { category in
                        Label(category.name, systemImage: category.symbolName)
                    }
                }
            }
            .navigationTitle("Alerts")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Spike") { showingAlarmKitSpike = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sample", systemImage: "plus", action: addSample)
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

    private func reconcile() async {
        let service = ReconciliationService(context: context)
        await service.reconcile()
        capacityWarning = service.capacityWarning
    }

    /// Temporary: exercises the model layer until step 6 builds real entry UI.
    private func addSample() {
        let category: AlertCategory
        if let existing = categories.first {
            category = existing
        } else {
            category = AlertCategory(
                name: "Medication",
                symbolName: "pills.fill",
                colorHex: "#FF375F",
                existingCount: categories.count
            )
            context.insert(category)
        }

        let reminder = Reminder(
            title: "Sample reminder",
            categoryID: category.id,
            schedule: .relativeToCompletion(interval: 3 * 3600, anchorReset: nil)
        )
        context.insert(reminder)
        Task { await reconcile() }
    }

    private func deleteReminders(at offsets: IndexSet) {
        for index in offsets {
            context.delete(reminders[index])
        }
        Task { await reconcile() }
    }
}

extension ScheduleType {
    var shortDescription: String {
        switch self {
        case let .fixed(times, weekdays):
            let days = weekdays.isEmpty ? "every day" : "\(weekdays.count) days/wk"
            return "Fixed · \(times.count) time(s) · \(days)"
        case let .relativeToCompletion(interval, _):
            return "Every \(Int(interval / 3600))h after completion"
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
