import SwiftUI

struct ProfileDetailView: View {
    @EnvironmentObject var gallery: GalleryManager
    var profile: GalleryProfile

    var body: some View {
        if let index = gallery.profiles.firstIndex(where: { $0.id == profile.id }) {
            let currentProfile = gallery.profiles[index]
            List {
                ForEach(currentProfile.photos) { photo in
                    GalleryPhotoCard(rankedPhoto: photo)
                        .listRowInsets(EdgeInsets())
                        .padding(.vertical, 4)
                }
                .onMove { offsets, dest in
                    gallery.movePhoto(at: offsets, to: dest, in: currentProfile)
                }
            }
            .listStyle(PlainListStyle())
            .navigationTitle(currentProfile.name)
            .toolbar { EditButton() }
        } else {
            Text("Profile not found")
        }
    }
}
