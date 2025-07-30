import SwiftUI

struct GalleryView: View {
    @StateObject private var galleryManager = GalleryManager.shared

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationView {
            Group {
                if galleryManager.photos.isEmpty {
                    Text("No analyzed photos yet")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(galleryManager.photos) { photo in
                                PhotoResultCard(rankedPhoto: photo)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Gallery")
        }
    }
}

#Preview {
    GalleryView()
}
