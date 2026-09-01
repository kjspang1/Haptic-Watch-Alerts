//
//  WindowPlannerTests.swift
//  Haptic Alert WatchTests
//
//  SPEC §6 calls the rolling window "mandatory architecture, not an
//  optimization" — the system alarm ceiling is real and undocumented. These
//  cover the window bounds, the idempotent diff, and orphan detection.
//

import Testing
import Foundation
@testable import Haptic_Alert_Watch

private let utc = TimeZone(identifier: "UTC")!

private var testCalendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = utc
    c.locale = Locale(identifier: "en_US_POSIX")
    return c
}

private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
    testCalendar.date(from: DateComponents(timeZone: utc, year: y, month: mo, day: d, hour: h, minute: mi))!
}

private func planner(window: TimeInterval = 30 * 3600, maxPer: Int = 24) -> WindowPlanner {
    WindowPlanner(
        engine: ScheduleEngine(calendar: testCalendar),
        window: window,
        maxOccurrencesPerReminder: maxPer
    )
}

// MARK: - Desired state

@Test("a fixed daily schedule materializes every firing inside the window")
func fixedMaterializesAcrossWindow() {
    let reminder = ReminderPlan(
        id: UUID(),
        schedule: .fixed(times: [DateComponents(hour: 8), DateComponents(hour: 20)], weekdays: []),
        createdAt: date(2026, 3, 1)
    )
    // 30h from 07:00 Tue reaches 13:00 Wed: 08:00, 20:00, 08:00.
    let desired = planner().desiredOccurrences(for: [reminder], now: date(2026, 3, 10, 7, 0))
    #expect(desired.map(\.fireAt) == [
        date(2026, 3, 10, 8, 0),
        date(2026, 3, 10, 20, 0),
        date(2026, 3, 11, 8, 0),
    ])
}

@Test("a completion-relative reminder materializes only its next firing")
func relativeMaterializesOnlyOne() {
    // The occurrence after this one depends on when the user completes it,
    // which hasn't happened — materializing a second invents a completion.
    let reminder = ReminderPlan(
        id: UUID(),
        schedule: .relativeToCompletion(interval: 3 * 3600, anchorReset: nil),
        anchor: date(2026, 3, 10, 6, 0),
        createdAt: date(2026, 3, 1)
    )
    let desired = planner().desiredOccurrences(for: [reminder], now: date(2026, 3, 10, 7, 0))
    #expect(desired.count == 1)
    #expect(desired.first?.fireAt == date(2026, 3, 10, 9, 0))
}

@Test("nothing beyond the window horizon is materialized")
func horizonIsRespected() {
    let reminder = ReminderPlan(
        id: UUID(),
        schedule: .fixed(times: [DateComponents(hour: 8)], weekdays: []),
        createdAt: date(2026, 3, 1)
    )
    // A 10h window from 07:00 reaches 17:00 — today's 08:00 only.
    let desired = planner(window: 10 * 3600).desiredOccurrences(for: [reminder], now: date(2026, 3, 10, 7, 0))
    #expect(desired.count == 1)
}

@Test("disabled reminders are not materialized")
func disabledRemindersSkipped() {
    let reminder = ReminderPlan(
        id: UUID(),
        schedule: .fixed(times: [DateComponents(hour: 8)], weekdays: []),
        isEnabled: false,
        createdAt: date(2026, 3, 1)
    )
    #expect(planner().desiredOccurrences(for: [reminder], now: date(2026, 3, 10, 7, 0)).isEmpty)
}

@Test("a pathological interval cannot flood the window")
func perReminderCapHolds() {
    // Every 60s across 30h would be 1800 alarms — far past the system
    // ceiling — so the per-reminder cap has to bound it.
    let reminder = ReminderPlan(
        id: UUID(),
        schedule: .fixed(times: (0..<24).map { DateComponents(hour: $0) }, weekdays: []),
        createdAt: date(2026, 3, 1)
    )
    let desired = planner(maxPer: 5).desiredOccurrences(for: [reminder], now: date(2026, 3, 10, 0, 30))
    #expect(desired.count == 5)
}

