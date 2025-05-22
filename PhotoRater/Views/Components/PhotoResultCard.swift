import SwiftUI

struct PhotoResultCard: View {
    let rankedPhoto: RankedPhoto
    @State private var isLoading = true
    @State private var loadedImage: UIImage?
    @State private var isExpanded = false
    @State private var showingDetailView = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Photo display with score overlay
            ZStack(alignment: .topTrailing) {
                photoImageView
                
                // Score badge
                VStack(spacing: 2) {
                    Text("\(Int(rankedPhoto.score))")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Text("SCORE")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(scoreColor.opacity(0.9))
                )
                .padding(8)
            }
            
            // Info section
            VStack(alignment: .leading, spacing: 8) {
                // Detailed scores if available
                if let scores = rankedPhoto.detailedScores {
                    HStack(spacing: 8) {
                        ScoreChip(title: "Visual", score: scores.visualQuality, color: .blue)
                        ScoreChip(title: "Appeal", score: scores.attractiveness, color: .pink)
                        ScoreChip(title: "Swipe", score: scores.swipeWorthiness, color: .green)
                        
                        Spacer()
                        
                        Button("Details") {
                            showingDetailView = true
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                    }
                }
                
                // Tags
                if let tags = rankedPhoto.tags, !tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                HStack(spacing: 4) {
                                    Text(tag.emoji)
                                        .font(.system(size: 12))
                                    Text(tag.rawValue.capitalized)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(6)
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                }
                
                // Main comment with truncation
                if let reason = rankedPhoto.reason, !reason.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isExpanded ? reason : truncatedReason(reason))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(isExpanded ? nil : 3)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        if shouldShowReadMore(reason) {
                            Button(action: {
                                isExpanded.toggle()
                            }) {
                                Text(isExpanded ? "Show Less" : "Read More")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                } else {
                    Text("Analysis completed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
        .onAppear {
            loadImageFromURL()
        }
        .sheet(isPresented: $showingDetailView) {
            PhotoDetailView(rankedPhoto: rankedPhoto)
        }
    }
    
    private var scoreColor: Color {
        switch rankedPhoto.score {
        case 80...100: return .green
        case 60...79: return .blue
        case 40...59: return .orange
        default: return .red
        }
    }
    
    private func truncatedReason(_ reason: String) -> String {
        let maxLength = 100
        if reason.count <= maxLength {
            return reason
        }
        let truncated = String(reason.prefix(maxLength))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "..."
        }
        return truncated + "..."
    }
    
    private func shouldShowReadMore(_ reason: String) -> Bool {
        return reason.count > 100
    }
    
    private var photoImageView: some View {
        Group {
            if let localImage = rankedPhoto.localImage {
                Image(uiImage: localImage)
                    .resizable()
                    .scaledToFill()
            } else if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if isLoading {
                ProgressView()
                    .frame(height: 180)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                            .font(.largeTitle)
                    )
            }
        }
        .frame(height: 180)
        .clipped()
        .cornerRadius(12)
    }
    
    private func loadImageFromURL() {
        if rankedPhoto.localImage != nil {
            isLoading = false
            return
        }
        
        isLoading = true
        
        guard let urlString = rankedPhoto.storageURL,
              let url = URL(string: urlString) else {
            isLoading = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if let error = error {
                    print("Error loading image: \(error.localizedDescription)")
                    return
                }
                
                if let data = data, let image = UIImage(data: data) {
                    self.loadedImage = image
                }
            }
        }.resume()
    }
}

struct ScoreChip: View {
    let title: String
    let score: Double
    let color: Color
    
    var body: some View {
        VStack(spacing: 1) {
            Text("\(Int(score))")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }
}
