import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            ContentView()
                .tabItem {
                    Label("Analyze", systemImage: "magnifyingglass")
                }

            PricingView()
                .tabItem {
                    Label("Credits", systemImage: "bolt.fill")
                }

            PromoCodeView()
                .tabItem {
                    Label("Promo", systemImage: "gift.fill")
                }
        }
    }
}

#Preview {
    MainTabView()
}
