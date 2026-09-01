//
//  ReconciliationService.swift
//  Haptic Alert Watch
//
//  Applies the WindowPlanner's diff to SwiftData and AlarmKit (SPEC §6).
//
//  Reconcile on: app foreground (background execution can't be trusted),
//  any reminder create/update/delete, any completion, and any alarm firing.
//

import Foundation
import SwiftData

@MainActor
final class ReconciliationService {
    private let context: ModelContext
    private let scheduler: any AlarmScheduling
    private let planner: WindowPlanner
    /// How many times to shrink the window and retry after hitting the
    /// system alarm ceiling before giving up and surfacing a warning.
    private let maxShrinkAttempts: Int

    /// Set when the user's configuration genuinely cannot fit in the
    /// smallest window we're willing to use (SPEC §6 rule 4).
    private(set) var capacityWarning: String?

    init(
        context: ModelContext,
        scheduler: any AlarmScheduling = AlarmKitScheduler(),
        planner: WindowPlanner = WindowPlanner(),
        maxShrinkAttempts: Int = 3
    ) {
        self.context = context
        self.scheduler = scheduler
        self.planner = planner
        self.maxShrinkAttempts = maxShrinkAttempts
    }

    @discardableResult
    func reconcile(now: Date = .now) async -> ReconciliationPlan {
        var activePlanner = planner
        var attempt = 0

        while true {
            let reminders = fetchReminderPlans()
            let existing = fetchExistingOccurrences()

            let desired = activePlanner.desiredOccurrences(for: reminders, now: now)
            let plan = activePlanner.plan(desired: desired, existing: existing)

            await cancel(plan.toCancel)

            do {
                try await scheduleAll(plan.toSchedule, reminders: reminders)
                try? context.save()
                await markOrphans()
                capacityWarning = nil
                return plan
            } catch is AlarmLimitReached {
                // Shrink and retry rather than failing outward. Occurrences
                // already scheduled this pass stay; the retry re-diffs and
                // simply plans fewer of them.
                try? context.save()
                attempt += 1
                guard attempt <= maxShrinkAttempts else {
                    capacityWarning = "Too many reminders to schedule reliably. "
                        + "Some alerts further ahead may not fire until earlier ones resolve."
                    return plan
                }
                activePlanner = activePlanner.shrunk()
            } catch {
                try? context.save()
                return plan
            }
        }
    }

    // MARK: - Applying the plan

    private func scheduleAll(_ occurrences: [PlannedOccurrence], reminders: [ReminderPlan]) async throws {
        let categories = (try? context.fetch(FetchDescriptor<AlertCategory>())) ?? []
        let allReminders = (try? context.fetch(FetchDescriptor<Reminder>())) ?? []

        // Nearest first, so if the ceiling is hit the alarms we lose are the
        // furthest out — the ones most likely to be re-planned later anyway.
        for occurrence in occurrences.sorted(by: { $0.fireAt < $1.fireAt }) {
            guard let reminder = allReminders.first(where: { $0.id == occurrence.reminderID }) else { continue }
            let category = categories.first { $0.id == reminder.categoryID }

            let row = ScheduledOccurrence(
                reminderID: occurrence.reminderID,
                fireAt: occurrence.fireAt,
                state: .pending
            )
            context.insert(row)

            let request = AlarmRequest(
                occurrenceID: row.id,
                reminderID: reminder.id,
                title: reminder.title,
                fireAt: occurrence.fireAt,
                soundID: category?.soundID ?? "default",
                tintColorHex: category?.colorHex ?? "#007AFF"
            )

            let alarmKitID = try await scheduler.schedule(request)
            row.alarmKitID = alarmKitID
            row.state = .scheduled
        }
    }

    private func cancel(_ occurrences: [ExistingOccurrence]) async {
        guard !occurrences.isEmpty else { return }
        let ids = Set(occurrences.map(\.id))

        for occurrence in occurrences {
            if let alarmKitID = occurrence.alarmKitID {
                try? await scheduler.cancel(alarmKitID: alarmKitID)
            }
        }
        // Cancelled occurrences were never reached, so they're not history —
        // delete them rather than leaving misleading rows behind.
        let rows = (try? context.fetch(
            FetchDescriptor<ScheduledOccurrence>(predicate: #Predicate { ids.contains($0.id) })
        )) ?? []
        for row in rows { context.delete(row) }
    }

    /// Marks occurrences whose alarm has vanished, so a scheduling failure
    /// stays visible rather than silently disappearing.
    private func markOrphans() async {
        let liveIDs = await scheduler.liveAlarmIDs()
        guard !liveIDs.isEmpty else { return }

        let existing = fetchExistingOccurrences()
        let orphans = Set(planner.orphaned(existing: existing, liveAlarmIDs: liveIDs).map(\.id))
        guard !orphans.isEmpty else { return }

        let rows = (try? context.fetch(
            FetchDescriptor<ScheduledOccurrence>(predicate: #Predicate { orphans.contains($0.id) })
        )) ?? []
        for row in rows { row.state = .orphaned }
        try? context.save()
    }

    // MARK: - Reading current state

    private func fetchReminderPlans() -> [ReminderPlan] {
        let reminders = (try? context.fetch(FetchDescriptor<Reminder>())) ?? []
        return reminders.map {
            ReminderPlan(
                id: $0.id,
                schedule: $0.schedule,
                isEnabled: $0.isEnabled,
                anchor: $0.lastAnchoringCompletion,
                createdAt: $0.createdAt
            )
        }
    }

    private func fetchExistingOccurrences() -> [ExistingOccurrence] {
        let rows = (try? context.fetch(FetchDescriptor<ScheduledOccurrence>())) ?? []
        return rows.map {
            ExistingOccurrence(
                id: $0.id,
                reminderID: $0.reminderID,
                fireAt: $0.fireAt,
                alarmKitID: $0.alarmKitID,
                state: $0.state
            )
        }
    }
}
