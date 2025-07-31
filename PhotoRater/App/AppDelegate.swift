import UIKit
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage

class AppDelegate: NSObject, UIApplicationDelegate {
    private var authStateListener: AuthStateDidChangeListenerHandle?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Configure Firebase - minimal setup
        FirebaseApp.configure()
        print("🔥 Firebase configured successfully")
        
        // Connect to Firebase emulators when enabled
#if DEBUG
        if ProcessInfo.processInfo.environment["FIREBASE_EMULATORS"] == "1" {
            let host = "localhost"
            Auth.auth().useEmulator(withHost: host, port: 9099)
            Firestore.firestore().useEmulator(withHost: host, port: 8080)
            Functions.functions().useEmulator(withHost: host, port: 5001)
            Storage.storage().useEmulator(withHost: host, port: 9199)
            print("🔄 Using Firebase emulators")
        }
#endif

        // Configure Firestore settings for better performance
        configureFirestoreSettings()
        
        // Set up authentication state listener
        authStateListener = Auth.auth().addStateDidChangeListener { auth, user in
            if let user = user {
                print("✅ User authenticated: \(user.uid)")
                // Initialize user credits after authentication
                Task {
                    await PricingManager.shared.loadUserCredits()
                    await PricingManager.shared.restorePurchases()
                }
            } else {
                print("🔑 No user authenticated, signing in anonymously...")
                // Sign in anonymously to satisfy authentication requirements
                Auth.auth().signInAnonymously { authResult, error in
                    if let error = error {
                        print("❌ Error signing in anonymously: \(error.localizedDescription)")
                    } else if let user = authResult?.user {
                        print("✅ Successfully signed in anonymously: \(user.uid)")
                        // Initialize user credits after authentication
                        Task {
                            await PricingManager.shared.loadUserCredits()
                            await PricingManager.shared.restorePurchases()
                        }
                    }
                }
            }
        }
        
        return true
    }
    
    private func configureFirestoreSettings() {
        // Configure Firestore for optimal performance
        let db = Firestore.firestore()
        let settings = FirestoreSettings()
        
        // Enable offline persistence for better user experience
        settings.isPersistenceEnabled = true
        settings.cacheSizeBytes = 100 * 1024 * 1024 // 100MB cache
        
        db.settings = settings
        print("📊 Firestore configured with offline persistence")
    }
    
    deinit {
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }
}
