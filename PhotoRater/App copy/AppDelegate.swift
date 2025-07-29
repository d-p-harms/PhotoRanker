import UIKit
import FirebaseCore
import FirebaseAuth

class AppDelegate: NSObject, UIApplicationDelegate {
    private var authStateListener: AuthStateDidChangeListenerHandle?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Configure Firebase
        FirebaseApp.configure()
        
        // Set up authentication state listener
        authStateListener = Auth.auth().addStateDidChangeListener { auth, user in
            if let user = user {
                print("User authenticated: \(user.uid)")
                // Initialize user credits after authentication
                Task {
                    await PricingManager.shared.loadUserCredits()
                }
            } else {
                // Sign in anonymously to satisfy authentication requirements
                Auth.auth().signInAnonymously { authResult, error in
                    if let error = error {
                        print("Error signing in anonymously: \(error.localizedDescription)")
                    } else if let user = authResult?.user {
                        print("Successfully signed in anonymously: \(user.uid)")
                        // Initialize user credits after authentication
                        Task {
                            await PricingManager.shared.loadUserCredits()
                        }
                    }
                }
            }
        }
        
        return true
    }
    
    deinit {
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }
}
