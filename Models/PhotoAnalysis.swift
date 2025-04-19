import Foundation

// Models/PhotoAnalysis.swift
struct PhotoAnalysis: Codable {
    let quality: PhotoQuality
    let composition: String?
    let lighting: String?
    let suggestions: [String]?
}
