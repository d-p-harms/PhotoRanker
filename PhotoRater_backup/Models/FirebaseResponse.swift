//
//  FirebaseResponse.swift
//  PhotoRater
//
//  Created by David Harms on 4/18/25.
//

import Foundation

struct FirebaseResponse: Codable {
    let fileName: String
    let storageURL: String
    let score: Double
    let tags: [PhotoTag]
    let reason: String
}
