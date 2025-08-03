import SwiftUI

struct ProfileDetailView: View {
    @EnvironmentObject var gallery: GalleryManager
    var profile: GalleryProfile

    var body: some View {
        if let index = gallery.profiles.firstIndex(where: { $0.id == profile.id }) {
            let currentProfile = gallery.profiles[index]
            List {
                ForEach(currentProfile.photos) { photo in
                    HStack {
                        if let image = photo.localImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipped()
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 80, height: 80)
                        }
                        Text(photo.fileName)
                            .lineLimit(1)
                    }
                }
                .onMove { offsets, dest in
                    gallery.movePhoto(at: offsets, to: dest, in: currentProfile)
                }
            }
            .navigationTitle(currentProfile.name)
            .toolbar { EditButton() }
        } else {
            Text("Profile not found")
        }
    }
}
