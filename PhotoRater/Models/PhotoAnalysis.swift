// PhotoAnalysis.swift - Simplified version
import Foundation

struct PhotoAnalysis: Codable {
    let score: PhotoQuality
    let tags: String?
    let reason: [String]?
}
