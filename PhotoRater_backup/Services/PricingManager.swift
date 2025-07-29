// PricingManager.swift
// Production version with debug overrides removed

import Foundation
import StoreKit
import FirebaseAuth
import FirebaseFirestore

@MainActor
class PricingManager: ObservableObject {
    static let shared = PricingManager()
    
    @Published var userCredits: Int = 0
    @Published var isUnlimited: Bool = false
    @Published var isLoading = false
    @Published var products: [Product] = []
    @Published var isInitialized = false
    
    private var updateListenerTask: Task<Void, Error>? = nil
    
    // Updated pricing tiers
    enum PricingTier {
        case free          // 15 photos during 2-week launch, 3 after
        case starter       // $0.99 for 20 photos
        case value         // $4.99 for 120 photos
        
        var credits: Int {
            switch self {
            case .free: return 15  // Launch promo amount
            case .starter: return 20
            case .value: return 120
            }
        }
        
        var price: Double {
            switch self {
            case .free: return 0.00
            case .starter: return 0.99
            case .value: return 4.99
            }
        }
        
        var title: String {
            switch self {
            case .free: return "Launch Special"
            case .starter: return "Starter Pack"
            case .value: return "Best Value"
            }
        }
        
        var description: String {
            switch self {
            case .free: return "Perfect for trying our AI analysis"
            case .starter: return "Great for optimizing your profile"
            case .value: return "Best deal - analyze your entire photo collection"
            }
        }
        
        var costPerPhoto: Double {
            switch self {
            case .free: return 0.00
            case .starter: return 0.0495  // $0.0495 per photo
            case .value: return 0.0416    // $0.0416 per photo
            }
        }
        
        var savings: String? {
            switch self {
            case .value: return "Save 16%"
            default: return nil
            }
        }
    }
    
    // Updated In-App Purchase Product IDs
    enum ProductID: String, CaseIterable {
        case starter = "com.photorater.starter20"
        case value = "com.photorater.value120"
        
        var tier: PricingTier {
            switch self {
            case .starter: return .starter
            case .value: return .value
            }
        }
    }
    
    // 2-week launch promotion period
    private var isLaunchPeriod: Bool {
        let launchDate = Calendar.current.date(from: DateComponents(
            year: 2025,
            month: 8,    // August
            day: 10      // Launch day
        ))!
        
        let promotionEnd = Calendar.current.date(byAdding: .day, value: 14, to: launchDate)! // 2 weeks
        let now = Date()
        let isActive = now >= launchDate && now < promotionEnd
        
        print("📅 Launch Promotion Check:")
        print("   Launch Date: \(launchDate)")
        print("   End Date: \(promotionEnd)")
        print("   Current Date: \(now)")
        print("   Is Active: \(isActive)")
        
        return isActive
    }
    
