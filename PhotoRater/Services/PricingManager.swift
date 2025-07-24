// PricingManager.swift
// Create new file: PhotoRater/Services/PricingManager.swift

import Foundation
import StoreKit
import FirebaseAuth
import FirebaseFirestore

class PricingManager: NSObject, ObservableObject {
    static let shared = PricingManager()
    
    @Published var userCredits: Int = 0
    @Published var isLoading = false
    
    private var products: [SKProduct] = []
    
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
    
    private override init() {
        super.init()
        SKPaymentQueue.default().add(self)
        loadProducts()
    }
    
    deinit {
        SKPaymentQueue.default().remove(self)
    }
    
    // MARK: - Public Methods
    
    func canAnalyzePhotos(count: Int) -> Bool {
        return userCredits >= count
    }
    
    func deductCredits(count: Int) {
        userCredits = max(0, userCredits - count)
        saveCreditsToFirebase()
    }
    
    func addCredits(count: Int) {
        userCredits += count
        saveCreditsToFirebase()
    }
    
    func initializeNewUser() {
        userCredits = PricingTier.free.credits // 3 free photos
        saveCreditsToFirebase()
    }
    
    func loadUserCredits() {
        guard let userId = Auth.auth().currentUser?.uid else {
            // If no user, wait for authentication then initialize
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.loadUserCredits()
            }
            return
        }
        
        let db = Firestore.firestore()
        db.collection("users").document(userId).getDocument { snapshot, error in
            DispatchQueue.main.async {
                if let data = snapshot?.data() {
                    self.userCredits = data["credits"] as? Int ?? 3
                    print("Loaded user credits: \(self.userCredits)")
                } else if error == nil {
                    // New user - initialize with free credits
                    print("New user detected, initializing with free credits")
                    self.initializeNewUser()
                } else {
                    print("Error loading credits: \(error?.localizedDescription ?? "Unknown error")")
                    // Default to free credits on error
                    self.userCredits = 3
                }
            }
        }
    }
    
    func purchaseProduct(_ productID: ProductID) {
        guard let product = products.first(where: { $0.productIdentifier == productID.rawValue }) else {
            print("Product not found: \(productID.rawValue)")
            return
        }
        
        let payment = SKPayment(product: product)
        SKPaymentQueue.default().add(payment)
        isLoading = true
    }
    
    // MARK: - Private Methods
    
    private func loadProducts() {
        let productIDs = Set(ProductID.allCases.map { $0.rawValue })
        let request = SKProductsRequest(productIdentifiers: productIDs)
        request.delegate = self
        request.start()
    }
    
    private func saveCreditsToFirebase() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let db = Firestore.firestore()
        db.collection("users").document(userId).setData([
            "credits": userCredits,
            "lastUpdated": FieldValue.serverTimestamp()
        ], merge: true) { error in
            if let error = error {
                print("Error saving credits: \(error)")
            } else {
                print("Credits saved successfully: \(self.userCredits)")
            }
        }
    }
}

// MARK: - SKProductsRequestDelegate
extension PricingManager: SKProductsRequestDelegate {
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        DispatchQueue.main.async {
            self.products = response.products
            print("Loaded \(self.products.count) products")
            for product in self.products {
                print("Product: \(product.productIdentifier) - \(product.localizedTitle) - \(product.price)")
            }
        }
    }
    
    func request(_ request: SKRequest, didFailWithError error: Error) {
        print("Product request failed: \(error)")
    }
}

// MARK: - SKPaymentTransactionObserver
extension PricingManager: SKPaymentTransactionObserver {
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            switch transaction.transactionState {
            case .purchased:
                handlePurchase(transaction)
                SKPaymentQueue.default().finishTransaction(transaction)
            case .failed:
                handleFailedPurchase(transaction)
                SKPaymentQueue.default().finishTransaction(transaction)
            case .restored:
                handleRestore(transaction)
                SKPaymentQueue.default().finishTransaction(transaction)
            case .deferred, .purchasing:
                break
            @unknown default:
                break
            }
        }
    }
    
    private func handlePurchase(_ transaction: SKPaymentTransaction) {
        guard let productID = ProductID(rawValue: transaction.payment.productIdentifier) else {
            print("Unknown product purchased: \(transaction.payment.productIdentifier)")
            DispatchQueue.main.async {
                self.isLoading = false
            }
            return
        }
        
        let creditsToAdd = productID.tier.credits
        
        DispatchQueue.main.async {
            self.addCredits(count: creditsToAdd)
            self.isLoading = false
            print("Purchase successful: Added \(creditsToAdd) credits")
        }
    }
    
    private func handleFailedPurchase(_ transaction: SKPaymentTransaction) {
        DispatchQueue.main.async {
            self.isLoading = false
            if let error = transaction.error as? SKError {
                if error.code != .paymentCancelled {
                    print("Purchase failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func handleRestore(_ transaction: SKPaymentTransaction) {
        handlePurchase(transaction)
    }
}
