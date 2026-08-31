//
//  LaunchSmokeTests.swift
//  Haptic Alert WatchUITests
//
//  Guards the failure mode that cost real debugging time during the model
//  layer build: an invalid SwiftData schema compiles cleanly, installs
//  cleanly, and then traps inside ModelContainer during the first SwiftUI
//  view update. Unit tests don't catch it — they crash the host before
//  reporting — so this asserts the app reaches a usable state and stays there.
//

import XCTest

final class LaunchSmokeTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunchesAndStaysRunning() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.navigationBars["Alerts"].waitForExistence(timeout: 10),
            "App did not reach its main screen — most likely a SwiftData schema trap in ModelContainer."
        )

        // A schema trap can fire slightly after first render, so confirm the
        // process is still alive rather than trusting the first frame.
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(app.state, .runningForeground, "App terminated shortly after launch.")
    }
}
