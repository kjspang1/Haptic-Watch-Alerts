//
//  ModelLayerTests.swift
//  Haptic Alert WatchTests
//
//  Persistence smoke tests for the SwiftData layer (SPEC §4). The main risk
//  here is ScheduleType: it's an enum with associated values, so it round
//  trips only if SwiftData actually stores the payload and not just the case.
//

import Testing
import SwiftData
import Foundation
@testable import Haptic_Alert_Watch

@MainActor
private func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: Reminder.self, CompletionEvent.self,
             AlertCategory.self, ScheduledOccurrence.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return ModelContext(container)
}

@MainActor
@Test("relativeToCompletion survives a save/fetch round trip with its payload")
func relativeScheduleRoundTrips() throws {
    let context = try makeContext()
    let reminder = Reminder(
        title: "Feed",
        categoryID: UUID(),
        schedule: .relativeToCompletion(interval: 3 * 3600, anchorReset: nil)
    )
    context.insert(reminder)
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<Reminder>())
    #expect(fetched.count == 1)

    guard case let .relativeToCompletion(interval, anchorReset) = try #require(fetched.first).schedule else {
        Issue.record("expected relativeToCompletion, got \(fetched[0].schedule)")
        return
    }
    #expect(interval == 3 * 3600)
    #expect(anchorReset == nil)
}

@MainActor
@Test("fixed schedule preserves times and weekdays")
func fixedScheduleRoundTrips() throws {
    let context = try makeContext()
    let times = [DateComponents(hour: 8, minute: 0), DateComponents(hour: 20, minute: 30)]
    let reminder = Reminder(
        title: "Meds",
        categoryID: UUID(),
        schedule: .fixed(times: times, weekdays: [2, 4, 6])
    )
    context.insert(reminder)
    try context.save()

    let fetched = try #require(try context.fetch(FetchDescriptor<Reminder>()).first)
    guard case let .fixed(fetchedTimes, weekdays) = fetched.schedule else {
        Issue.record("expected fixed, got \(fetched.schedule)")
        return
    }
    #expect(fetchedTimes.count == 2)
    #expect(fetchedTimes.first?.hour == 8)
    #expect(fetchedTimes.last?.minute == 30)
    #expect(weekdays == [2, 4, 6])
}

@MainActor
@Test("deleting a reminder cascades to its completion events")
func deletingReminderCascades() throws {
    let context = try makeContext()
    let reminder = Reminder(
        title: "Pump",
        categoryID: UUID(),
        schedule: .relativeToCompletion(interval: 7200, anchorReset: nil)
    )
    context.insert(reminder)
    reminder.completions.append(
        CompletionEvent(scheduledFor: .now, action: .done)
    )
    try context.save()
    #expect(try context.fetch(FetchDescriptor<CompletionEvent>()).count == 1)

    context.delete(reminder)
    try context.save()
    #expect(try context.fetch(FetchDescriptor<CompletionEvent>()).isEmpty)
}

@MainActor
@Test("only done and skipped move the completion anchor")
func anchorIgnoresDeferralAndDismissal() throws {
    let context = try makeContext()
    let reminder = Reminder(
        title: "Drops",
        categoryID: UUID(),
        schedule: .relativeToCompletion(interval: 3600, anchorReset: nil)
    )
    context.insert(reminder)

    let done = Date(timeIntervalSince1970: 1_000)
    let laterDeferral = Date(timeIntervalSince1970: 5_000)
    let laterDismissal = Date(timeIntervalSince1970: 9_000)

    reminder.completions.append(CompletionEvent(scheduledFor: done, resolvedAt: done, action: .done))
    reminder.completions.append(CompletionEvent(scheduledFor: laterDeferral, resolvedAt: laterDeferral, action: .deferred))
    reminder.completions.append(CompletionEvent(scheduledFor: laterDismissal, resolvedAt: laterDismissal, action: .dismissed))
    try context.save()

    // Deferral and dismissal are later in time but must not become the anchor,
    // or snoozing would silently walk the whole schedule forward (SPEC §5.2).
    #expect(reminder.lastAnchoringCompletion == done)
}

@MainActor
@Test("alert identities are assigned by rotation, never chosen")
func alertIdentityRotates() throws {
    let count = AlertIdentity.all.count
    #expect(count > 0)
    #expect(AlertIdentity.assign(forExistingCount: 0) == AlertIdentity.all[0])
    #expect(AlertIdentity.assign(forExistingCount: count) == AlertIdentity.all[0])
    #expect(AlertIdentity.assign(forExistingCount: count + 1) == AlertIdentity.all[1 % count])
}

@MainActor
@Test("occurrences with the same reminder and fire time reconcile as one")
func reconciliationKeyMatchesLogicalFiring() throws {
    let reminderID = UUID()
    let fireAt = Date(timeIntervalSince1970: 1_700_000_000)

    let a = ScheduledOccurrence(reminderID: reminderID, fireAt: fireAt)
    let b = ScheduledOccurrence(reminderID: reminderID, fireAt: fireAt, state: .scheduled)
    let other = ScheduledOccurrence(reminderID: UUID(), fireAt: fireAt)

    #expect(a.reconciliationKey == b.reconciliationKey)
    #expect(a.reconciliationKey != other.reconciliationKey)
}
