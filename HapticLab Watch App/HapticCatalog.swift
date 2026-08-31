//
//  HapticCatalog.swift
//  HapticLab Watch App
//
//  The nine WKHapticType values usable outside a session. The navigation
//  (.navigationLeftTurn, .navigationRightTurn, .navigationGenericManeuver)
//  and underwater depth types are deliberately excluded: the system only
//  plays them while an active navigation or depth session is running, so
//  they are not candidates for alert identities.
//

import Foundation
import WatchKit

enum Haptic: String, CaseIterable, Codable {
    case notification
    case directionUp
    case directionDown
    case success
    case failure
    case retry
    case start
    case stop
    case click

    var label: String {
        switch self {
        case .notification: "Notification"
        case .directionUp: "Direction Up"
        case .directionDown: "Direction Down"
        case .success: "Success"
        case .failure: "Failure"
        case .retry: "Retry"
        case .start: "Start"
        case .stop: "Stop"
        case .click: "Click"
        }
    }

    var wkType: WKHapticType {
        switch self {
        case .notification: .notification
        case .directionUp: .directionUp
        case .directionDown: .directionDown
        case .success: .success
        case .failure: .failure
        case .retry: .retry
        case .start: .start
        case .stop: .stop
        case .click: .click
        }
    }
}

/// Delivery timing for the burst style. One knob set, applied uniformly —
/// the pattern is not per-reminder configurable by design. Identity comes
/// from *which* haptic plays; the burst only makes it easier to notice.
enum BurstTiming {
    /// Taps per burst.
    static let tapsPerBurst = 3
    /// Gap between taps inside one burst.
    static let inBurstGap: TimeInterval = 0.25
    /// The "beat" of silence before the burst repeats.
    static let betweenBursts: TimeInterval = 0.7
    /// How many bursts to play in the lab. Real alerts would repeat until acknowledged.
    static let burstCount = 2
}

/// A candidate alert identity. Sequences are only playable while the app is
/// foreground-active (SPEC §3.1) — this catalog exists to answer whether the
/// burst delivery is *worth* pursuing, not to ship as-is.
struct HapticPattern: Identifiable, Hashable {
    let id: String
    let label: String
    let haptic: Haptic
    /// Delay *before* each step. First step is 0.
    let steps: [(haptic: Haptic, delay: TimeInterval)]

    static func == (a: HapticPattern, b: HapticPattern) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    func play() {
        Task {
            for step in steps {
                if step.delay > 0 {
                    try? await Task.sleep(for: .seconds(step.delay))
                }
                WKInterfaceDevice.current().play(step.haptic.wkType)
            }
        }
    }

    /// Baseline: one tap of the raw system haptic.
    static let singles: [HapticPattern] = Haptic.allCases.map {
        HapticPattern(id: $0.rawValue, label: $0.label, haptic: $0, steps: [($0, 0)])
    }

    /// The proposed delivery: N quick taps of the *same* haptic, a beat of
    /// silence, then repeat. Same identity as the single, louder presentation.
    static let bursts: [HapticPattern] = Haptic.allCases.map { haptic in
        var steps: [(haptic: Haptic, delay: TimeInterval)] = []
        for burst in 0..<BurstTiming.burstCount {
            for tap in 0..<BurstTiming.tapsPerBurst {
                let delay: TimeInterval = (burst == 0 && tap == 0)
                    ? 0
                    : (tap == 0 ? BurstTiming.betweenBursts : BurstTiming.inBurstGap)
                steps.append((haptic, delay))
            }
        }
        return HapticPattern(id: "burst.\(haptic.rawValue)",
                             label: haptic.label,
                             haptic: haptic,
                             steps: steps)
    }
}

/// Singles vs bursts is a straight A/B on the same nine identities — run
/// both and compare accuracy to see whether the burst delivery actually
/// buys distinguishability or just makes everything more noticeable.
enum QuizSet: String, CaseIterable {
    case singles, bursts

    var label: String {
        switch self {
        case .singles: "Singles"
        case .bursts: "Bursts"
        }
    }

    var patterns: [HapticPattern] {
        switch self {
        case .singles: HapticPattern.singles
        case .bursts: HapticPattern.bursts
        }
    }
}
