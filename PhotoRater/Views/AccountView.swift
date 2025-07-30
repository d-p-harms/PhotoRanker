import SwiftUI

struct AccountView: View {
    var body: some View {
        NavigationView {
            List {
                NavigationLink("Credits") {
                    PricingView()
                }
                NavigationLink("Promo Codes") {
                    PromoCodeView()
                }
                NavigationLink("Settings") {
                    Text("Settings coming soon")
                }
                NavigationLink("Purchase History") {
                    Text("Purchase history coming soon")
                }
            }
            .navigationTitle("Account")
        }
    }
}

#Preview {
    AccountView()
}
