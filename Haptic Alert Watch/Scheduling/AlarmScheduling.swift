//
//  AlarmScheduling.swift
//  Haptic Alert Watch
//
//  The boundary between our scheduling logic and AlarmKit. Everything above
//  this protocol is testable without a device; everything below it can only
//  be verified on hardware.
//

import Foundation
import AlarmKit
import ActivityKit
import AppIntents
import SwiftUI

/// What an alarm needs to be presented.
struct AlarmRequest: Equatable, Sendable {
    let occurrenceID: UUID
    let reminderID: UUID
    let title: String
    let fireAt: Date
    /// iPhone-only: the Watch substitutes its standard ping (SPEC §3.1).
    let soundID: String
    let tintColorHex: String
}

/// Raised when the system's undocumented alarm ceiling is hit, so callers
/// can shrink the window and retry rather than failing outward (SPEC §6).
struct AlarmLimitReached: Error {}

protocol AlarmScheduling: Sendable {
    /// Schedules one alarm, returning the AlarmKit ID to persist.
    /// Throws `AlarmLimitReached` when the system refuses more alarms.
    func schedule(_ request: AlarmRequest) async throws -> UUID
    func cancel(alarmKitID: UUID) async throws
    /// IDs AlarmKit still knows about, for orphan detection.
    func liveAlarmIDs() async -> Set<UUID>
}

// MARK: - AlarmKit implementation

struct AlarmKitScheduler: AlarmScheduling {
    func schedule(_ request: AlarmRequest) async throws -> UUID {
        let id = UUID()

        // "Done" is the custom secondary button. Verified on device: it
        // forwards to the Watch alongside the system Stop button, and the
        // intent must stop the alarm itself (SPEC §3.6).
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: request.title),
            secondaryButton: AlarmButton(
                text: "Done",
                textColor: .green,
                systemImageName: "checkmark.circle.fill"
            ),
            secondaryButtonBehavior: .custom
        )

        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: ReminderAlarmMetadata(),
            tintColor: Color(hex: request.tintColorHex) ?? .blue
        )

        let configuration = AlarmManager.AlarmConfiguration.alarm(
            schedule: .fixed(request.fireAt),
            attributes: attributes,
            stopIntent: DismissReminderIntent(
                occurrenceID: request.occurrenceID.uuidString,
                reminderID: request.reminderID.uuidString
            ),
            secondaryIntent: CompleteReminderIntent(
                occurrenceID: request.occurrenceID.uuidString,
                reminderID: request.reminderID.uuidString
            ),
            sound: request.soundID == "default" ? .default : .named(request.soundID)
        )

        do {
            _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
        } catch AlarmManager.AlarmError.maximumLimitReached {
            throw AlarmLimitReached()
        }
        return id
    }

    func cancel(alarmKitID: UUID) async throws {
        // Already-gone alarms are not an error — reconciliation is meant to
        // converge, not to insist the world matched its expectations.
        try? AlarmManager.shared.cancel(id: alarmKitID)
    }

    func liveAlarmIDs() async -> Set<UUID> {
        // `alarmUpdates` is a stream, so read the first emission: it carries
        // the current set of alarms AlarmKit still knows about.
        for await alarms in AlarmManager.shared.alarmUpdates {
            return Set(alarms.map(\.id))
        }
        return []
    }
}

struct ReminderAlarmMetadata: AlarmMetadata {
    init() {}
}

extension Color {
    /// Parses "#RRGGBB". Returns nil rather than guessing on bad input.
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
