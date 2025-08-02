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
            MainTabView()
                .environmentObject(GalleryManager.shared)
                .onAppear {
                    // Ensure Firebase is configured
                    if FirebaseApp.app() == nil {
                        FirebaseApp.configure()
                    }
                }
        }
    }
}

// Extension for handling app lifecycle events
extension PhotoRaterApp {
    private func setupAppearance() {
        // Configure global app appearance if needed
        UINavigationBar.appearance().largeTitleTextAttributes = [
            .foregroundColor: UIColor.label
        ]
    }
}
