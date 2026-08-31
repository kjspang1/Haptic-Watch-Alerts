//
//  AlarmKitSpike.swift
//  Haptic Alert Watch
//
//  Throwaway spike to answer SPEC.md open question #2: what does the
//  forwarded alarm presentation look like on the Watch, and does the
//  Done vs. Dismiss distinction actually survive the trip? Delete once
//  the answer is captured in SPEC.md.
//

import SwiftUI
import AlarmKit
import AppIntents
import ActivityKit

enum AlarmSpikeLog {
    private static let key = "AlarmSpike.lastAction"

    static func record(_ action: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        UserDefaults.standard.set("\(action) at \(stamp)", forKey: key)
    }

    static var last: String? {
        UserDefaults.standard.string(forKey: key)
    }
}

struct SpikeDismissIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Dismiss"

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {}
    init(alarmID: String) { self.alarmID = alarmID }

    func perform() async throws -> some IntentResult {
        AlarmSpikeLog.record("STOP button tapped")
        return .result()
    }
}

struct SpikeDoneIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Done"

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {}
    init(alarmID: String) { self.alarmID = alarmID }

    func perform() async throws -> some IntentResult {
        // secondaryButtonBehavior: .custom means the system does NOT stop the
        // alarm for us — without this the alarm keeps sounding on the iPhone
        // even after Done is tapped on the Watch.
        if let id = UUID(uuidString: alarmID) {
            try AlarmManager.shared.stop(id: id)
        }
        AlarmSpikeLog.record("DONE (secondary) button tapped")
        return .result()
    }
}

struct SpikeMetadata: AlarmMetadata {
    init() {}
}

/// Test sounds for the "can a custom sound reach the Watch?" question.
/// `oneLong` and `threeShort` differ in rhythm on purpose: if a pulsed
/// sound produces a pulsed *feel* on the wrist, then sound is the channel
/// that can carry alert identity (SPEC §3.1, §7.1).
enum SpikeSound: String, CaseIterable, Identifiable {
    case systemDefault, oneLong, threeShort

    var id: String { rawValue }

    var label: String {
        switch self {
        case .systemDefault: "System default"
        case .oneLong: "One long tone"
        case .threeShort: "Three short pips"
        }
    }

    var alertSound: AlertConfiguration.AlertSound {
        switch self {
        case .systemDefault: .default
        case .oneLong: .named("AlertOneLong.caf")
        case .threeShort: .named("AlertThreeShort.caf")
        }
    }
}

struct AlarmKitSpikeView: View {
    @State private var status = "Idle"
    @State private var lastAction = AlarmSpikeLog.last ?? "None yet"
    @State private var sound: SpikeSound = .threeShort

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Schedules a one-off alarm ~2 minutes out with a system Stop button plus a custom \"Done\" secondary button. Background the app, let it fire, and check what actually shows on the Watch.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Picker("Sound", selection: $sound) {
                    ForEach(SpikeSound.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Button("Schedule test alarm (2 min)") {
                    Task { await scheduleTestAlarm() }
                }
                .buttonStyle(.borderedProminent)

                Text(status)
                    .font(.callout)

                Divider()

                Text("Last recorded action (refresh after reopening the app):")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(lastAction)
                    .font(.body.monospaced())

                Button("Refresh") {
                    lastAction = AlarmSpikeLog.last ?? "None yet"
                }

                Spacer()
            }
            .padding()
            .navigationTitle("AlarmKit Spike")
        }
    }

    @MainActor
    private func scheduleTestAlarm() async {
        do {
            let state = try await AlarmManager.shared.requestAuthorization()
            guard state == .authorized else {
                status = "Not authorized: \(state)"
                return
            }

            let id = UUID()
            let fireDate = Date().addingTimeInterval(120)
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: fireDate)
            let minute = calendar.component(.minute, from: fireDate)

            let schedule = Alarm.Schedule.relative(
                .init(time: .init(hour: hour, minute: minute), repeats: .never)
            )

            let alert = AlarmPresentation.Alert(
                title: "Spike Test Alarm",
                secondaryButton: AlarmButton(text: "Done", textColor: .green, systemImageName: "checkmark.circle.fill"),
                secondaryButtonBehavior: .custom
            )

            let attributes = AlarmAttributes(
                presentation: AlarmPresentation(alert: alert),
                metadata: SpikeMetadata(),
                tintColor: .blue
            )

            let configuration = AlarmManager.AlarmConfiguration.alarm(
                schedule: schedule,
                attributes: attributes,
                stopIntent: SpikeDismissIntent(alarmID: id.uuidString),
                secondaryIntent: SpikeDoneIntent(alarmID: id.uuidString),
                sound: sound.alertSound
            )

            _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
            status = "Scheduled \(sound.label) for \(hour):\(String(format: "%02d", minute)) — background the app now and wait."
        } catch {
            status = "Error: \(error)"
        }
    }
}

#Preview {
    AlarmKitSpikeView()
}
