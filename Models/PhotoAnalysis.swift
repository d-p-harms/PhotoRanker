//
//  PhotoAnalysis.swift
//  PhotoRater
//
//  Created by David Harms on 4/18/25.
//
import Foundation

struct PhotoAnalysis: Codable {
    let quality: PhotoQuality
    let composition: String?
    let lighting: String?
    let suggestions: [String]?
}

struct PhotoQuality: Codable {
    let overall: Double
    let clarity: Double
    let composition: Double
    let lighting: Double
}
