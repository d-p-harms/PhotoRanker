import Foundation
import UIKit

struct RankedPhoto: Identifiable, Codable {
    let id: UUID
    let fileName: String
    let storageURL: String?
    let score: Double
    let tags: [PhotoTag]?
    let reason: String?
    
    // Enhanced AI Analysis Data
    let detailedScores: DetailedScores?
    let technicalFeedback: TechnicalFeedback?
    let datingInsights: DatingInsights?
    let improvements: [String]?
    let strengths: [String]?
    let nextPhotoSuggestions: [String]?
    
    var localImage: UIImage?

    enum CodingKeys: String, CodingKey {
        case id
        case fileName
        case storageURL
        case score
        case tags
        case reason
        case detailedScores
        case technicalFeedback
        case datingInsights
        case improvements
        case strengths
        case nextPhotoSuggestions
    }
    
    // Simple initializer for backward compatibility
    init(image: UIImage, score: Double, tags: [PhotoTag]?, reason: String? = nil) {
        self.id = UUID()
        self.fileName = "photo_\(Date().timeIntervalSince1970).jpg"
        self.storageURL = nil
        self.score = score
        self.tags = tags
        self.reason = reason
        self.localImage = image
        
        // Default values for enhanced data
        self.detailedScores = nil
        self.technicalFeedback = nil
        self.datingInsights = nil
        self.improvements = nil
        self.strengths = nil
        self.nextPhotoSuggestions = nil
    }
    
    // Full initializer with all AI data
    init(id: UUID, fileName: String, storageURL: String, score: Double, tags: [PhotoTag], reason: String,
         detailedScores: DetailedScores? = nil,
         technicalFeedback: TechnicalFeedback? = nil,
         datingInsights: DatingInsights? = nil,
         improvements: [String]? = nil,
         strengths: [String]? = nil,
         nextPhotoSuggestions: [String]? = nil) {
        
        self.id = id
        self.fileName = fileName
        self.storageURL = storageURL
        self.score = score
        self.tags = tags
        self.reason = reason
        self.localImage = nil
        
        // Enhanced AI data
        self.detailedScores = detailedScores
        self.technicalFeedback = technicalFeedback
        self.datingInsights = datingInsights
        self.improvements = improvements
        self.strengths = strengths
        self.nextPhotoSuggestions = nextPhotoSuggestions
    }
    
    // Helper method to create a copy with updated reason
    func withUpdatedReason(_ newReason: String) -> RankedPhoto {
        return RankedPhoto(
            id: self.id,
            fileName: self.fileName,
            storageURL: self.storageURL ?? "",
            score: self.score,
            tags: self.tags ?? [],
            reason: newReason,
            detailedScores: self.detailedScores,
            technicalFeedback: self.technicalFeedback,
            datingInsights: self.datingInsights,
            improvements: self.improvements,
            strengths: self.strengths,
            nextPhotoSuggestions: self.nextPhotoSuggestions
        )
    }

    // Codable conformance (excluding localImage)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fileName = try container.decode(String.self, forKey: .fileName)
        storageURL = try container.decodeIfPresent(String.self, forKey: .storageURL)
        score = try container.decode(Double.self, forKey: .score)
        tags = try container.decodeIfPresent([PhotoTag].self, forKey: .tags)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        detailedScores = try container.decodeIfPresent(DetailedScores.self, forKey: .detailedScores)
        technicalFeedback = try container.decodeIfPresent(TechnicalFeedback.self, forKey: .technicalFeedback)
        datingInsights = try container.decodeIfPresent(DatingInsights.self, forKey: .datingInsights)
        improvements = try container.decodeIfPresent([String].self, forKey: .improvements)
        strengths = try container.decodeIfPresent([String].self, forKey: .strengths)
        nextPhotoSuggestions = try container.decodeIfPresent([String].self, forKey: .nextPhotoSuggestions)
        localImage = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(fileName, forKey: .fileName)
        try container.encodeIfPresent(storageURL, forKey: .storageURL)
        try container.encode(score, forKey: .score)
        try container.encodeIfPresent(tags, forKey: .tags)
        try container.encodeIfPresent(reason, forKey: .reason)
        try container.encodeIfPresent(detailedScores, forKey: .detailedScores)
        try container.encodeIfPresent(technicalFeedback, forKey: .technicalFeedback)
        try container.encodeIfPresent(datingInsights, forKey: .datingInsights)
        try container.encodeIfPresent(improvements, forKey: .improvements)
        try container.encodeIfPresent(strengths, forKey: .strengths)
        try container.encodeIfPresent(nextPhotoSuggestions, forKey: .nextPhotoSuggestions)
    }
}

struct DetailedScores: Codable {
    let overall: Double
    let visualQuality: Double
    let attractiveness: Double
    let datingAppeal: Double
    let swipeWorthiness: Double
    
    var averageScore: Double {
        return (visualQuality + attractiveness + datingAppeal + swipeWorthiness) / 4.0
    }
    
    var topCategory: String {
        let scores = [
            ("Visual Quality", visualQuality),
            ("Attractiveness", attractiveness),
            ("Dating Appeal", datingAppeal),
            ("Swipe Appeal", swipeWorthiness)
        ]
        return scores.max(by: { $0.1 < $1.1 })?.0 ?? "Overall"
    }
}

struct TechnicalFeedback: Codable {
    let lighting: String?
    let composition: String?
    let styling: String?
    
    var hasAnyFeedback: Bool {
        return lighting != nil || composition != nil || styling != nil
    }
}

struct DatingInsights: Codable {
    let personalityProjected: [String]?
    let demographicAppeal: String?
    let profileRole: String?
    
    var topPersonalityTraits: [String] {
        return Array((personalityProjected ?? []).prefix(3))
    }
}
