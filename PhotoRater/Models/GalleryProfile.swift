import Foundation
import SwiftUI

struct GalleryProfile: Identifiable {
    let id: UUID = UUID()
    var name: String
    var photos: [RankedPhoto] = []
}
