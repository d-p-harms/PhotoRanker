// PromoCodeManager.swift
// Final production version with server-side validation

import Foundation
import FirebaseAuth
import FirebaseFunctions

@MainActor
class PromoCodeManager: ObservableObject {
    static let shared = PromoCodeManager()
    
    @Published var isValidating = false
    @Published var redemptionMessage: String?
    @Published var isSuccess = false
    
    private let functions = Functions.functions()
    
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
        guard await ensureAuthenticated() != nil else {
            await updateUI(isValidating: false, message: "Authentication failed. Please try again.", success: false)
            return .failure("Authentication failed")
        }

        // Redeem promo code via Cloud Function
        do {
            let result = try await functions.httpsCallable("redeemPromoCode").call(["code": cleanCode])

            guard let data = result.data as? [String: Any],
                  let credits = data["credits"] as? Int,
                  let description = data["description"] as? String,
                  let isUnlimited = data["isUnlimited"] as? Bool,
                  let expirationSeconds = data["expirationDate"] as? TimeInterval,
                  let maxUses = data["maxUses"] as? Int else {
                throw PromoCodeError.networkError
            }

            let expirationDate = Date(timeIntervalSince1970: expirationSeconds)

            let promoDetails = PromoCodeDetails(
                credits: credits,
                description: description,
                isUnlimited: isUnlimited,
                expirationDate: expirationDate,
                maxUses: maxUses
            )

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
        
        // Handle Firebase Functions errors
        let nsError = error as NSError

        if nsError.domain == FunctionsErrorDomain, let code = FunctionsErrorCode(rawValue: nsError.code) {
            switch code {
            case .alreadyExists:
                return "You've already used this promo code"
            case .notFound, .invalidArgument:
                return "Invalid promo code"
            case .failedPrecondition:
                return "This promo code is no longer active"
            case .resourceExhausted:
                return "This promo code has reached its usage limit"
            case .permissionDenied:
                return "Permission denied. Please restart the app."
            case .unauthenticated:
                return "Authentication error. Please restart the app."
            case .deadlineExceeded:
                return "Request timed out. Please try again."
            case .unavailable:
                return "Service temporarily unavailable. Please try again."
            default:
                break
            }
        }

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
