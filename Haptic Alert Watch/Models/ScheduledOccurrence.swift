//
//  ScheduledOccurrence.swift
//  Haptic Alert Watch
//
//  The instance half of the rule/instance split: one materialized future
//  firing, mapped to one AlarmKit alarm.
//
//  These rows are disposable. Reconciliation *rebuilds* the desired set and
//  diffs against what's stored rather than mutating in place, so the
//  operation stays idempotent (SPEC §6). Held by `reminderID` rather than a
//  relationship for that reason — occurrences are derived data.
//

import Foundation
import SwiftData

@Model
final class ScheduledOccurrence {
    var id: UUID = UUID()
    var reminderID: UUID = UUID()
    var fireAt: Date = Date()
    /// nil until AlarmKit accepts the alarm. A non-nil value that no longer
    /// resolves means the occurrence is `.orphaned`.
    var alarmKitID: UUID?
    var state: OccurrenceState = OccurrenceState.pending

    init(
        id: UUID = UUID(),
        reminderID: UUID,
        fireAt: Date,
        alarmKitID: UUID? = nil,
        state: OccurrenceState = .pending
    ) {
        self.id = id
        self.reminderID = reminderID
        self.fireAt = fireAt
        self.alarmKitID = alarmKitID
        self.state = state
    }

    /// Identifies the same logical firing across a rebuild. Two occurrences
    /// match when they belong to the same reminder and fire at the same
    /// second — the basis for the reconciliation diff.
    var reconciliationKey: String {
        "\(reminderID.uuidString)@\(Int(fireAt.timeIntervalSince1970))"
    }
}
