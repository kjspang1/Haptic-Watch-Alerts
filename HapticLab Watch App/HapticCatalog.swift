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

/// A candidate alert identity: either a single system haptic or a short
/// sequence of them. Sequences are only playable while the app is
/// foreground-active (see SPEC §3.1) — this catalog exists to answer
/// whether patterns are *worth* pursuing, not to ship them as-is.
struct HapticPattern: Identifiable, Hashable {
    let id: String
    let label: String
    /// Delay *before* each step. First step usually 0.
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

    /// One entry per raw WKHapticType.
    static let singles: [HapticPattern] = Haptic.allCases.map {
        HapticPattern(id: $0.rawValue, label: $0.label, steps: [($0, 0)])
    }

    /// Sequences designed to differ in *rhythm and count*, not just texture —
    /// the hypothesis being that count is easier to perceive than timbre when
    /// you are distracted.
    static let sequences: [HapticPattern] = [
        HapticPattern(id: "seq.double", label: "Double Tap",
                      steps: [(.click, 0), (.click, 0.15)]),
        HapticPattern(id: "seq.triple", label: "Triple Tap",
                      steps: [(.click, 0), (.click, 0.15), (.click, 0.15)]),
        HapticPattern(id: "seq.longShort", label: "Long then Short",
                      steps: [(.notification, 0), (.click, 0.4)]),
        HapticPattern(id: "seq.rising", label: "Rising",
                      steps: [(.directionUp, 0), (.directionUp, 0.3)]),
        HapticPattern(id: "seq.falling", label: "Falling",
                      steps: [(.directionDown, 0), (.directionDown, 0.3)]),
        HapticPattern(id: "seq.heartbeat", label: "Heartbeat",
                      steps: [(.click, 0), (.click, 0.12), (.click, 0.5), (.click, 0.12)]),
    ]
}

enum QuizSet: String, CaseIterable {
    case singles, sequences, all

    var label: String {
        switch self {
        case .singles: "Singles"
        case .sequences: "Patterns"
        case .all: "Both"
        }
    }

    var patterns: [HapticPattern] {
        switch self {
        case .singles: HapticPattern.singles
        case .sequences: HapticPattern.sequences
        case .all: HapticPattern.singles + HapticPattern.sequences
        }
    }
}
