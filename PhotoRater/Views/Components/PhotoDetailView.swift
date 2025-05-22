//
//  PhotoDetailView.swift
//  PhotoRater
//
//  Created by David Harms on 5/21/25.
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
                    
                    // Overall Score
                    overallScoreSection
                    
                    // Detailed Scores
                    if let scores = rankedPhoto.detailedScores {
                        detailedScoresSection(scores)
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
                    .frame(height: 250)
                    .overlay(
                        ProgressView()
                    )
            }
        }
        .frame(maxHeight: 300)
        .cornerRadius(12)
    }
    
    private var overallScoreSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overall Score")
                .font(.headline)
                .fontWeight(.semibold)
            
            HStack {
                Text("\(Int(rankedPhoto.score))")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(scoreColor)
                
                Text("/100")
                    .font(.title2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                ScoreProgressView(score: rankedPhoto.score)
            }
            
            Text(scoreDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func detailedScoresSection(_ scores: DetailedScores) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detailed Breakdown")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 8) {
                ScoreRow(title: "Visual Quality", score: scores.visualQuality, icon: "camera.fill", color: .blue)
                ScoreRow(title: "Attractiveness", score: scores.attractiveness, icon: "heart.fill", color: .pink)
                ScoreRow(title: "Dating Appeal", score: scores.datingAppeal, icon: "person.2.fill", color: .purple)
                ScoreRow(title: "Swipe Worthiness", score: scores.swipeWorthiness, icon: "hand.tap.fill", color: .green)
            }
            
            Text("Your strongest area: \(scores.topCategory)")
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
    
    private var scoreColor: Color {
        switch rankedPhoto.score {
        case 80...100: return .green
        case 60...79: return .blue
        case 40...59: return .orange
        default: return .red
        }
    }
    
    private var scoreDescription: String {
        switch rankedPhoto.score {
        case 80...100: return "Excellent photo for dating profiles"
        case 60...79: return "Good photo with room for improvement"
        case 40...59: return "Average photo, could use enhancement"
        default: return "Consider retaking or major improvements"
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

struct ScoreRow: View {
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
            
            Text("\(Int(score))")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(color)
            
            ScoreProgressView(score: score, height: 6, width: 60)
        }
    }
}

struct ScoreProgressView: View {
    let score: Double
    let height: CGFloat
    let width: CGFloat
    
    init(score: Double, height: CGFloat = 8, width: CGFloat = 100) {
        self.score = score
        self.height = height
        self.width = width
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: width, height: height)
            
            Rectangle()
                .fill(scoreColor)
                .frame(width: width * (score / 100), height: height)
        }
        .cornerRadius(height / 2)
    }
    
    private var scoreColor: Color {
        switch score {
        case 80...100: return .green
        case 60...79: return .blue
        case 40...59: return .orange
        default: return .red
        }
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
