//
//  Haptic_Alert_WatchApp.swift
//  Haptic Alert Watch
//
//  Created by Kevin Spang on 8/24/26.
//

import SwiftUI
import CoreData

@main
struct Haptic_Alert_WatchApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
