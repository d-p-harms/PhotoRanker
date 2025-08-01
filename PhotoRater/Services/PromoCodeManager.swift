// PromoCodeManager.swift
// Updated with single secure promo code

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class PromoCodeManager: ObservableObject {
    static let shared = PromoCodeManager()
    
    @Published var isValidating = false
    @Published var redemptionMessage: String?
    @Published var isSuccess = false
    
    private let db = Firestore.firestore()
    
    // Single secure promo code
    private let promoCodes: [String: PromoCodeDetails] = [
        "K9X7M3P8Q2W5": PromoCodeDetails(
            credits: 999,
            description: "Unlimited Access",
            isUnlimited: true,
            expirationDate: Calendar.current.date(byAdding: .year, value: 2, to: Date())!,
            maxUses: 10
        )
    ]
    
    private init() {}
    
    // MARK: - Public Methods
    
    func redeemPromoCode(_ code: String) async -> PromoRedemptionResult {
        // Clear previous state
        await updateUI(isValidating: true, message: nil, success: false)
        
        // Validate input
        let cleanCode = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !cleanCode.isEmpty else {
            await updateUI(isValidating: false, message: "Please enter a promo code", success: false)
            return .failure("Empty code")
        }
        
        guard cleanCode.count >= 3 && cleanCode.count <= 20 else {
            await updateUI(isValidating: false, message: "Invalid promo code format", success: false)
            return .failure("Invalid format")
        }
        
        // Check if code exists
        guard let promoDetails = promoCodes[cleanCode] else {
            await updateUI(isValidating: false, message: "Invalid promo code", success: false)
            return .failure("Invalid promo code")
        }
        
        // Check expiration
        if Date() > promoDetails.expirationDate {
            await updateUI(isValidating: false, message: "This promo code has expired", success: false)
            return .failure("Promo code expired")
        }
        
        // Ensure user is authenticated
        guard let userId = await ensureAuthenticated() else {
            await updateUI(isValidating: false, message: "Authentication failed. Please try again.", success: false)
            return .failure("Authentication failed")
        }
        
        // Perform redemption
        do {
            try await performRedemption(userId: userId, code: cleanCode, promoDetails: promoDetails)
            
            // Success
            if promoDetails.isUnlimited {
                PricingManager.shared.setUnlimitedAccess(until: promoDetails.expirationDate)
                await updateUI(
                    isValidating: false,
                    message: "🎉 Unlimited credits activated! Enjoy unlimited photo analysis for 2 years.",
                    success: true
                )
            } else {
                PricingManager.shared.addCredits(count: promoDetails.credits)
                await updateUI(
                    isValidating: false,
                    message: "🎉 Success! Added \(promoDetails.credits) credits to your account.",
                    success: true
                )
            }
            
            // Refresh user credits
            await PricingManager.shared.loadUserCredits()
            
            return .success(promoDetails)
            
        } catch {
            let errorMessage = getReadableError(error)
            await updateUI(isValidating: false, message: errorMessage, success: false)
            return .failure(errorMessage)
        }
    }
    
    // Helper method to check if a code exists (for testing)
    func isValidCode(_ code: String) -> Bool {
        let upperCode = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return promoCodes[upperCode] != nil
    }
    
    // Get all available promo codes (for testing/admin purposes)
    func getAllPromoCodes() -> [String: PromoCodeDetails] {
        return promoCodes
    }
    
    // MARK: - Private Methods
    
    private func ensureAuthenticated() async -> String? {
        if let currentUser = Auth.auth().currentUser {
            print("✅ User already authenticated: \(currentUser.uid)")
            return currentUser.uid
        }
        
        // Try to sign in anonymously
        do {
            let result = try await Auth.auth().signInAnonymously()
            print("✅ Successfully authenticated user: \(result.user.uid)")
            return result.user.uid
        } catch {
            print("❌ Authentication failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func performRedemption(userId: String, code: String, promoDetails: PromoCodeDetails) async throws {
        // Check if user has already used this code
        let userPromoRef = db.collection("users").document(userId)
            .collection("redeemedPromoCodes").document(code)
        
        let userPromoDoc = try await userPromoRef.getDocument()
        
        if userPromoDoc.exists {
            throw PromoCodeError.alreadyRedeemed
        }
        
        // Check global usage limit
        let globalPromoRef = db.collection("promoCodes").document(code)
        let globalPromoDoc = try await globalPromoRef.getDocument()
        
        let currentUses = globalPromoDoc.data()?["uses"] as? Int ?? 0
        if currentUses >= promoDetails.maxUses {
            throw PromoCodeError.usageLimitReached
        }
        
        // Perform transaction
        _ = try await db.runTransaction { (transaction, errorPointer) in
            do {
                let userRef = self.db.collection("users").document(userId)
                let userDoc = try transaction.getDocument(userRef)
                
                let currentCredits = userDoc.data()?["credits"] as? Int ?? 0
                
                // Update user credits
                var userData: [String: Any] = [
                    "lastUpdated": FieldValue.serverTimestamp()
                ]
                
                if promoDetails.isUnlimited {
                    userData["isUnlimited"] = true
                    userData["unlimitedUntil"] = Timestamp(date: promoDetails.expirationDate)
                    userData["credits"] = 999
                } else {
                    userData["credits"] = currentCredits + promoDetails.credits
                }
                
                transaction.setData(userData, forDocument: userRef, merge: true)
                
                // Record user's redemption
                let redemptionData: [String: Any] = [
                    "redeemedAt": FieldValue.serverTimestamp(),
                    "creditsAdded": promoDetails.credits,
                    "isUnlimited": promoDetails.isUnlimited,
                    "description": promoDetails.description
                ]
                
                transaction.setData(redemptionData, forDocument: userPromoRef)
                
                // Update global usage count
                let globalData: [String: Any] = [
                    "uses": currentUses + 1,
                    "lastUsed": FieldValue.serverTimestamp(),
                    "description": promoDetails.description,
                    "maxUses": promoDetails.maxUses
                ]
                
                transaction.setData(globalData, forDocument: globalPromoRef, merge: true)
                
                return nil
                
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
        
        print("✅ Promo code \(code) redeemed successfully for user \(userId)")
    }
    
    private func updateUI(isValidating: Bool, message: String?, success: Bool) async {
        self.isValidating = isValidating
        self.redemptionMessage = message
        self.isSuccess = success
    }
    
    private func getReadableError(_ error: Error) -> String {
        if let promoError = error as? PromoCodeError {
            switch promoError {
            case .alreadyRedeemed:
                return "You've already used this promo code"
            case .usageLimitReached:
                return "This promo code has reached its usage limit"
            case .networkError:
                return "Network error. Please check your connection and try again."
            case .authenticationFailed:
                return "Authentication failed. Please restart the app and try again."
            }
        }
        
        // Handle Firestore errors
        let nsError = error as NSError
        
        switch nsError.code {
        case FirestoreErrorCode.unavailable.rawValue:
            return "Service temporarily unavailable. Please try again."
        case FirestoreErrorCode.deadlineExceeded.rawValue:
            return "Request timed out. Please try again."
        case FirestoreErrorCode.permissionDenied.rawValue:
            return "Permission denied. Please restart the app."
        case FirestoreErrorCode.notFound.rawValue:
            return "Account not found. Please restart the app."
        case FirestoreErrorCode.unauthenticated.rawValue:
            return "Authentication error. Please restart the app."
        default:
            let description = error.localizedDescription.lowercased()
            if description.contains("network") || description.contains("internet") {
                return "Network error. Please check your connection."
            } else if description.contains("timeout") {
                return "Request timed out. Please try again."
            } else {
                print("❌ Unhandled error: \(error.localizedDescription)")
                return "Something went wrong. Please try again."
            }
        }
    }
}

// MARK: - Supporting Types

struct PromoCodeDetails {
    let credits: Int
    let description: String
    let isUnlimited: Bool
    let expirationDate: Date
    let maxUses: Int
    
    var isExpired: Bool {
        return Date() > expirationDate
    }
    
    var formattedExpiration: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: expirationDate)
    }
}

enum PromoRedemptionResult {
    case success(PromoCodeDetails)
    case failure(String)
}

enum PromoCodeError: Error, LocalizedError {
    case alreadyRedeemed
    case usageLimitReached
    case networkError
    case authenticationFailed
    
    var errorDescription: String? {
        switch self {
        case .alreadyRedeemed:
            return "Promo code already redeemed"
        case .usageLimitReached:
            return "Promo code usage limit reached"
        case .networkError:
            return "Network error"
        case .authenticationFailed:
            return "Authentication failed"
        }
    }
}
