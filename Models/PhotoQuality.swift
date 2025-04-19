//
//  PhotoQuality.swift
//  PhotoRater
//
//  Created by David Harms on 4/19/25.
//
import Foundation
// Models/PhotoQuality.swift
struct PhotoQuality: Codable {
    let overall: Double
    let clarity: Double
    let composition: Double
    let lighting: Double
}
