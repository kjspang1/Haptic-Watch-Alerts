//
//  Reminder.swift
//  Haptic Alert Watch
//
//  A Reminder is a *rule*, not a firing. Materialized firings live in
//  ScheduledOccurrence. Keeping these separate is what makes the
//  rolling-window scheduler and its reconciliation tractable (SPEC §4).
//

import Foundation
import SwiftData

@Model
final class Reminder {
    var id: UUID = UUID()
    var title: String = ""
    /// v2 payload: "two blue pills". Not surfaced in the alert in v1.
    var note: String?
    /// → AlertCategory.id. Held as an ID rather than a relationship because
    /// deleting a category must not cascade into its reminders.
    var categoryID: UUID = UUID()
    /// Backing storage for `schedule`.
    ///
    /// `ScheduleType` is an enum with associated values carrying collections
    /// (`[DateComponents]`, `Set<Int>`). SwiftData trips an assertion trying
    /// to build a schema for that shape, so it is persisted as encoded JSON
    /// and exposed through the computed `schedule` below. Nothing queries on
    /// schedule contents, so losing predicate support costs us nothing.
    var scheduleData: Data = Data()
    var isEnabled: Bool = true
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \CompletionEvent.reminder)
    var completions: [CompletionEvent] = []

    init(
        id: UUID = UUID(),
        title: String,
        note: String? = nil,
        categoryID: UUID,
        schedule: ScheduleType,
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.categoryID = categoryID
        self.scheduleData = Self.encode(schedule)
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    /// The recurrence rule. See `scheduleData` for why this is computed.
    var schedule: ScheduleType {
        get {
            (try? JSONDecoder().decode(ScheduleType.self, from: scheduleData))
                ?? .oneOff(date: .distantFuture)
        }
        set { scheduleData = Self.encode(newValue) }
    }

    private static func encode(_ schedule: ScheduleType) -> Data {
        (try? JSONEncoder().encode(schedule)) ?? Data()
    }

    /// The anchor a `relativeToCompletion` schedule counts forward from.
    ///
    /// Only `.done` and `.skipped` move the anchor. A deferral or a bare
    /// dismissal deliberately leaves it where it was, so snoozing an alert
    /// cannot quietly walk the whole schedule forward (SPEC §5.2).
    var lastAnchoringCompletion: Date? {
        completions
            .filter { $0.action == .done || $0.action == .skipped }
            .map(\.resolvedAt)
            .max()
    }
}

/// A record of what the user did when an alert fired.
@Model
final class CompletionEvent {
    var id: UUID = UUID()
    /// When it was supposed to fire.
    var scheduledFor: Date = Date()
    /// When the user actually acted.
    var resolvedAt: Date = Date()
    var action: CompletionAction = CompletionAction.done
    /// v2: ounces, dose taken. Always nil in v1 — the field exists now so
    /// adding it later doesn't touch the whole completion path (SPEC §4).
    var payload: Data?

    var reminder: Reminder?

    init(
        id: UUID = UUID(),
        scheduledFor: Date,
        resolvedAt: Date = Date(),
        action: CompletionAction,
        payload: Data? = nil,
        reminder: Reminder? = nil
    ) {
        self.id = id
        self.scheduledFor = scheduledFor
        self.resolvedAt = resolvedAt
        self.action = action
        self.payload = payload
        self.reminder = reminder
    }
}
