//
//  RankedPhoto.swift
//  PhotoRater
//
//  Created by David Harms on 4/18/25.
//
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
    
    init(image: UIImage, score: Double, tags: [PhotoTag]?, analysis: PhotoAnalysis? = nil) {
        self.id = UUID()
        self.fileName = "photo_\(Date().timeIntervalSince1970).jpg"
        self.storageURL = nil
        self.score = score
        self.tags = tags
        self.analysis = analysis
        self.localImage = image
    }
    
    init(from response: FirebaseResponse) {
        self.id = UUID()
        self.fileName = response.fileName
        self.storageURL = response.storageURL
        self.score = response.score
        self.tags = response.tags
        self.analysis = response.analysis
        self.localImage = nil
    }
}
