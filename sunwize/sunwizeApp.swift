//
//  sunwizeApp.swift
//  sunwize
//
//  Created by Anthony Greenall-Ota on 8/11/2025.
//

import SwiftUI

@main
struct sunwizeApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
