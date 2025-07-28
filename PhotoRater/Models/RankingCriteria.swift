//
//  RankingCriteria.swift
//  PhotoRater
//
//  Created by David Harms on 4/18/25.
//
import Foundation

enum RankingCriteria: String, CaseIterable {
    case best
    case social
    case activity
    case personality
    case balanced
    
    var title: String {
        switch self {
        case .best: return "Best Overall"
        case .social: return "Social Photos"
        case .activity: return "Activity/Hobby"
        case .personality: return "Personality"
        case .balanced: return "Balanced Set"
        }
    }
    
    var icon: String {
        switch self {
        case .best: return "trophy"
        case .social: return "person.2"
        case .activity: return "figure.wave"
        case .personality: return "face.smiling"
        case .balanced: return "camera"
        }
    }
    
    var description: String {
        switch self {
        case .best:
            return "Selects your highest quality photos based on overall appeal for dating profiles."
        case .social:
            return "Prioritizes photos showing you with friends, at gatherings, or social events."
        case .activity:
            return "Prioritizes photos that show you engaged in activities or hobbies."
        case .personality:
            return "Prioritizes photos that highlight your unique personality traits."
        case .balanced:
            return "Creates a diverse selection with 2 social photos, 2 activity photos, and 2 personality photos for a well-rounded dating profile that appeals to different people."
        }
    }
}
