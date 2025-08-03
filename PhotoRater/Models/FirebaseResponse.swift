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
    let tags: [PhotoTag]?
    let reason: String?

    // Expanded analysis fields
    let visualQuality: Double?
    let attractivenessScore: Double?
    let datingAppealScore: Double?
    let swipeWorthiness: Double?

    let strengths: [String]?
    let improvements: [String]?
    let nextPhotoSuggestions: [String]?

    let technicalFeedback: TechnicalFeedback?
    let datingInsights: DatingInsights?
    let categorization: Categorization?
    let psychologicalInsights: PsychologicalInsights?
    let competitiveAnalysis: CompetitiveAnalysis?
    let strategicAdvice: StrategicAdvice?
}