// MARK: - Diff

@Test("reconciliation is idempotent")
func planIsIdempotent() {
    // SPEC §6: the schedule is rebuilt, not mutated. Running twice against
    // an unchanged world must produce no second round of work.
    let reminderID = UUID()
    let fireAt = date(2026, 3, 10, 8, 0)
    let desired = [PlannedOccurrence(reminderID: reminderID, fireAt: fireAt)]
    let existing = [ExistingOccurrence(
        id: UUID(), reminderID: reminderID, fireAt: fireAt,
        alarmKitID: UUID(), state: .scheduled
    )]

    let plan = planner().plan(desired: desired, existing: existing)
    #expect(plan.isEmpty)
    #expect(plan.unchanged.count == 1)
}

@Test("a firing no longer desired is cancelled")
func staleOccurrenceIsCancelled() {
    let reminderID = UUID()
    let stale = ExistingOccurrence(
        id: UUID(), reminderID: reminderID, fireAt: date(2026, 3, 10, 8, 0),
        alarmKitID: UUID(), state: .scheduled
    )
    let plan = planner().plan(desired: [], existing: [stale])
    #expect(plan.toCancel == [stale])
    #expect(plan.toSchedule.isEmpty)
}

@Test("a newly desired firing is scheduled")
func newOccurrenceIsScheduled() {
    let wanted = PlannedOccurrence(reminderID: UUID(), fireAt: date(2026, 3, 10, 8, 0))
    let plan = planner().plan(desired: [wanted], existing: [])
    #expect(plan.toSchedule == [wanted])
}

@Test("resolved history neither blocks scheduling nor gets cancelled")
func historyIsIgnoredByTheDiff() {
    // A .resolved row at the same time must not be mistaken for a live
    // alarm satisfying the desired firing, or the alarm silently never
    // gets scheduled.
    let reminderID = UUID()
    let fireAt = date(2026, 3, 10, 8, 0)
    let history = ExistingOccurrence(
        id: UUID(), reminderID: reminderID, fireAt: fireAt,
        alarmKitID: UUID(), state: .resolved
    )
    let desired = [PlannedOccurrence(reminderID: reminderID, fireAt: fireAt)]

    let plan = planner().plan(desired: desired, existing: [history])
    #expect(plan.toSchedule.count == 1)
    #expect(plan.toCancel.isEmpty)
}

// MARK: - Orphans and capacity

@Test("a scheduled occurrence whose alarm vanished is flagged orphaned")
func orphanDetection() {
    let goneID = UUID()
    let liveID = UUID()
    let orphan = ExistingOccurrence(
        id: UUID(), reminderID: UUID(), fireAt: date(2026, 3, 10, 8, 0),
        alarmKitID: goneID, state: .scheduled
    )
    let healthy = ExistingOccurrence(
        id: UUID(), reminderID: UUID(), fireAt: date(2026, 3, 10, 9, 0),
        alarmKitID: liveID, state: .scheduled
    )

    let found = planner().orphaned(existing: [orphan, healthy], liveAlarmIDs: [liveID])
    #expect(found == [orphan])
}

@Test("shrinking halves the window but never below its floor")
func windowShrinksWithAFloor() {
    let original = planner(window: 30 * 3600)
    #expect(original.shrunk().window == 15 * 3600)

    var tiny = planner(window: 90 * 60)
    tiny = tiny.shrunk(by: 0.5, floor: 3600)
    #expect(tiny.window == 3600)
    // Shrinking to nothing would mean scheduling no alarms at all, which is
    // a worse failure than scheduling fewer.
    #expect(tiny.shrunk(by: 0.5, floor: 3600).window == 3600)
}
