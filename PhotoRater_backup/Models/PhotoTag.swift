//
//  PhotoTag.swift
//  PhotoRater
//
//  Created by David Harms on 4/18/25.
//
import Foundation

enum PhotoTag: String, Codable {
    case social
    case activity
    case personality
    
    var emoji: String {
        switch self {
        case .social: return "👥"
        case .activity: return "🏄"
        case .personality: return "😊"
        }
    }
}
