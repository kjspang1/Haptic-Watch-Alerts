//
//  ScheduleEngineTests.swift
//  Haptic Alert WatchTests
//
//  SPEC §10 calls §5 "the part most likely to be subtly wrong", and a bug
//  here fires alarms at the wrong time — the worst failure this app has.
//  Everything is a pure function over injected dates, so it gets tested
//  exhaustively rather than sampled.
//

import Testing
import Foundation
@testable import Haptic_Alert_Watch

// A fixed calendar and clock so nothing depends on when the suite runs.
private let utc = TimeZone(identifier: "UTC")!

private var testCalendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = utc
    c.locale = Locale(identifier: "en_US_POSIX")
    return c
}

private func engine(
    deferral: TimeInterval = 9 * 60,
    grace: TimeInterval = 5 * 60
) -> ScheduleEngine {
    ScheduleEngine(calendar: testCalendar, deferralInterval: deferral, dismissalGrace: grace)
}

/// 2026-03-10 is a Tuesday (weekday 3).
private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
    testCalendar.date(from: DateComponents(
        timeZone: utc, year: y, month: mo, day: d, hour: h, minute: mi
    ))!
}

private func time(_ h: Int, _ m: Int) -> DateComponents {
    DateComponents(hour: h, minute: m)
}

// MARK: - Next fire: fixed (SPEC §5.1)

@Test("fixed daily schedule finds the next slot later the same day")
func fixedFindsLaterSlotToday() {
    let schedule = ScheduleType.fixed(times: [time(8, 0), time(20, 0)], weekdays: [])
    let next = engine().nextFire(for: schedule, now: date(2026, 3, 10, 9, 0))
    #expect(next == date(2026, 3, 10, 20, 0))
}

@Test("fixed daily schedule rolls to tomorrow once the day's slots have passed")
func fixedRollsToNextDay() {
    let schedule = ScheduleType.fixed(times: [time(8, 0), time(20, 0)], weekdays: [])
    let next = engine().nextFire(for: schedule, now: date(2026, 3, 10, 21, 0))
    #expect(next == date(2026, 3, 11, 8, 0))
}

@Test("fixed schedule respects the weekday filter")
func fixedRespectsWeekdays() {
    // Weekday 6 = Friday. From Tuesday, the next 8am Friday is the 13th.
    let schedule = ScheduleType.fixed(times: [time(8, 0)], weekdays: [6])
    let next = engine().nextFire(for: schedule, now: date(2026, 3, 10, 9, 0))
    #expect(next == date(2026, 3, 13, 8, 0))
}

@Test("fixed schedule picks the earliest across several weekdays")
func fixedPicksEarliestWeekday() {
    // Wednesday (4) and Friday (6); from Tuesday, Wednesday wins.
    let schedule = ScheduleType.fixed(times: [time(8, 0)], weekdays: [4, 6])
    let next = engine().nextFire(for: schedule, now: date(2026, 3, 10, 9, 0))
    #expect(next == date(2026, 3, 11, 8, 0))
}

@Test("fixed fire time is strictly after now, never equal")
func fixedIsStrictlyAfterNow() {
    let schedule = ScheduleType.fixed(times: [time(8, 0)], weekdays: [])
    // Exactly 08:00 must roll forward, or an alarm could re-fire instantly.
    let next = engine().nextFire(for: schedule, now: date(2026, 3, 10, 8, 0))
    #expect(next == date(2026, 3, 11, 8, 0))
}

@Test("fixed schedule with no times has no next fire")
func fixedWithNoTimesIsNil() {
    let next = engine().nextFire(for: .fixed(times: [], weekdays: []), now: date(2026, 3, 10))
    #expect(next == nil)
}

// MARK: - Next fire: completion-relative

@Test("relative schedule counts forward from the last completion")
func relativeUsesAnchor() {
    let schedule = ScheduleType.relativeToCompletion(interval: 3 * 3600, anchorReset: nil)
    let next = engine().nextFire(
        for: schedule,
        now: date(2026, 3, 10, 14, 0),
        anchor: date(2026, 3, 10, 13, 0)
    )
    #expect(next == date(2026, 3, 10, 16, 0))
}

@Test("relative schedule falls back to createdAt when never completed")
func relativeFallsBackToCreatedAt() {
    let schedule = ScheduleType.relativeToCompletion(interval: 3 * 3600, anchorReset: nil)
    let next = engine().nextFire(
        for: schedule,
        now: date(2026, 3, 10, 10, 0),
        anchor: nil,
        createdAt: date(2026, 3, 10, 9, 0)
    )
    #expect(next == date(2026, 3, 10, 12, 0))
}

