import Foundation
import UIKit

struct RankedPhoto: Identifiable {
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
    let categorization: Categorization?
    let psychologicalInsights: PsychologicalInsights?
    let competitiveAnalysis: CompetitiveAnalysis?
    
    var localImage: UIImage?
    
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
        self.categorization = nil
        self.psychologicalInsights = nil
        self.competitiveAnalysis = nil
    }
    
    // Full initializer with all AI data
    init(id: UUID, fileName: String, storageURL: String, score: Double, tags: [PhotoTag], reason: String,
         detailedScores: DetailedScores? = nil,
         technicalFeedback: TechnicalFeedback? = nil,
         datingInsights: DatingInsights? = nil,
         improvements: [String]? = nil,
         strengths: [String]? = nil,
         nextPhotoSuggestions: [String]? = nil,
         categorization: Categorization? = nil,
         psychologicalInsights: PsychologicalInsights? = nil,
         competitiveAnalysis: CompetitiveAnalysis? = nil) {
        
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
        self.categorization = categorization
        self.psychologicalInsights = psychologicalInsights
        self.competitiveAnalysis = competitiveAnalysis
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
            nextPhotoSuggestions: self.nextPhotoSuggestions,
            categorization: self.categorization,
            psychologicalInsights: self.psychologicalInsights,
            competitiveAnalysis: self.competitiveAnalysis
        )
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

struct Categorization: Codable {
    let socialScore: Double
    let activityScore: Double
    let personalityScore: Double
    let primaryCategory: String
    let categoryConfidence: Double
}

struct PsychologicalInsights: Codable {
    let confidence: [String]?
    let authenticity: String?
    let emotionalIntelligence: String?
    let marketPositioning: String?
    let psychologicalImpact: String?
    let trustworthiness: String?
    let approachability: String?
}

struct CompetitiveAnalysis: Codable {
    let uniqueElements: [String]?
    let marketAdvantages: [String]?
    let improvementPotential: [String]?
}
