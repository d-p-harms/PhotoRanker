import Foundation
import SwiftUI

class GalleryManager: ObservableObject {
    static let shared = GalleryManager()
    @Published var profiles: [GalleryProfile]

    init() {
        self.profiles = [GalleryProfile(name: "Default")]
    }

    func addProfile(named name: String) {
        guard !name.isEmpty else { return }
        profiles.append(GalleryProfile(name: name))
    }

    func addPhoto(_ photo: RankedPhoto, to profile: GalleryProfile? = nil) {
        if let profile = profile, let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index].photos.append(photo)
        } else {
            profiles[0].photos.append(photo)
        }
    }

    func movePhoto(at offsets: IndexSet, to destination: Int, in profile: GalleryProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index].photos.move(fromOffsets: offsets, toOffset: destination)
    }
}
