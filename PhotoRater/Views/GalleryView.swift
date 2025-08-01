import SwiftUI

struct GalleryView: View {
    private let sampleImages = ["photo", "photo.fill", "photo.on.rectangle", "photo.circle"]
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(sampleImages, id: \.self) { name in
                        Image(systemName: name)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 100)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary)
                            )
                    }
                }
                .padding()
            }
            .navigationTitle("Gallery")
        }
    }
}

#Preview {
    GalleryView()
}
