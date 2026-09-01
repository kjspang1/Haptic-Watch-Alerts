//
//  ReconciliationServiceTests.swift
//  Haptic Alert WatchTests
//
//  End-to-end reconciliation against a real in-memory store and a fake
//  AlarmKit, so the SwiftData writes and the limit-retry path are covered
//  without a device.
//

import Testing
import Foundation
import SwiftData
@testable import Haptic_Alert_Watch

/// Stands in for AlarmKit. Can be told to start refusing alarms after N
/// scheduled, to exercise the shrink-and-retry path.
private final class FakeScheduler: AlarmScheduling, @unchecked Sendable {
    var scheduled: [AlarmRequest] = []
    var cancelled: [UUID] = []
    var live: Set<UUID> = []
    /// nil = unlimited.
    var ceiling: Int?

    func schedule(_ request: AlarmRequest) async throws -> UUID {
        if let ceiling, scheduled.count >= ceiling { throw AlarmLimitReached() }
        scheduled.append(request)
        let id = UUID()
        live.insert(id)
        return id
    }

    func cancel(alarmKitID: UUID) async throws {
        cancelled.append(alarmKitID)
        live.remove(alarmKitID)
    }

    func liveAlarmIDs() async -> Set<UUID> { live }
}

@MainActor
private func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: Reminder.self, CompletionEvent.self, AlertCategory.self, ScheduledOccurrence.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return ModelContext(container)
}

private var testCalendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

private func testPlanner(window: TimeInterval = 30 * 3600) -> WindowPlanner {
    WindowPlanner(engine: ScheduleEngine(calendar: testCalendar), window: window)
}

private let now = Date(timeIntervalSince1970: 1_772_000_000)

@MainActor
@Test("reconciling schedules alarms and records their AlarmKit IDs")
func reconcileSchedulesAndPersists() async throws {
    let context = try makeContext()
    let fake = FakeScheduler()

    let category = AlertCategory(name: "Meds", symbolName: "pills.fill", colorHex: "#FF0000", existingCount: 0)
    context.insert(category)
    context.insert(Reminder(
        title: "Take meds",
        categoryID: category.id,
        schedule: .relativeToCompletion(interval: 3 * 3600, anchorReset: nil),
        createdAt: now
    ))
    try context.save()

    let service = ReconciliationService(context: context, scheduler: fake, planner: testPlanner())
    await service.reconcile(now: now)

    #expect(fake.scheduled.count == 1)
    #expect(fake.scheduled.first?.title == "Take meds")

    let rows = try context.fetch(FetchDescriptor<ScheduledOccurrence>())
    #expect(rows.count == 1)
    #expect(rows.first?.state == .scheduled)
    #expect(rows.first?.alarmKitID != nil)
}

@MainActor
@Test("reconciling twice schedules nothing further")
func reconcileIsIdempotentEndToEnd() async throws {
    let context = try makeContext()
    let fake = FakeScheduler()
    context.insert(Reminder(
        title: "Feed",
        categoryID: UUID(),
        schedule: .relativeToCompletion(interval: 3 * 3600, anchorReset: nil),
        createdAt: now
    ))
    try context.save()

    let service = ReconciliationService(context: context, scheduler: fake, planner: testPlanner())
    await service.reconcile(now: now)
    let afterFirst = fake.scheduled.count

    await service.reconcile(now: now)
    #expect(fake.scheduled.count == afterFirst, "second pass must not duplicate alarms")
    #expect(try context.fetch(FetchDescriptor<ScheduledOccurrence>()).count == 1)
}

@MainActor
@Test("disabling a reminder cancels its alarm and clears the row")
func disablingCancels() async throws {
    let context = try makeContext()
    let fake = FakeScheduler()
    let reminder = Reminder(
        title: "Drops",
        categoryID: UUID(),
        schedule: .relativeToCompletion(interval: 3600, anchorReset: nil),
        createdAt: now
    )
    context.insert(reminder)
    try context.save()

    let service = ReconciliationService(context: context, scheduler: fake, planner: testPlanner())
    await service.reconcile(now: now)
    #expect(try context.fetch(FetchDescriptor<ScheduledOccurrence>()).count == 1)

    reminder.isEnabled = false
    try context.save()
    await service.reconcile(now: now)

    #expect(fake.cancelled.count == 1)
    #expect(try context.fetch(FetchDescriptor<ScheduledOccurrence>()).isEmpty)
}

@MainActor
@Test("hitting the alarm ceiling shrinks the window instead of failing")
func ceilingShrinksRatherThanFails() async throws {
    let context = try makeContext()
    let fake = FakeScheduler()
    fake.ceiling = 2

    // Hourly alarms across a 30h window would want far more than 2.
    context.insert(Reminder(
        title: "Hourly",
        categoryID: UUID(),
        schedule: .fixed(times: (0..<24).map { DateComponents(hour: $0) }, weekdays: []),
        createdAt: now
    ))
    try context.save()

    let service = ReconciliationService(context: context, scheduler: fake, planner: testPlanner())
    await service.reconcile(now: now)

    // The ceiling must be respected, and the nearest alarms still scheduled —
    // failing outward would leave the user with no alarms at all.
    #expect(fake.scheduled.count == 2)
    let scheduledRows = try context.fetch(FetchDescriptor<ScheduledOccurrence>())
        .filter { $0.state == .scheduled }
    #expect(scheduledRows.count == 2)
}

@MainActor
@Test("a capacity warning surfaces when the config cannot fit")
func capacityWarningSurfaces() async throws {
    let context = try makeContext()
    let fake = FakeScheduler()
    fake.ceiling = 0   // refuses everything

    context.insert(Reminder(
        title: "Hourly",
        categoryID: UUID(),
        schedule: .fixed(times: (0..<24).map { DateComponents(hour: $0) }, weekdays: []),
        createdAt: now
    ))
    try context.save()

    let service = ReconciliationService(
        context: context, scheduler: fake, planner: testPlanner(), maxShrinkAttempts: 2
    )
    await service.reconcile(now: now)

    // SPEC §6 rule 4: surface a warning rather than silently scheduling nothing.
    #expect(service.capacityWarning != nil)
}

@MainActor
@Test("completing a relative reminder re-anchors the next alarm")
func completionReAnchorsNextAlarm() async throws {
    let context = try makeContext()
    let fake = FakeScheduler()
    let reminder = Reminder(
        title: "Feed",
        categoryID: UUID(),
        schedule: .relativeToCompletion(interval: 3 * 3600, anchorReset: nil),
        createdAt: now
    )
    context.insert(reminder)
    try context.save()

    let service = ReconciliationService(context: context, scheduler: fake, planner: testPlanner())
    await service.reconcile(now: now)
    #expect(fake.scheduled.first?.fireAt == now.addingTimeInterval(3 * 3600))

    // Completed an hour later: the next alarm must move with the anchor.
    let completedAt = now.addingTimeInterval(3600)
    let event = CompletionEvent(scheduledFor: now, resolvedAt: completedAt, action: .done)
    event.reminder = reminder
    context.insert(event)
    for row in try context.fetch(FetchDescriptor<ScheduledOccurrence>()) {
        row.state = .resolved
    }
    try context.save()

    await service.reconcile(now: completedAt)
    #expect(fake.scheduled.last?.fireAt == completedAt.addingTimeInterval(3 * 3600))
}
