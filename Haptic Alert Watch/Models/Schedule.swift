//
//  Schedule.swift
//  Haptic Alert Watch
//
//  The rule half of the rule/instance split (SPEC §4). A ScheduleType says
//  *when* a reminder should fire; it never records that a firing happened.
//

import Foundation

/// How a reminder recurs.
///
/// The distinction that matters is what a completion does to the next fire
/// time: `fixed` is anchored to the clock and ignores completions, while
/// `relativeToCompletion` re-anchors to the moment the user marked it done.
enum ScheduleType: Codable, Hashable, Sendable {
    /// Anchored to the clock. Deferral does NOT move future occurrences.
    /// `weekdays` uses `Calendar` weekday numbering (1 = Sunday); an empty
    /// set means every day.
    case fixed(times: [DateComponents], weekdays: Set<Int>)

    /// Anchored to last completion. Deferral does NOT move the anchor —
    /// only Done does. `anchorReset` optionally re-baselines daily to stop
    /// unbounded forward drift (SPEC §5.3).
    case relativeToCompletion(interval: TimeInterval, anchorReset: DateComponents?)

    /// Single firing, then done. No successor.
    case oneOff(date: Date)
}

/// What the user did when an alert fired.
///
/// `dismissed` is deliberately distinct from `done`: for a
/// completion-relative reminder the two produce different next-fire times,
/// and collapsing them silently breaks the user's cadence (SPEC §5.2).
enum CompletionAction: String, Codable, Sendable {
    case done, skipped, deferred, dismissed
}

/// Lifecycle of a materialized occurrence.
///
/// `orphaned` means the stored `alarmKitID` no longer resolves with
/// AlarmKit — reconciliation marks these rather than deleting them, so a
/// scheduling failure stays visible instead of vanishing (SPEC §6).
enum OccurrenceState: String, Codable, Sendable {
    case pending, scheduled, fired, resolved, orphaned
}
