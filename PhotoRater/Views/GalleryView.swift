import SwiftUI

struct GalleryView: View {
    var body: some View {
        NavigationView {
            Text("Saved photos appear here")
                .navigationTitle("Gallery")
        }
    }
}

#Preview {
    GalleryView()
}
