import SwiftUI

struct AccountView: View {
    var body: some View {
        NavigationView {
            List {
                NavigationLink("Credits", destination: PricingView())
                NavigationLink("Promo Code", destination: PromoCodeView())
                NavigationLink("Privacy Policy", destination: PrivacyPolicyView())
            }
            .navigationTitle("Account")
        }
    }
}
