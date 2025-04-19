import Foundation
import UIKit

struct RankedPhoto: Identifiable {
    let id: UUID
    let fileName: String
    let storageURL: String?
    let score: Double
    let tags: [PhotoTag]?
    let analysis: PhotoAnalysis?
    
    // Not persisted
    var localImage: UIImage?
    
    // Initializer for creating from a local image (for testing/simulation)
    init(image: UIImage, score: Double, tags: [PhotoTag]?, analysis: PhotoAnalysis? = nil) {
        self.id = UUID()
        self.fileName = "photo_\(Date().timeIntervalSince1970).jpg"
        self.storageURL = nil
        self.score = score
        self.tags = tags
        self.analysis = analysis
        self.localImage = image
    }
    
    // Main initializer for creating from Firebase response
    init(id: UUID, fileName: String, storageURL: String?, score: Double, tags: [PhotoTag]?, analysis: PhotoAnalysis?) {
        self.id = id
        self.fileName = fileName
        self.storageURL = storageURL
        self.score = score
        self.tags = tags
        self.analysis = analysis
        self.localImage = nil
    }
}