@Test("anchorReset re-baselines the anchor after its daily boundary")
func anchorResetPreventsDrift() {
    // Every 4h, re-baselining at 08:00. Last completion was 21:00 yesterday,
    // which would otherwise put the next fire at 01:00 — the drift SPEC §5.3
    // exists to stop. Once 08:00 passes it becomes the anchor.
    let schedule = ScheduleType.relativeToCompletion(interval: 4 * 3600, anchorReset: time(8, 0))
    let next = engine().nextFire(
        for: schedule,
        now: date(2026, 3, 10, 9, 0),
        anchor: date(2026, 3, 9, 21, 0)
    )
    #expect(next == date(2026, 3, 10, 12, 0))
}

@Test("anchorReset does not override a completion made after the boundary")
func anchorResetYieldsToNewerCompletion() {
    // Completed at 10:00, after the 08:00 reset — the completion is newer,
    // so it stays the anchor and the reset must not pull the schedule back.
    let schedule = ScheduleType.relativeToCompletion(interval: 4 * 3600, anchorReset: time(8, 0))
    let next = engine().nextFire(
        for: schedule,
        now: date(2026, 3, 10, 11, 0),
        anchor: date(2026, 3, 10, 10, 0)
    )
    #expect(next == date(2026, 3, 10, 14, 0))
}

// MARK: - Next fire: one-off

@Test("one-off returns its date while future and nil once past")
func oneOffHasNoSuccessor() {
    let fireAt = date(2026, 3, 10, 12, 0)
    #expect(engine().nextFire(for: .oneOff(date: fireAt), now: date(2026, 3, 10, 11, 0)) == fireAt)
    #expect(engine().nextFire(for: .oneOff(date: fireAt), now: date(2026, 3, 10, 13, 0)) == nil)
}

// MARK: - Action semantics table (SPEC §5.2)

@Test("Done on a fixed schedule advances to the next clock slot")
func doneOnFixedAdvancesToClockSlot() {
    let schedule = ScheduleType.fixed(times: [time(8, 0), time(20, 0)], weekdays: [])
    let result = engine().resolution(for: .done, schedule: schedule, now: date(2026, 3, 10, 8, 5))
    #expect(result.nextFire == date(2026, 3, 10, 20, 0))
    #expect(result.movesAnchor == false)
}

@Test("Done on a relative schedule re-anchors to now")
func doneOnRelativeMovesAnchor() {
    let schedule = ScheduleType.relativeToCompletion(interval: 3 * 3600, anchorReset: nil)
    // Originally anchored at 13:00, but Done at 14:30 re-anchors there.
    let result = engine().resolution(
        for: .done, schedule: schedule,
        now: date(2026, 3, 10, 14, 30),
        anchor: date(2026, 3, 10, 13, 0)
    )
    #expect(result.nextFire == date(2026, 3, 10, 17, 30))
    #expect(result.movesAnchor == true)
}

@Test("Deferral re-fires shortly and never moves the anchor")
func deferralDoesNotMoveAnchor() {
    let schedule = ScheduleType.relativeToCompletion(interval: 3 * 3600, anchorReset: nil)
    let result = engine(deferral: 10 * 60).resolution(
        for: .deferred, schedule: schedule,
        now: date(2026, 3, 10, 14, 0),
        anchor: date(2026, 3, 10, 13, 0)
    )
    #expect(result.nextFire == date(2026, 3, 10, 14, 10))
    #expect(result.movesAnchor == false)
}

@Test("Deferring a fixed alarm leaves its future occurrences untouched")
func deferralOnFixedIsJustARefire() {
    let schedule = ScheduleType.fixed(times: [time(8, 0), time(20, 0)], weekdays: [])
    let result = engine(deferral: 10 * 60).resolution(
        for: .deferred, schedule: schedule, now: date(2026, 3, 10, 8, 0)
    )
    // The snooze itself, not the next clock slot.
    #expect(result.nextFire == date(2026, 3, 10, 8, 10))
    // 20:00 is still coming; deferral changed nothing about the rule.
    #expect(engine().nextFire(for: schedule, now: date(2026, 3, 10, 8, 10)) == date(2026, 3, 10, 20, 0))
}

