import Foundation
import UIKit

struct RankedPhoto: Identifiable {
    let id: UUID
    let fileName: String
    let storageURL: String?
    let score: Double
    let tags: [PhotoTag]?
    let reason: String?
    
    var localImage: UIImage?
    
    init(image: UIImage, score: Double, tags: [PhotoTag]?, reason: String? = nil) {
        self.id = UUID()
        self.fileName = "photo_\(Date().timeIntervalSince1970).jpg"
        self.storageURL = nil
        self.score = score
        self.tags = tags
        self.reason = reason
        self.localImage = image
    }

    init(id: UUID, fileName: String, storageURL: String, score: Double, tags: [PhotoTag], reason: String) {
        self.id = id
        self.fileName = fileName
        self.storageURL = storageURL
        self.score = score
        self.tags = tags
        self.reason = reason
        self.localImage = nil
    }
}
