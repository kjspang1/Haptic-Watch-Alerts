//
//  ScheduleEngine.swift
//  Haptic Alert Watch
//
//  Next-fire calculation and the action-semantics table (SPEC §5).
//
//  Deliberately pure: no SwiftData, no AlarmKit, and no reading of the
//  system clock — `now` is always injected. SPEC §10 calls this the part
//  most likely to be subtly wrong, and bugs here fire alarms at the wrong
//  time, so it must be exhaustively testable without a device or UI.
//

import Foundation

/// What should happen after the user resolves an alert.
struct Resolution: Equatable, Sendable {
    /// When the reminder should next fire. `nil` means no successor —
    /// the reminder is finished (a resolved one-off).
    let nextFire: Date?
    /// Whether this action re-anchors a completion-relative schedule.
    /// Only Done and Skip do; deferral and dismissal deliberately do not
    /// (SPEC §5.2), or snoozing would walk the cadence forward silently.
    let movesAnchor: Bool
}

struct ScheduleEngine: Sendable {
    var calendar: Calendar
    /// How far out a deferral/snooze re-fires.
    var deferralInterval: TimeInterval
    /// How long after a bare dismissal a completion-relative reminder
    /// re-fires. Dismissal is treated as *not done*, so the reminder comes
    /// back rather than silently advancing the schedule (SPEC §5.2).
    var dismissalGrace: TimeInterval

    init(
        calendar: Calendar = .current,
        deferralInterval: TimeInterval = 9 * 60,
        dismissalGrace: TimeInterval = 5 * 60
    ) {
        self.calendar = calendar
        self.deferralInterval = deferralInterval
        self.dismissalGrace = dismissalGrace
    }

    // MARK: - Next fire (SPEC §5.1)

    /// The next time this schedule should fire, strictly after `now`.
    ///
    /// - Parameters:
    ///   - anchor: last anchoring completion, for `relativeToCompletion`.
    ///             Falls back to `createdAt` when the reminder has never
    ///             been completed.
    /// - Returns: `nil` when the schedule has no future firing.
    func nextFire(
        for schedule: ScheduleType,
        now: Date,
        anchor: Date? = nil,
        createdAt: Date = .distantPast
    ) -> Date? {
        switch schedule {
        case let .fixed(times, weekdays):
            return nextFixedFire(times: times, weekdays: weekdays, now: now)

        case let .relativeToCompletion(interval, anchorReset):
            let base = anchor ?? createdAt
            let effective = reanchored(base, reset: anchorReset, now: now)
            return effective.addingTimeInterval(interval)

        case let .oneOff(date):
            return date > now ? date : nil
        }
    }

    /// Next clock slot matching any of `times` on an allowed weekday.
    ///
    /// Uses `Calendar.nextDate(after:matching:)` rather than arithmetic so
    /// DST transitions and month boundaries are the calendar's problem, not
    /// ours. An empty `weekdays` means every day.
    private func nextFixedFire(times: [DateComponents], weekdays: Set<Int>, now: Date) -> Date? {
        guard !times.isEmpty else { return nil }

        var candidates: [Date] = []
        for time in times {
            var components = DateComponents()
            components.hour = time.hour
            components.minute = time.minute
            components.second = time.second ?? 0

            if weekdays.isEmpty {
                if let next = calendar.nextDate(
                    after: now, matching: components, matchingPolicy: .nextTime
                ) {
                    candidates.append(next)
                }
            } else {
                for weekday in weekdays {
                    var weekdayComponents = components
                    weekdayComponents.weekday = weekday
                    if let next = calendar.nextDate(
                        after: now, matching: weekdayComponents, matchingPolicy: .nextTime
                    ) {
                        candidates.append(next)
                    }
                }
            }
        }
        return candidates.min()
    }

    /// Applies daily re-baselining for `anchorReset` (SPEC §5.3).
    ///
    /// If a reset boundary has passed more recently than the last
    /// completion, that boundary becomes the anchor. This is what stops a
    /// relative schedule drifting later and later across a week.
    private func reanchored(_ base: Date, reset: DateComponents?, now: Date) -> Date {
        guard let reset else { return base }

        var components = DateComponents()
        components.hour = reset.hour
        components.minute = reset.minute
        components.second = reset.second ?? 0

        guard let mostRecentReset = calendar.nextDate(
            after: now, matching: components, matchingPolicy: .nextTime, direction: .backward
        ) else { return base }

        return mostRecentReset > base ? mostRecentReset : base
    }

    // MARK: - Action semantics (SPEC §5.2)

    /// What happens to the schedule when the user resolves an alert.
    ///
    /// The distinction that matters is completion-relative: Done re-anchors
    /// to `now`, while deferral and dismissal leave the anchor untouched.
    func resolution(
        for action: CompletionAction,
        schedule: ScheduleType,
        now: Date,
        anchor: Date? = nil,
        createdAt: Date = .distantPast
    ) -> Resolution {
        // A resolved one-off has no successor regardless of how it ended,
        // except a deferral, which is an explicit request to see it again.
        if case .oneOff = schedule, action != .deferred {
            return Resolution(nextFire: nil, movesAnchor: false)
        }

        switch action {
        case .done, .skipped:
            // Both re-anchor: the activity either happened, or the user
            // decided this cycle is over. Either way the clock restarts.
            let next = nextFire(for: schedule, now: now, anchor: now, createdAt: createdAt)
            return Resolution(nextFire: next, movesAnchor: isRelative(schedule))

        case .deferred:
            // Re-fire shortly. Future fixed occurrences are untouched, and a
            // relative anchor stays put until Done.
            return Resolution(
                nextFire: now.addingTimeInterval(deferralInterval),
                movesAnchor: false
            )

        case .dismissed:
            switch schedule {
            case .fixed:
                // Nobody cares which button was hit on a clock alarm.
                return Resolution(
                    nextFire: nextFire(for: schedule, now: now, anchor: anchor, createdAt: createdAt),
                    movesAnchor: false
                )
            case .relativeToCompletion:
                // Ambiguous by nature: dismissing isn't saying it's done.
                // Treat as not done, leave the anchor, come back shortly.
                return Resolution(
                    nextFire: now.addingTimeInterval(dismissalGrace),
                    movesAnchor: false
                )
            case .oneOff:
                return Resolution(nextFire: nil, movesAnchor: false)
            }
        }
    }

    private func isRelative(_ schedule: ScheduleType) -> Bool {
        if case .relativeToCompletion = schedule { return true }
        return false
    }
}
