//
//  PhotoTag.swift
//  PhotoRater
//
//  Created by David Harms on 4/18/25.
//
import Foundation

enum PhotoTag: String, Codable, CaseIterable {
    case social
    case activity
    case personality
    case confident
    case outdoors

    var emoji: String {
        switch self {
        case .social: return "👥"
        case .activity: return "🏄"
        case .personality: return "😊"
        case .confident: return "💪"
        case .outdoors: return "🌲"
        }
    }
}
