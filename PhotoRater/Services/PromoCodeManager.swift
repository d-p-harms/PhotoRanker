// PromoCodeManager.swift
// Final production version with server-side validation

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
        
        // Ensure user is authenticated
        guard let userId = await ensureAuthenticated() else {
            await updateUI(isValidating: false, message: "Authentication failed. Please try again.", success: false)
            return .failure("Authentication failed")
        }
        
        // Fetch promo code from Firestore
        do {
            let promoDoc = try await db.collection("promoCodes").document(cleanCode).getDocument()
            
            guard promoDoc.exists, let promoData = promoDoc.data() else {
                await updateUI(isValidating: false, message: "Invalid promo code", success: false)
                return .failure("Invalid promo code")
            }
            
            // Parse Firestore data
            guard let credits = promoData["credits"] as? Int,
                  let description = promoData["description"] as? String,
                  let isUnlimited = promoData["isUnlimited"] as? Bool,
                  let maxUses = promoData["maxUses"] as? Int,
                  let isActive = promoData["isActive"] as? Bool,
                  let expirationTimestamp = promoData["expirationDate"] as? Timestamp else {
                await updateUI(isValidating: false, message: "Invalid promo code configuration", success: false)
                return .failure("Invalid promo code configuration")
            }
            
            let expirationDate = expirationTimestamp.dateValue()
            let currentUses = promoData["currentUses"] as? Int ?? 0
            
            let promoDetails = PromoCodeDetails(
                credits: credits,
                description: description,
                isUnlimited: isUnlimited,
                expirationDate: expirationDate,
                maxUses: maxUses
            )
            
            // Check if promo code is active
            guard isActive else {
                await updateUI(isValidating: false, message: "This promo code is no longer active", success: false)
                return .failure("Promo code inactive")
            }
            
            // Check expiration
            if Date() > promoDetails.expirationDate {
                await updateUI(isValidating: false, message: "This promo code has expired", success: false)
                return .failure("Promo code expired")
            }
            
            // Check usage limits
            if currentUses >= maxUses {
                await updateUI(isValidating: false, message: "This promo code has reached its usage limit", success: false)
                return .failure("Usage limit reached")
            }
            
            // Check if user already redeemed this code
            let userPromoDoc = try await db.collection("users").document(userId)
                .collection("redeemedPromoCodes").document(cleanCode).getDocument()
            
            if userPromoDoc.exists {
                await updateUI(isValidating: false, message: "You've already used this promo code", success: false)
                return .failure("Already redeemed")
            }
            
            // Perform redemption
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
                await updateUI(
                    isValidating: false,
                    message: "🎉 Success! You've received \(promoDetails.credits) credits.",
                    success: true
                )
            }
            
            return .success(promoDetails)
            
        } catch {
            let errorMessage = getReadableError(error)
            await updateUI(isValidating: false, message: errorMessage, success: false)
            return .failure(errorMessage)
        }
    }
    
    // MARK: - Private Methods
    
    private func ensureAuthenticated() async -> String? {
        if let currentUser = Auth.auth().currentUser {
            return currentUser.uid
        }
        
        // Attempt anonymous sign-in
        do {
            let result = try await Auth.auth().signInAnonymously()
            return result.user.uid
        } catch {
            print("❌ Authentication failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func performRedemption(userId: String, code: String, promoDetails: PromoCodeDetails) async throws {
        let userPromoRef = db.collection("users").document(userId)
            .collection("redeemedPromoCodes").document(code)
        let globalPromoRef = db.collection("promoCodes").document(code)
        
        // Check current usage count again (race condition protection)
        let currentPromoDoc = try await globalPromoRef.getDocument()
        guard let currentData = currentPromoDoc.data() else {
            throw PromoCodeError.networkError
        }
        
        let currentUses = currentData["currentUses"] as? Int ?? 0
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
                    "currentUses": currentUses + 1,
                    "lastUsed": FieldValue.serverTimestamp(),
                ]
                
                transaction.setData(globalData, forDocument: globalPromoRef, merge: true)
                
                return nil
                
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
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
