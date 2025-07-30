import Foundation
import SwiftUI

@MainActor
class GalleryManager: ObservableObject {
    static let shared = GalleryManager()

    @Published private(set) var photos: [RankedPhoto] = []

    private let saveURL: URL = {
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return path.appendingPathComponent("gallery.json")
    }()

    private init() {
        load()
    }

    func add(_ newPhotos: [RankedPhoto]) {
        photos.insert(contentsOf: newPhotos, at: 0)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL) else { return }
        do {
            photos = try JSONDecoder().decode([RankedPhoto].self, from: data)
        } catch {
            print("Failed to load gallery: \(error)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(photos)
            try data.write(to: saveURL)
        } catch {
            print("Failed to save gallery: \(error)")
        }
    }
}
