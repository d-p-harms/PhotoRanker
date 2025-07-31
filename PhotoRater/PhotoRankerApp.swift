// PhotoRaterApp.swift
// Main app file

import SwiftUI
import Firebase

@main
struct PhotoRaterApp: App {
    
    init() {
        // Configure Firebase
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}
