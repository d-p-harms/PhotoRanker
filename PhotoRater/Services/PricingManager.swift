// PricingManager.swift
// Fixed version with proper async/await handling

import Foundation
import StoreKit
import FirebaseAuth
import FirebaseFirestore

@MainActor
class PricingManager: ObservableObject {
    static let shared = PricingManager()
    
    @Published var userCredits: Int = 0
    @Published var isLoading = false
    @Published var products: [Product] = []
    @Published var isInitialized = false
    
    private var updateListenerTask: Task<Void, Error>? = nil
    
    // Pricing tiers
    enum PricingTier {
        case free          // 3 photos to try the service
        case starter       // $0.99 for 50 photos
        case value         // $4.99 for 350 photos
        
        var credits: Int {
            switch self {
            case .free: return 3
            case .starter: return 50
            case .value: return 350
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
            case .free: return "Try It Free"
            case .starter: return "Starter Pack"
            case .value: return "Best Value"
            }
        }
        
        var description: String {
            switch self {
            case .free: return "Perfect for testing our AI analysis"
            case .starter: return "Great value for optimizing your profile"
            case .value: return "Best deal - analyze hundreds of photos"
            }
        }
        
        var costPerPhoto: Double {
            switch self {
            case .free: return 0.00
            default: return price / Double(credits)
            }
        }
        
        var savings: String? {
            switch self {
            case .value: return "Save 30%"
            default: return nil
            }
        }
    }
    
    // In-App Purchase Product IDs
    enum ProductID: String, CaseIterable {
        case starter = "com.photorater.starter50"
        case value = "com.photorater.value350"
        
        var tier: PricingTier {
            switch self {
            case .starter: return .starter
            case .value: return .value
            }
        }
    }
    
    private init() {
        // Start listening for transaction updates
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
        return userCredits >= count
    }
    
    func deductCredits(count: Int) {
        userCredits = max(0, userCredits - count)
        Task {
            await saveCreditsToFirebase()
        }
    }
    
    func addCredits(count: Int) {
        userCredits += count
        Task {
            await saveCreditsToFirebase()
        }
    }
    
    func initializeNewUser() {
        userCredits = PricingTier.free.credits // 3 free photos
        Task {
            await saveCreditsToFirebase()
        }
    }
    
    // FIXED: Replaced loadUserCreditsSync with proper async handling
    func loadUserCredits() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            // If no user, wait for authentication then try again
            print("No authenticated user, waiting...")
            return
        }
        
        let db = Firestore.firestore()
        
        do {
            let document = try await db.collection("users").document(userId).getDocument()
            
            await MainActor.run {
                if let data = document.data() {
                    self.userCredits = data["credits"] as? Int ?? 3
                    print("Loaded user credits: \(self.userCredits)")
                } else {
                    // New user - initialize with free credits
                    print("New user detected, initializing with free credits")
                    self.userCredits = PricingTier.free.credits
                    Task {
                        await self.saveCreditsToFirebase()
                    }
                }
            }
        } catch {
            await MainActor.run {
                print("Error loading credits: \(error.localizedDescription)")
                // Default to free credits on error
                self.userCredits = 3
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
                    // Sort by price (starter first, then value)
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
            try await db.collection("users").document(userId).setData([
                "credits": userCredits,
                "lastUpdated": FieldValue.serverTimestamp()
            ], merge: true)
            
            print("Credits saved successfully: \(self.userCredits)")
        } catch {
            print("Error saving credits: \(error)")
        }
    }
    
    private func listenForTransactions() -> Task<Void, Error> {
        return Task {
            // Listen for transaction updates using StoreKit.Transaction
            for await result in StoreKit.Transaction.updates {
                do {
                    let transaction = try checkVerified(result)
                    
                    // Handle the transaction
                    if let productID = ProductID(rawValue: transaction.productID) {
                        await handleSuccessfulPurchase(transaction, productID: productID)
                    }
                    
                    // Finish the transaction
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
            // Update credits directly here to avoid nested async calls
            self.userCredits += creditsToAdd
            print("Purchase successful: Added \(creditsToAdd) credits")
        }
        
        // Save to Firebase separately
        await saveCreditsToFirebase()
    }
    
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        // Check whether the JWS passes StoreKit verification
        switch result {
        case .unverified:
            // StoreKit parses the JWS, but it fails verification
            throw StoreKitError.failedVerification
        case .verified(let safe):
            // The result is verified. Return the unwrapped value
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

// Custom StoreKit error for verification failures
enum StoreKitError: Error {
    case failedVerification
}
