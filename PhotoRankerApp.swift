//
//  PhotoRankerApp.swift
//  PhotoRater
//
//  Created by David Harms on 4/18/25.
//

import SwiftUI
import FirebaseCore

@main
struct PhotoRaterApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
