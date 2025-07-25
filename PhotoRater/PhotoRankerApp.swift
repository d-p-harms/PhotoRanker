//
//  PhotoRaterApp.swift
//  PhotoRater
//
//  Created by David Harms on 4/17/25.
//

import SwiftUI
import FirebaseCore

@main
struct PhotoRaterApp: App {
    // Register app delegate for Firebase setup
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
