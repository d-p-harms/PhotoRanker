//
//  AppDelegate.swift
//  PhotoRater
//
//  Created by David Harms on 4/17/25.
//
import UIKit
import FirebaseCore
import FirebaseAuth

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Configure Firebase
        FirebaseApp.configure()
        
        // Sign in anonymously to satisfy authentication requirements
        Auth.auth().signInAnonymously { authResult, error in
            if let error = error {
                print("Error signing in anonymously: \(error.localizedDescription)")
            } else {
                print("Successfully signed in anonymously")
            }
        }
        
        return true
    }
}
