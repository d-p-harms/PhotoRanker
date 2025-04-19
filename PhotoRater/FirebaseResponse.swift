//
//  FirebaseResponse.swift
//  PhotoRater
//
//  Created by David Harms on 4/18/25.
//

struct FirebaseResponse: Codable {
    let fileName: String
    let storageURL: String
    let score: Double
    let tags: [PhotoTag]
    let analysis: PhotoAnalysis
}
