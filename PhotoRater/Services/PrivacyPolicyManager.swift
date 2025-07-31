import Foundation

class PrivacyPolicyManager {
    static let shared = PrivacyPolicyManager()

    private let acceptedKey = "PrivacyPolicyAcceptedVersion"
    private let currentVersion = 1

    private init() {}

    func hasAcceptedPrivacyPolicy() -> Bool {
        UserDefaults.standard.integer(forKey: acceptedKey) >= currentVersion
    }

    func acceptPrivacyPolicy() {
        UserDefaults.standard.set(currentVersion, forKey: acceptedKey)
    }

    func showPrivacyPolicy() -> Bool {
        !hasAcceptedPrivacyPolicy()
    }
}
