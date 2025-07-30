//
//  PhotoDetailView.swift
//  PhotoRater
//
//  Updated to focus on qualitative feedback instead of numerical scores
//

import SwiftUI

struct PhotoDetailView: View {
    let rankedPhoto: RankedPhoto
    @Environment(\.presentationMode) var presentationMode
    @State private var loadedImage: UIImage?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Photo
                    photoView
                    
                    // Overall Quality Assessment
                    overallQualitySection
                    
                    // Quality Breakdown - Visual indicators instead of numbers
                    if let scores = rankedPhoto.detailedScores {
                        qualityBreakdownSection(scores)
                    }
                    
                    // Strengths
                    if let strengths = rankedPhoto.strengths, !strengths.isEmpty {
                        strengthsSection(strengths)
                    }
                    
                    // Improvements
                    if let improvements = rankedPhoto.improvements, !improvements.isEmpty {
                        improvementsSection(improvements)
                    }
                    
                    // Technical Feedback
                    if let technical = rankedPhoto.technicalFeedback, technical.hasAnyFeedback {
                        technicalFeedbackSection(technical)
                    }
                    
                    // Dating Insights
                    if let insights = rankedPhoto.datingInsights {
                        datingInsightsSection(insights)
                    }
                    
                    // Next Photo Suggestions
                    if let suggestions = rankedPhoto.nextPhotoSuggestions, !suggestions.isEmpty {
                        nextPhotoSuggestionsSection(suggestions)
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationTitle("Photo Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
        .navigationViewStyle(.stack)
        .onAppear {
            loadImageIfNeeded()
        }
    }
    
    private var photoView: some View {
        Group {
            if let localImage = rankedPhoto.localImage {
                Image(uiImage: localImage)
                    .resizable()
                    .scaledToFit()
            } else if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 250 * DeviceSizing.scale)
                    .overlay(
                        ProgressView()
                    )
            }
        }
        .frame(maxHeight: 300 * DeviceSizing.scale)
        .cornerRadius(12)
    }
    
    private var overallQualitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overall Assessment")
                .font(.headline)
                .fontWeight(.semibold)
            
            HStack {
                QualityIndicator(score: rankedPhoto.score)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(getQualityDescription(rankedPhoto.score))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(getQualityColor(rankedPhoto.score))
                    
                    Text(getDetailedQualityDescription(rankedPhoto.score))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func qualityBreakdownSection(_ scores: DetailedScores) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quality Breakdown")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 8) {
                QualityRow(title: "Visual Quality", score: scores.visualQuality, icon: "camera.fill", color: .blue)
                QualityRow(title: "Attractiveness", score: scores.attractiveness, icon: "heart.fill", color: .pink)
                QualityRow(title: "Dating Appeal", score: scores.datingAppeal, icon: "person.2.fill", color: .purple)
                QualityRow(title: "Profile Fit", score: scores.swipeWorthiness, icon: "hand.tap.fill", color: .green)
            }
            
            Text("Strongest area: \(scores.topCategory)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.blue)
                .padding(.top, 4)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func strengthsSection(_ strengths: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                Text("What's Working Well")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            ForEach(Array(strengths.enumerated()), id: \.offset) { index, strength in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                    
                    Text(strength)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func improvementsSection(_ improvements: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "target")
                    .foregroundColor(.orange)
                Text("Ways to Improve")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            ForEach(Array(improvements.enumerated()), id: \.offset) { index, improvement in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.orange)
                    
                    Text(improvement)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func technicalFeedbackSection(_ technical: TechnicalFeedback) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Technical Analysis")
                .font(.headline)
                .fontWeight(.semibold)
            
            if let lighting = technical.lighting {
                TechnicalFeedbackRow(title: "Lighting", feedback: lighting, icon: "lightbulb.fill")
            }
            
            if let composition = technical.composition {
                TechnicalFeedbackRow(title: "Composition", feedback: composition, icon: "viewfinder")
            }
            
            if let styling = technical.styling {
                TechnicalFeedbackRow(title: "Styling", feedback: styling, icon: "tshirt.fill")
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func datingInsightsSection(_ insights: DatingInsights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dating Profile Insights")
                .font(.headline)
                .fontWeight(.semibold)
            
            if let personality = insights.personalityProjected, !personality.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Personality Traits Shown:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(personality, id: \.self) { trait in
                                Text(trait.capitalized)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.2))
                                    .foregroundColor(.blue)
                                    .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                }
            }
            
            if let appeal = insights.demographicAppeal {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Appeals Most To:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(appeal)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            if let role = insights.profileRole {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Best Used As:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(role)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color.purple.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func nextPhotoSuggestionsSection(_ suggestions: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "camera.badge.plus")
                    .foregroundColor(.blue)
                Text("Next Photo Ideas")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                HStack(alignment: .top, spacing: 8) {
                    Text("💡")
                        .font(.subheadline)
                    
                    Text(suggestion)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
    
    // Helper functions for quality descriptions
    private func getQualityDescription(_ score: Double) -> String {
        switch score {
        case 90...100: return "Excellent Photo"
        case 80..<90: return "Great Photo"
        case 70..<80: return "Good Photo"
        case 60..<70: return "Fair Photo"
        default: return "Needs Improvement"
        }
    }
    
    private func getDetailedQualityDescription(_ score: Double) -> String {
        switch score {
        case 90...100: return "Outstanding quality - perfect for your profile"
        case 80..<90: return "High quality with strong dating appeal"
        case 70..<80: return "Good quality with some room for improvement"
        case 60..<70: return "Decent photo that could be enhanced"
        default: return "Consider retaking or major improvements"
        }
    }
    
    private func getQualityColor(_ score: Double) -> Color {
        switch score {
        case 80...100: return .green
        case 60...79: return .blue
        case 40...59: return .orange
        default: return .red
        }
    }
    
    private func loadImageIfNeeded() {
        guard rankedPhoto.localImage == nil,
              let urlString = rankedPhoto.storageURL,
              let url = URL(string: urlString) else { return }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let data = data, let image = UIImage(data: data) {
                    self.loadedImage = image
                }
            }
        }.resume()
    }
}

struct QualityIndicator: View {
    let score: Double
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                .frame(width: 60 * DeviceSizing.scale, height: 60 * DeviceSizing.scale)
            
            Circle()
                .trim(from: 0, to: score / 100)
                .stroke(getQualityColor(score), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .frame(width: 60 * DeviceSizing.scale, height: 60 * DeviceSizing.scale)
                .rotationEffect(.degrees(-90))
            
            Image(systemName: getQualityIcon(score))
                .font(.title2)
                .foregroundColor(getQualityColor(score))
        }
    }
    
    private func getQualityColor(_ score: Double) -> Color {
        switch score {
        case 80...100: return .green
        case 60...79: return .blue
        case 40...59: return .orange
        default: return .red
        }
    }
    
    private func getQualityIcon(_ score: Double) -> String {
        switch score {
        case 90...100: return "star.fill"
        case 80..<90: return "heart.fill"
        case 70..<80: return "thumbsup.fill"
        case 60..<70: return "hand.thumbsup"
        default: return "exclamationmark.triangle.fill"
        }
    }
}

struct QualityRow: View {
    let title: String
    let score: Double
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            
            Spacer()
            
            QualityStars(score: score)
        }
    }
}

struct QualityStars: View {
    let score: Double
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { index in
                Image(systemName: starType(for: index))
                    .foregroundColor(starColor(for: index))
                    .font(.caption)
            }
        }
    }
    
    private func starType(for index: Int) -> String {
        let threshold = Double(index + 1) * 20
        if score >= threshold {
            return "star.fill"
        } else if score >= threshold - 10 {
            return "star.leadinghalf.filled"
        } else {
            return "star"
        }
    }
    
    private func starColor(for index: Int) -> Color {
        let threshold = Double(index + 1) * 20
        return score >= threshold - 10 ? .yellow : .gray.opacity(0.4)
    }
}

struct TechnicalFeedbackRow: View {
    let title: String
    let feedback: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .frame(width: 16)
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            Text(feedback)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
