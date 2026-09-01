//
//  ReminderIntents.swift
//  Haptic Alert Watch
//
//  The alarm buttons. These may run while the app is backgrounded or not
//  running at all, so they reach the store through `AppModelContainer`
//  rather than a SwiftUI environment.
//

import Foundation
import AppIntents
import AlarmKit
import SwiftData

/// The one container shared by the app and by intents launched from an alarm.
enum AppModelContainer {
    static let shared: ModelContainer = {
        do {
            return try ModelContainer(
                for: Reminder.self, CompletionEvent.self,
                     AlertCategory.self, ScheduledOccurrence.self
            )
        } catch {
            // A container that cannot open means no reminder can be resolved
            // or rescheduled; failing loudly beats silently losing alarms.
            fatalError("Unable to open model container: \(error)")
        }
    }()
}

/// "Done" — the custom secondary button on the alarm.
///
/// ⚠️ `secondaryButtonBehavior: .custom` means the system does **not** stop
/// the alarm. Verified on device: without the explicit stop, tapping Done on
/// the Watch silences only the Watch while the iPhone keeps alarming
/// (SPEC §3.6). The stop must come first, before any work that could throw.
struct CompleteReminderIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mark Done"

    @Parameter(title: "Occurrence ID") var occurrenceID: String
    @Parameter(title: "Reminder ID") var reminderID: String

    init() {}
    init(occurrenceID: String, reminderID: String) {
        self.occurrenceID = occurrenceID
        self.reminderID = reminderID
    }

    func perform() async throws -> some IntentResult {
        await ReminderResolver.resolve(
            occurrenceID: occurrenceID, reminderID: reminderID, action: .done
        )
        return .result()
    }
}

/// The system Stop button. AlarmKit stops the alarm on both devices itself,
/// so this only records the outcome and re-plans.
struct DismissReminderIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Dismiss"

    @Parameter(title: "Occurrence ID") var occurrenceID: String
    @Parameter(title: "Reminder ID") var reminderID: String

    init() {}
    init(occurrenceID: String, reminderID: String) {
        self.occurrenceID = occurrenceID
        self.reminderID = reminderID
    }

    func perform() async throws -> some IntentResult {
        await ReminderResolver.resolve(
            occurrenceID: occurrenceID, reminderID: reminderID, action: .dismissed
        )
        return .result()
    }
}

enum ReminderResolver {
    /// Stops the alarm, records what the user did, then re-plans the window.
    @MainActor
    static func resolve(occurrenceID: String, reminderID: String, action: CompletionAction) async {
        let context = ModelContext(AppModelContainer.shared)

        guard let occurrenceUUID = UUID(uuidString: occurrenceID),
              let reminderUUID = UUID(uuidString: reminderID) else { return }

        let occurrence = (try? context.fetch(
            FetchDescriptor<ScheduledOccurrence>(
                predicate: #Predicate { $0.id == occurrenceUUID }
            )
        ))?.first

        // Stop first. Everything below is bookkeeping, and bookkeeping that
        // throws must never leave an alarm sounding.
        if action == .done, let alarmKitID = occurrence?.alarmKitID {
            try? AlarmManager.shared.stop(id: alarmKitID)
        }

        let reminder = (try? context.fetch(
            FetchDescriptor<Reminder>(predicate: #Predicate { $0.id == reminderUUID })
        ))?.first

        if let reminder {
            let event = CompletionEvent(
                scheduledFor: occurrence?.fireAt ?? .now,
                resolvedAt: .now,
                action: action
            )
            event.reminder = reminder
            context.insert(event)
        }

        occurrence?.state = .resolved

        try? context.save()

        await ReconciliationService(context: context).reconcile()
    }
}
