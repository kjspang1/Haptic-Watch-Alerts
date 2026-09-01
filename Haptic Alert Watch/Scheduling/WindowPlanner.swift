//
//  WindowPlanner.swift
//  Haptic Alert Watch
//
//  The rolling window and its reconciliation diff (SPEC §6), as pure
//  functions over value types. No SwiftData and no AlarmKit, so the logic
//  that decides which alarms exist can be tested without either.
//
//  SPEC §6 is emphatic that the schedule is *rebuilt*, not mutated:
//  `plan(desired:existing:)` is idempotent, so running it twice against an
//  unchanged world produces an empty second plan.
//

import Foundation

/// A reminder reduced to only what scheduling needs.
struct ReminderPlan: Equatable, Sendable {
    let id: UUID
    let schedule: ScheduleType
    let isEnabled: Bool
    /// Last anchoring completion, for completion-relative schedules.
    let anchor: Date?
    let createdAt: Date

    init(id: UUID, schedule: ScheduleType, isEnabled: Bool = true, anchor: Date? = nil, createdAt: Date) {
        self.id = id
        self.schedule = schedule
        self.isEnabled = isEnabled
        self.anchor = anchor
        self.createdAt = createdAt
    }
}

/// A firing we want to exist.
struct PlannedOccurrence: Equatable, Sendable {
    let reminderID: UUID
    let fireAt: Date

    /// Identity across a rebuild: same reminder, same second.
    var key: String { "\(reminderID.uuidString)@\(Int(fireAt.timeIntervalSince1970))" }
}

/// A firing that already exists in the store.
struct ExistingOccurrence: Equatable, Sendable {
    let id: UUID
    let reminderID: UUID
    let fireAt: Date
    let alarmKitID: UUID?
    let state: OccurrenceState

    var key: String { "\(reminderID.uuidString)@\(Int(fireAt.timeIntervalSince1970))" }
}

/// The diff between what should exist and what does.
struct ReconciliationPlan: Equatable, Sendable {
    var toSchedule: [PlannedOccurrence] = []
    var toCancel: [ExistingOccurrence] = []
    var unchanged: [ExistingOccurrence] = []

    var isEmpty: Bool { toSchedule.isEmpty && toCancel.isEmpty }
}

struct WindowPlanner: Sendable {
    var engine: ScheduleEngine
    /// How far ahead to materialize. SPEC §6 says 24–36h; the system alarm
    /// ceiling is undocumented, so this is deliberately shrinkable.
    var window: TimeInterval
    /// Hard cap per reminder, so a pathological interval (every 60s) cannot
    /// flood the window and exhaust the system alarm limit on its own.
    var maxOccurrencesPerReminder: Int

    init(
        engine: ScheduleEngine = ScheduleEngine(),
        window: TimeInterval = 30 * 3600,
        maxOccurrencesPerReminder: Int = 24
    ) {
        self.engine = engine
        self.window = window
        self.maxOccurrencesPerReminder = maxOccurrencesPerReminder
    }

    // MARK: - Desired state

    func desiredOccurrences(for reminders: [ReminderPlan], now: Date) -> [PlannedOccurrence] {
        let horizon = now.addingTimeInterval(window)
        return reminders
            .filter(\.isEnabled)
            .flatMap { occurrences(for: $0, now: now, horizon: horizon) }
            .sorted { $0.fireAt < $1.fireAt }
    }

    private func occurrences(for reminder: ReminderPlan, now: Date, horizon: Date) -> [PlannedOccurrence] {
        switch reminder.schedule {
        case .fixed:
            // Clock-anchored, so every firing in the window is knowable now.
            var results: [PlannedOccurrence] = []
            var cursor = now
            while results.count < maxOccurrencesPerReminder {
                guard let next = engine.nextFire(
                    for: reminder.schedule, now: cursor,
                    anchor: reminder.anchor, createdAt: reminder.createdAt
                ), next <= horizon else { break }
                results.append(PlannedOccurrence(reminderID: reminder.id, fireAt: next))
                cursor = next
            }
            return results

        case .relativeToCompletion:
            // Only ONE is knowable. The occurrence after this one depends on
            // when the user actually completes it, which hasn't happened yet
            // — materializing a second would be inventing a completion.
            guard let next = engine.nextFire(
                for: reminder.schedule, now: now,
                anchor: reminder.anchor, createdAt: reminder.createdAt
            ), next <= horizon else { return [] }
            return [PlannedOccurrence(reminderID: reminder.id, fireAt: next)]

        case .oneOff:
            guard let next = engine.nextFire(
                for: reminder.schedule, now: now,
                anchor: reminder.anchor, createdAt: reminder.createdAt
            ), next <= horizon else { return [] }
            return [PlannedOccurrence(reminderID: reminder.id, fireAt: next)]
        }
    }

    // MARK: - Diff (SPEC §6 reconciliation algorithm)

    /// Diffs desired against stored. Idempotent: with an unchanged world the
    /// second run returns an empty plan.
    ///
    /// Only live occurrences (`.pending` / `.scheduled`) participate. Ones
    /// already `.fired`, `.resolved` or `.orphaned` are history and are
    /// neither cancelled nor counted as satisfying a desired firing.
    func plan(desired: [PlannedOccurrence], existing: [ExistingOccurrence]) -> ReconciliationPlan {
        let live = existing.filter { $0.state == .pending || $0.state == .scheduled }
        let liveByKey = Dictionary(live.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let desiredKeys = Set(desired.map(\.key))

        var plan = ReconciliationPlan()
        for occurrence in desired where liveByKey[occurrence.key] == nil {
            plan.toSchedule.append(occurrence)
        }
        for occurrence in live {
            if desiredKeys.contains(occurrence.key) {
                plan.unchanged.append(occurrence)
            } else {
                plan.toCancel.append(occurrence)
            }
        }
        return plan
    }

    /// Occurrences whose AlarmKit alarm has vanished underneath us.
    ///
    /// Marked `.orphaned` rather than deleted, so a scheduling failure stays
    /// visible instead of silently disappearing (SPEC §6 step 5).
    func orphaned(existing: [ExistingOccurrence], liveAlarmIDs: Set<UUID>) -> [ExistingOccurrence] {
        existing.filter { occurrence in
            guard occurrence.state == .scheduled, let alarmID = occurrence.alarmKitID else { return false }
            return !liveAlarmIDs.contains(alarmID)
        }
    }

    /// A smaller window, for retrying after `maximumLimitReached` (SPEC §6
    /// rule 4: shrink and retry rather than failing outward).
    func shrunk(by factor: Double = 0.5, floor: TimeInterval = 3600) -> WindowPlanner {
        var copy = self
        copy.window = max(floor, window * factor)
        return copy
    }
}
