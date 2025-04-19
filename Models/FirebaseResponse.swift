//
//  FirebaseResponse.swift
//  PhotoRater
//
//  Created by David Harms on 4/19/25.
//
import Foundation
struct FirebaseResponse: Codable {
    let fileName: String
    let storageURL: String
    let score: Double
    let tags: [String]
    let analysis: ResponseAnalysis
}

struct ResponseAnalysis: Codable {
    let quality: ResponseQuality
    let composition: String?
    let lighting: String?
    let suggestions: [String]?
}

struct ResponseQuality: Codable {
    let overall: Double
    let clarity: Double
    let composition: Double
    let lighting: Double
}
