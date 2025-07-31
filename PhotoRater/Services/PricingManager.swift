import Foundation
import StoreKit
import FirebaseAuth
import FirebaseFirestore
import SwiftUI

@MainActor
class PricingManager: ObservableObject {
    @Published var userCredits: Int = 0
    @Published var isUnlimited: Bool = false
    @Published var isLoading: Bool = false
    @Published var products: [Product] = []
    @Published var isInitialized: Bool = false
    
    // CRITICAL: Separate purchased from free credits
    private var purchasedCredits: Int = 0
    private var freeCredits: Int = 0
    
    static let shared = PricingManager()
    private var updateListenerTask: Task<Void, Error>?
    
    // Launch promotion check
    var isLaunchPeriod: Bool {
        let launchDate = Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 24))!
        let promotionEnd = Calendar.current.date(byAdding: .day, value: 14, to: launchDate)!
        let now = Date()
        return now >= launchDate && now < promotionEnd
    }
    
    private init() {
        updateListenerTask = listenForTransactions()
        
        Task {
            await loadProducts()
            await restoreAllPurchasesFromApple() // CRITICAL: Always check Apple first
            await loadFreeCreditsFromFirebase()   // Then load free credits
            await MainActor.run {
                self.isInitialized = true
            }
        }
    }
    
    // STEP 1: Always restore purchases on app launch
    private func restoreAllPurchasesFromApple() async {
        print("🔄 Checking Apple for previous purchases...")
        
        do {
            // Sync with Apple's servers
            try await AppStore.sync()
            
            var totalPurchasedCredits = 0
            var hasUnlimitedPurchase = false
            
            // Check ALL transactions ever made by this Apple ID
            for await result in Transaction.all {
                do {
                    let transaction = try checkVerified(result)
                    
                    // Only count non-refunded transactions
                    guard !transaction.isUpgraded else { continue }
                    
                    if let productID = ProductID(rawValue: transaction.productID) {
                        if productID.tier.isUnlimited {
                            hasUnlimitedPurchase = true
                            print("✅ Restored unlimited access")
                        } else {
                            totalPurchasedCredits += productID.tier.credits
                            print("✅ Restored \(productID.tier.credits) credits from \(productID.rawValue)")
                        }
                    }
                } catch {
                    print("❌ Transaction verification failed: \(error)")
                }
            }
            
            await MainActor.run {
                self.purchasedCredits = totalPurchasedCredits
                self.isUnlimited = hasUnlimitedPurchase
                
                print("🎯 Total purchased credits restored: \(totalPurchasedCredits)")
                print("♾️ Unlimited access: \(hasUnlimitedPurchase)")
            }
            
        } catch {
            print("❌ Failed to restore from Apple: \(error)")
        }
    }
    
    // STEP 2: Load free credits from Firebase (these can be lost)
    private func loadFreeCreditsFromFirebase() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            await MainActor.run {
                self.freeCredits = self.isLaunchPeriod ? 15 : 3
                self.updateTotalCredits()
            }
            return
        }
        
        let db = Firestore.firestore()
        
        do {
            let document = try await db.collection("users").document(userId).getDocument()
            
            await MainActor.run {
                if let data = document.data() {
                    self.freeCredits = data["freeCredits"] as? Int ?? (self.isLaunchPeriod ? 15 : 3)
                } else {
                    // New user gets launch bonus
                    self.freeCredits = self.isLaunchPeriod ? 15 : 3
                    print("🆕 New user gets \(self.freeCredits) free credits")
                }
                self.updateTotalCredits()
            }
        } catch {
            await MainActor.run {
                print("❌ Error loading free credits: \(error)")
                self.freeCredits = self.isLaunchPeriod ? 15 : 3
                self.updateTotalCredits()
            }
        }
    }
    
    // STEP 3: Smart credit calculation
    private func updateTotalCredits() {
        if isUnlimited {
            userCredits = 999 // Show high number for unlimited
        } else {
            userCredits = purchasedCredits + freeCredits
        }
        
        print("📊 Credits updated: Total=\(userCredits) (Purchased=\(purchasedCredits) + Free=\(freeCredits))")
    }
    
    // STEP 4: Smart credit deduction (use free first)
    func deductCredits(count: Int) {
        guard !isUnlimited else { return }
        
        // Always use free credits first, preserve purchased credits
        if freeCredits >= count {
            freeCredits -= count
        } else {
            let remaining = count - freeCredits
            freeCredits = 0
            purchasedCredits = max(0, purchasedCredits - remaining)
        }
        
        updateTotalCredits()
        
        // Save updated free credits to Firebase
        Task {
            await saveFreeCreditsToFirebase()
        }
    }
    
    // STEP 5: Only save free credits to Firebase (purchased credits come from Apple)
    private func saveFreeCreditsToFirebase() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let db = Firestore.firestore()
        
        do {
            let updateData: [String: Any] = [
                "freeCredits": freeCredits,
                "lastUpdated": FieldValue.serverTimestamp(),
                // Don't save purchased credits - they come from Apple
            ]
            
            try await db.collection("users").document(userId).setData(updateData, merge: true)
            print("💾 Free credits saved: \(freeCredits)")
        } catch {
            print("❌ Error saving free credits: \(error)")
        }
    }
    
    // STEP 6: Handle new purchases
    func purchaseProduct(_ productID: ProductID) async {
        guard let product = products.first(where: { $0.id == productID.rawValue }) else {
            print("Product not found: \(productID.rawValue)")
            return
        }
        
        isLoading = true
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await handleSuccessfulPurchase(transaction, productID: productID)
                await transaction.finish()
                
            case .userCancelled:
                print("Purchase cancelled by user")
                
            case .pending:
                print("Purchase pending (e.g., parental approval)")
                
            @unknown default:
                print("Unknown purchase result")
            }
        } catch {
            print("Purchase failed: \(error)")
        }
        
        isLoading = false
    }
    
    private func handleSuccessfulPurchase(_ transaction: StoreKit.Transaction, productID: ProductID) async {
        await MainActor.run {
            if productID.tier.isUnlimited {
                self.isUnlimited = true
            } else {
                self.purchasedCredits += productID.tier.credits
                print("✅ Purchase successful: +\(productID.tier.credits) credits")
            }
            self.updateTotalCredits()
        }
        
        // No need to save to Firebase - Apple handles purchased credits
    }
    
    // STEP 7: Public restore function (for "Restore Purchases" button)
    func restorePurchases() async {
        await restoreAllPurchasesFromApple()
        await MainActor.run {
            self.updateTotalCredits()
        }
        print("🔄 Purchases restored successfully")
    }
    
    // STEP 8: Check if user can analyze photos
    func canAnalyzePhotos(count: Int) -> Bool {
        return isUnlimited || userCredits >= count
    }
    
    // STEP 9: Add free credits (from promo codes, etc.)
    func addFreeCredits(count: Int) {
        freeCredits += count
        updateTotalCredits()
        
        Task {
            await saveFreeCreditsToFirebase()
        }
    }
    
    // STEP 10: Set unlimited access
    func setUnlimitedAccess(until date: Date? = nil) {
        isUnlimited = true
        if userCredits < 999 {
            userCredits = 999 // Show high number for unlimited
        }
        Task {
            await saveFreeCreditsToFirebase()
        }
    }
    
    // STEP 11: Initialize new user
    func initializeNewUser() {
        let launchCredits = isLaunchPeriod ? 15 : 3
        freeCredits = launchCredits
        isUnlimited = false
        
        print("🎯 Initialized new user with \(freeCredits) credits")
        print("🎁 Launch promotion active: \(isLaunchPeriod)")
        
        updateTotalCredits()
        
        Task {
            await saveFreeCreditsToFirebase()
        }
    }
    
    // STEP 12: Load user credits (public method for compatibility)
    func loadUserCredits() async {
        await loadFreeCreditsFromFirebase()
    }
    
    // MARK: - Private Implementation
    
    private func loadProducts() async {
        do {
            let productIds = ProductID.allCases.map { $0.rawValue }
            let loadedProducts = try await Product.products(for: productIds)
            
            await MainActor.run {
                self.products = loadedProducts.sorted { $0.price < $1.price }
                print("Loaded \(self.products.count) products")
                for product in self.products {
                    print("Product: \(product.id) - \(product.displayName) - \(product.displayPrice)")
                }
            }
        } catch {
            print("Failed to load products: \(error)")
        }
    }
    
    private func listenForTransactions() -> Task<Void, Error> {
        return Task {
            for await result in StoreKit.Transaction.updates {
                do {
                    let transaction = try checkVerified(result)
                    
                    if let productID = ProductID(rawValue: transaction.productID) {
                        await handleSuccessfulPurchase(transaction, productID: productID)
                    }
                    
                    await transaction.finish()
                } catch {
                    print("Transaction verification failed: \(error)")
                }
            }
        }
    }
    
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw PhotoRaterError.storeKitVerificationFailed
        case .verified(let safe):
            return safe
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
}

// MARK: - Product Tier Extensions
extension ProductTier {
    var isUnlimited: Bool {
        return self == .unlimited
    }
}

// MARK: - Error Types
enum PhotoRaterError: Error, LocalizedError {
    case storeKitVerificationFailed
    case insufficientCredits
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .storeKitVerificationFailed:
            return "Purchase verification failed"
        case .insufficientCredits:
            return "Insufficient credits"
        case .networkError:
            return "Network connection error"
        }
    }
}
