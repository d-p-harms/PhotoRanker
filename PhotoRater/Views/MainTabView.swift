import SwiftUI

struct MainTabView: View {
    enum Tab {
        case analyze
        case pricing
        case promo
    }

    @State private var selectedTab: Tab = .analyze

    var body: some View {
        TabView(selection: $selectedTab) {
            ContentView()
                .tabItem {
                    Label("Analyze", systemImage: "sparkles.magnifyingglass")
                }
                .tag(Tab.analyze)

            PricingView()
                .tabItem {
                    Label("Credits", systemImage: "bolt.fill")
                }
                .tag(Tab.pricing)

            PromoCodeView()
                .tabItem {
                    Label("Promo", systemImage: "ticket.fill")
                }
                .tag(Tab.promo)
        }
    }
}

#Preview {
    MainTabView()
}
