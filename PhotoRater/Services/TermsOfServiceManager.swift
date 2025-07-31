import Foundation

class TermsOfServiceManager {
    static let shared = TermsOfServiceManager()

    /// Increment this value whenever the terms text changes to force users to re-accept.
    private let currentVersion = 1
    private let acceptedKey = "AcceptedTermsVersion"
    private let defaults = UserDefaults.standard

    private init() {}

    /// Returns true if the user has accepted the current version of the terms.
    func hasAcceptedTerms() -> Bool {
        return defaults.integer(forKey: acceptedKey) >= currentVersion
    }

    /// Records acceptance of the current terms.
    func acceptTerms() {
        defaults.set(currentVersion, forKey: acceptedKey)
    }

    /// Returns the version of the terms the user previously accepted.
    func getTermsVersion() -> Int {
        return defaults.integer(forKey: acceptedKey)
    }
}