@Test("Skip re-anchors a relative schedule just as Done does")
func skipTreatsNowAsAnchor() {
    let schedule = ScheduleType.relativeToCompletion(interval: 3 * 3600, anchorReset: nil)
    let result = engine().resolution(
        for: .skipped, schedule: schedule,
        now: date(2026, 3, 10, 14, 0),
        anchor: date(2026, 3, 10, 10, 0)
    )
    #expect(result.nextFire == date(2026, 3, 10, 17, 0))
    #expect(result.movesAnchor == true)
}

@Test("Dismissing a relative alert leaves the anchor and re-fires after a grace period")
func dismissalOnRelativeDoesNotAdvanceSchedule() {
    // The §5.2 ambiguity, resolved as "not done": dismissing must not
    // silently advance the cadence with no signal to the user.
    let schedule = ScheduleType.relativeToCompletion(interval: 3 * 3600, anchorReset: nil)
    let result = engine(grace: 5 * 60).resolution(
        for: .dismissed, schedule: schedule,
        now: date(2026, 3, 10, 14, 0),
        anchor: date(2026, 3, 10, 13, 0)
    )
    #expect(result.nextFire == date(2026, 3, 10, 14, 5))
    #expect(result.movesAnchor == false)
}

@Test("Dismissing a fixed alarm just advances to the next slot")
func dismissalOnFixedAdvances() {
    let schedule = ScheduleType.fixed(times: [time(8, 0), time(20, 0)], weekdays: [])
    let result = engine().resolution(for: .dismissed, schedule: schedule, now: date(2026, 3, 10, 8, 1))
    #expect(result.nextFire == date(2026, 3, 10, 20, 0))
    #expect(result.movesAnchor == false)
}

@Test("A resolved one-off has no successor, whichever way it ended")
func resolvedOneOffHasNoSuccessor() {
    let schedule = ScheduleType.oneOff(date: date(2026, 3, 10, 12, 0))
    let now = date(2026, 3, 10, 12, 1)
    for action in [CompletionAction.done, .skipped, .dismissed] {
        let result = engine().resolution(for: action, schedule: schedule, now: now)
        #expect(result.nextFire == nil, "\(action) should end a one-off")
        #expect(result.movesAnchor == false)
    }
}

@Test("Deferring a one-off brings it back rather than ending it")
func deferredOneOffStillReturns() {
    let schedule = ScheduleType.oneOff(date: date(2026, 3, 10, 12, 0))
    let result = engine(deferral: 9 * 60).resolution(
        for: .deferred, schedule: schedule, now: date(2026, 3, 10, 12, 0)
    )
    #expect(result.nextFire == date(2026, 3, 10, 12, 9))
}

// MARK: - Regression guards

@Test("repeated deferrals never drag a relative schedule forward")
func repeatedDeferralsDoNotDrift() {
    // The failure this guards: snoozing five times quietly turning a 3-hour
    // cadence into a 4-hour one, with nothing telling the user.
    let schedule = ScheduleType.relativeToCompletion(interval: 3 * 3600, anchorReset: nil)
    let anchor = date(2026, 3, 10, 13, 0)
    let eng = engine(deferral: 10 * 60)

    var now = date(2026, 3, 10, 16, 0)
    for _ in 0..<5 {
        let deferral = eng.resolution(for: .deferred, schedule: schedule, now: now, anchor: anchor)
        #expect(deferral.movesAnchor == false)
        now = deferral.nextFire!
    }

    // After 50 minutes of snoozing, Done re-anchors to that moment — and the
    // anchor only ever moved because of Done, never the deferrals.
    let done = eng.resolution(for: .done, schedule: schedule, now: now, anchor: anchor)
    #expect(done.nextFire == now.addingTimeInterval(3 * 3600))
    #expect(done.movesAnchor == true)
}

@Test("a fixed schedule survives a spring-forward DST transition")
func fixedSurvivesDSTSpringForward() throws {
    // US DST begins 2026-03-08. An 08:00 alarm must stay 08:00 local, which
    // is why next-fire uses Calendar matching rather than adding 86400.
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "America/New_York")!
    let eng = ScheduleEngine(calendar: cal)

    let beforeTransition = cal.date(from: DateComponents(
        year: 2026, month: 3, day: 7, hour: 9, minute: 0
    ))!
    let next = eng.nextFire(for: .fixed(times: [time(8, 0)], weekdays: []), now: beforeTransition)

    let components = cal.dateComponents([.year, .month, .day, .hour, .minute], from: try #require(next))
    #expect(components.day == 8)
    #expect(components.hour == 8)
    #expect(components.minute == 0)
}
