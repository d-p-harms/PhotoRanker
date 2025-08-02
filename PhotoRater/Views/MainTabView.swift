import SwiftUI

struct MainTabView: View {
    enum Tab {
        case analysis
        case gallery
        case account
    }

    @State private var selectedTab: Tab = .analysis

    var body: some View {
        TabView(selection: $selectedTab) {
            ContentView()
                .tabItem {
                    Label("Analysis", systemImage: "sparkles.magnifyingglass")
                }
                .tag(Tab.analysis)

            GalleryView()
                .tabItem {
                    Label("Gallery", systemImage: "photo.on.rectangle.angled")
                }
                .tag(Tab.gallery)

            AccountView()
                .tabItem {
                    Label("Account", systemImage: "person.crop.circle")
                }
                .tag(Tab.account)
        }
    }
}

#Preview {
    MainTabView()
}
