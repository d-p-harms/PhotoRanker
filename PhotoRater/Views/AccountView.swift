import SwiftUI
import FirebaseAuth

struct AccountView: View {
    @StateObject private var pricingManager = PricingManager.shared
    @State private var showingPricingView = false
    @State private var showingPromoCodeView = false

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

                    Button("Buy Credits") { showingPricingView = true }
                    Button("Redeem Promo Code") { showingPromoCodeView = true }
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
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showingPricingView) {
            PricingView()
        }
        .sheet(isPresented: $showingPromoCodeView) {
            PromoCodeView()
        }
    }
}

#Preview {
    AccountView()
}
