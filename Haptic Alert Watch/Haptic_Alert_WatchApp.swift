//
//  Haptic_Alert_WatchApp.swift
//  Haptic Alert Watch
//
//  Created by Kevin Spang on 8/24/26.
//

import SwiftUI
import SwiftData

@main
struct Haptic_Alert_WatchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            Reminder.self,
            CompletionEvent.self,
            AlertCategory.self,
            ScheduledOccurrence.self,
        ])
    }
}