    private init() {
        updateListenerTask = listenForTransactions()
        
        Task {
            await loadProducts()
            await loadUserCredits()
            await MainActor.run {
                self.isInitialized = true
            }
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    // MARK: - Public Methods
    
    func canAnalyzePhotos(count: Int) -> Bool {
        return isUnlimited || userCredits >= count
    }
    
    func deductCredits(count: Int) {
        if !isUnlimited {
            userCredits = max(0, userCredits - count)
            Task {
                await saveCreditsToFirebase()
            }
        }
    }
    
    func addCredits(count: Int) {
        userCredits += count
        Task {
            await saveCreditsToFirebase()
        }
    }
    
    func setUnlimitedAccess(until date: Date? = nil) {
        isUnlimited = true
        if userCredits < 999 {
            userCredits = 999 // Show high number for unlimited
        }
        Task {
            await saveCreditsToFirebase()
        }
    }
    
    func initializeNewUser() {
        let launchCredits = isLaunchPeriod ? 15 : 3
        userCredits = launchCredits
        isUnlimited = false
        
        print("🎯 Initialized new user with \(userCredits) credits")
        print("🎁 Launch promotion active: \(isLaunchPeriod)")
        if isLaunchPeriod {
            print("🎉 User gets 2-week launch special: 15 free analyses!")
            let endDate = Calendar.current.date(from: DateComponents(year: 2025, month: 8, day: 24))!
            print("🗓️ Promotion ends: \(DateFormatter.localizedString(from: endDate, dateStyle: .medium, timeStyle: .none))")
        }
        
        Task {
            await saveCreditsToFirebase()
        }
    }
    
    func loadUserCredits() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("No authenticated user, waiting...")
            return
        }
        
        let db = Firestore.firestore()
        
        do {
            let document = try await db.collection("users").document(userId).getDocument()
            
            await MainActor.run {
                if let data = document.data() {
                    self.userCredits = data["credits"] as? Int ?? (isLaunchPeriod ? 15 : 3)
                    self.isUnlimited = data["isUnlimited"] as? Bool ?? false
                    
                    // Check if unlimited access has expired
                    if self.isUnlimited, let unlimitedUntil = data["unlimitedUntil"] as? Timestamp {
                        if unlimitedUntil.dateValue() < Date() {
                            self.isUnlimited = false
                        }
                    }
                    
                    print("Loaded user credits: \(self.userCredits), unlimited: \(self.isUnlimited)")
                } else {
                    print("New user detected, initializing with \(isLaunchPeriod ? 15 : 3) credits")
                    self.initializeNewUser()
                }
            }
        } catch {
            await MainActor.run {
                print("Error loading credits: \(error.localizedDescription)")
                self.userCredits = isLaunchPeriod ? 15 : 3
                self.isUnlimited = false
            }
        }
    }
    
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
                
                // Handle successful purchase
                await handleSuccessfulPurchase(transaction, productID: productID)
                
                // Finish the transaction
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
    
    // MARK: - Private Methods
    
    private func loadProducts() async {
        do {
            let productIds = ProductID.allCases.map { $0.rawValue }
            let loadedProducts = try await Product.products(for: productIds)
            
            await MainActor.run {
                self.products = loadedProducts.sorted { product1, product2 in
                    return product1.price < product2.price
                }
                
                print("Loaded \(self.products.count) products")
                for product in self.products {
                    print("Product: \(product.id) - \(product.displayName) - \(product.displayPrice)")
                }
            }
        } catch {
            print("Failed to load products: \(error)")
        }
    }
    
    private func saveCreditsToFirebase() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let db = Firestore.firestore()
        
        do {
            var updateData: [String: Any] = [
                "credits": userCredits,
                "isUnlimited": isUnlimited,
                "lastUpdated": FieldValue.serverTimestamp()
            ]
            
            // If unlimited, set expiration date (optional)
            if isUnlimited {
                let expirationDate = Calendar.current.date(byAdding: .year, value: 1, to: Date())!
                updateData["unlimitedUntil"] = Timestamp(date: expirationDate)
            }
            
            try await db.collection("users").document(userId).setData(updateData, merge: true)
            
            print("Credits saved successfully: \(self.userCredits), unlimited: \(self.isUnlimited)")
        } catch {
            print("Error saving credits: \(error)")
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
    
    private func handleSuccessfulPurchase(_ transaction: StoreKit.Transaction, productID: ProductID) async {
        let creditsToAdd = productID.tier.credits
        
        await MainActor.run {
            self.userCredits += creditsToAdd
            print("Purchase successful: Added \(creditsToAdd) credits")
        }
        
        await saveCreditsToFirebase()
    }
    
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw PhotoRaterError.storeKitVerificationFailed
        case .verified(let safe):
            return safe
        }
    }
    
    // MARK: - Restore Purchases
    
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            print("Purchases restored successfully")
        } catch {
            print("Failed to restore purchases: \(error)")
        }
    }
}

// Custom error types for the app
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
