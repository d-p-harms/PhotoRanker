// PromoCodeManager.swift
// Fixed version with proper error handling and integration

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
    
    // Predefined promo codes (you can also store these in Firebase)
    private let promoCodes: [String: PromoCodeDetails] = [
        "APPSTORE2025": PromoCodeDetails(
            credits: 999,
            description: "App Store Review - Unlimited Credits",
            isUnlimited: true,
            expirationDate: Calendar.current.date(byAdding: .month, value: 6, to: Date())!,
            maxUses: 100
        ),
        "LAUNCH50": PromoCodeDetails(
            credits: 50,
            description: "Launch Special - 50 Free Credits",
            isUnlimited: false,
            expirationDate: Calendar.current.date(byAdding: .month, value: 2, to: Date())!,
            maxUses: 1000
        ),
        "REVIEWER": PromoCodeDetails(
            credits: 999,
            description: "Reviewer Access - Unlimited",
            isUnlimited: true,
            expirationDate: Calendar.current.date(byAdding: .year, value: 1, to: Date())!,
            maxUses: 50
        ),
        "TESTFLIGHT": PromoCodeDetails(
            credits: 100,
            description: "TestFlight Beta - 100 Credits",
            isUnlimited: false,
            expirationDate: Calendar.current.date(byAdding: .month, value: 3, to: Date())!,
            maxUses: 500
        ),
        "UNLIMITED": PromoCodeDetails(
            credits: 999,
            description: "Unlimited Access",
            isUnlimited: true,
            expirationDate: Calendar.current.date(byAdding: .year, value: 1, to: Date())!,
            maxUses: 10
        )
    ]
    
    private init() {}
    
    func redeemPromoCode(_ code: String) async -> PromoRedemptionResult {
        guard let userId = Auth.auth().currentUser?.uid else {
            await updateUI(isValidating: false, message: "Please sign in first", success: false)
            return .failure("Please sign in first")
        }
        
        await updateUI(isValidating: true, message: nil, success: false)
        
        let upperCode = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if code exists
        guard let promoDetails = promoCodes[upperCode] else {
            await updateUI(isValidating: false, message: "Invalid promo code", success: false)
            return .failure("Invalid promo code")
        }
        
        // Check expiration
        if Date() > promoDetails.expirationDate {
            await updateUI(isValidating: false, message: "This promo code has expired", success: false)
            return .failure("Promo code expired")
        }
        
        do {
            // Check if user has already used this code
            let userPromoRef = db.collection("users").document(userId).collection("redeemedPromoCodes").document(upperCode)
            let promoDoc = try await userPromoRef.getDocument()
            
            if promoDoc.exists {
                await updateUI(isValidating: false, message: "You've already used this promo code", success: false)
                return .failure("Already redeemed")
            }
            
            // Check global usage limit
            let globalPromoRef = db.collection("promoCodes").document(upperCode)
            let globalDoc = try await globalPromoRef.getDocument()
            
            if let data = globalDoc.data(),
               let currentUses = data["uses"] as? Int,
               currentUses >= promoDetails.maxUses {
                await updateUI(isValidating: false, message: "This promo code has reached its usage limit", success: false)
                return .failure("Usage limit reached")
            }
            
            // Redeem the code
            try await db.runTransaction { transaction, errorPointer in
                // Update user's credits
                let userRef = self.db.collection("users").document(userId)
                let userDoc = try transaction.getDocument(userRef)
                
                let currentCredits = userDoc.data()?["credits"] as? Int ?? 0
                
                var updateData: [String: Any] = [
                    "lastUpdated": FieldValue.serverTimestamp()
                ]
                
                if promoDetails.isUnlimited {
                    updateData["isUnlimited"] = true
                    updateData["unlimitedUntil"] = promoDetails.expirationDate
                    updateData["credits"] = 999 // Show high number for unlimited
                } else {
                    updateData["credits"] = currentCredits + promoDetails.credits
                }
                
                transaction.updateData(updateData, forDocument: userRef)
                
                // Record redemption
                transaction.setData([
                    "redeemedAt": FieldValue.serverTimestamp(),
                    "creditsAdded": promoDetails.credits,
                    "isUnlimited": promoDetails.isUnlimited,
                    "description": promoDetails.description
                ], forDocument: userPromoRef)
                
                // Update global usage count
                let currentUses = globalDoc.data()?["uses"] as? Int ?? 0
                transaction.setData([
                    "uses": currentUses + 1,
                    "lastUsed": FieldValue.serverTimestamp()
                ], forDocument: globalPromoRef, merge: true)
                
                return nil
            }
            
            // Update local state
            if promoDetails.isUnlimited {
                PricingManager.shared.setUnlimitedAccess(until: promoDetails.expirationDate)
                await updateUI(isValidating: false, message: "🎉 Unlimited credits activated!", success: true)
            } else {
                PricingManager.shared.addCredits(count: promoDetails.credits)
                await updateUI(isValidating: false, message: "🎉 Added \(promoDetails.credits) credits to your account!", success: true)
            }
            
            return .success(promoDetails)
            
        } catch {
            await updateUI(isValidating: false, message: "Error redeeming code: \(error.localizedDescription)", success: false)
            return .failure(error.localizedDescription)
        }
    }
    
    private func updateUI(isValidating: Bool, message: String?, success: Bool) async {
        await MainActor.run {
            self.isValidating = isValidating
            self.redemptionMessage = message
            self.isSuccess = success
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
}

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
