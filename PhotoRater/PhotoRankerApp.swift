// PhotoRaterApp.swift
// Main app file

import SwiftUI
import Firebase

@main
struct PhotoRaterApp: App {

    /// Register the ``AppDelegate`` to handle Firebase setup and other app
    /// lifecycle events.
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}
