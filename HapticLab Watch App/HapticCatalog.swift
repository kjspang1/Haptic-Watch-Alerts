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

enum Haptic: String, CaseIterable, Identifiable, Codable {
    case notification
    case directionUp
    case directionDown
    case success
    case failure
    case retry
    case start
    case stop
    case click

    var id: String { rawValue }

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

    func play() {
        WKInterfaceDevice.current().play(wkType)
    }
}
