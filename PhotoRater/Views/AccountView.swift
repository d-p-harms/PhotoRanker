import SwiftUI
import FirebaseAuth

struct AccountView: View {
    @StateObject private var pricingManager = PricingManager.shared

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Account")) {
                    if let user = AuthenticationService.shared.currentUser {
                        Text("User ID: \(user.uid)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Credits")) {
                    if pricingManager.isInitialized {
                        HStack {
                            Text(pricingManager.isUnlimited ? "Unlimited" : "Credits")
                            Spacer()
                            Text(pricingManager.isUnlimited ? "∞" : "\(pricingManager.userCredits)")
                                .foregroundColor(pricingManager.isUnlimited ? .green : .primary)
                        }
                    } else {
                        ProgressView()
                    }
                    Button("Restore Purchases") {
                        Task { await pricingManager.restorePurchases() }
                    }
                }

                Section {
                    Button("Sign Out") {
                        try? Auth.auth().signOut()
                    }
                }
            }
            .navigationTitle("Account")
        }
    }
}

#Preview {
    AccountView()
}
