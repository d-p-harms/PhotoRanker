// PhotoRaterApp.swift
// Main app file with App Check configuration

import SwiftUI
import Firebase
import FirebaseAppCheck

@main
struct PhotoRaterApp: App {
    
    init() {
        // Configure App Check for debug/simulator builds
        #if DEBUG || targetEnvironment(simulator)
        let providerFactory = AppCheckDebugProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)
        #else
        // Production App Check configuration
        let providerFactory = DeviceCheckProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)
        #endif
        
        // Configure Firebase
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .responsive()
        }
    }
}
