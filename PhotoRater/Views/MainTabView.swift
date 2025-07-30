import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            ContentView()
                .tabItem {
                    Label("Analyze", systemImage: "magnifyingglass")
                }

            GalleryView()
                .tabItem {
                    Label("Gallery", systemImage: "photo.on.rectangle")
                }

            AccountView()
                .tabItem {
                    Label("Account", systemImage: "person.crop.circle")
                }
        }
    }
}

#Preview {
    MainTabView()
}
