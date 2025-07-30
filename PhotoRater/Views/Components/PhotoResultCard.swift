import SwiftUI

struct PhotoResultCard: View {
    let rankedPhoto: RankedPhoto
    @State private var isLoading = true
    @State private var loadedImage: UIImage?
    @State private var showingDetailView = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Photo display with quality indicator instead of score
            ZStack(alignment: .topTrailing) {
                photoImageView
                
                // Quality badge instead of numerical score
                VStack(spacing: 2) {
                    Image(systemName: qualityIcon)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Text(qualityLabel)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(qualityColor.opacity(0.9))
                )
                .padding(8)
            }
            
            // Info section - No numerical scores shown
            VStack(alignment: .leading, spacing: 12) {
                // Quality indicators row
                HStack(spacing: 8) {
                    QualityChip(title: "Visual", quality: getQualityLevel(rankedPhoto.detailedScores?.visualQuality ?? rankedPhoto.score), color: .blue)
                    QualityChip(title: "Appeal", quality: getQualityLevel(rankedPhoto.detailedScores?.attractiveness ?? rankedPhoto.score), color: .pink)
                    QualityChip(title: "Profile Fit", quality: getQualityLevel(rankedPhoto.detailedScores?.swipeWorthiness ?? rankedPhoto.score), color: .purple)
                    Spacer()
                }
                
                // Tags row
                if let tags = rankedPhoto.tags, !tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(tags.prefix(3), id: \.rawValue) { tag in
                            HStack(spacing: 4) {
                                Text(tag.emoji)
                                    .font(.caption2)
                                Text(tag.rawValue.capitalized)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                        
                        if tags.count > 3 {
                            Text("+\(tags.count - 3)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                }
                
                // Recommendation text - Keep it short and positive
                if let reason = rankedPhoto.reason {
                    Text(reason)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                // "View Details" button (clearly labeled as an action)
                Button(action: {
                    showingDetailView = true
                }) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .font(.subheadline)
                        Text("View Detailed Analysis")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle()) // Ensures reliable tapping
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
    
    // Convert numerical score to quality level
    private func getQualityLevel(_ score: Double) -> QualityLevel {
        switch score {
        case 90...100: return .excellent
        case 80..<90: return .great
        case 70..<80: return .good
        case 60..<70: return .fair
        default: return .needsWork
        }
    }
    
    private var qualityColor: Color {
        switch rankedPhoto.score {
        case 80...100: return .green
        case 60...79: return .blue
        case 40...59: return .orange
        default: return .red
        }
    }
    
    private var qualityIcon: String {
        switch rankedPhoto.score {
        case 90...100: return "star.fill"
        case 80..<90: return "heart.fill"
        case 70..<80: return "thumbsup.fill"
        case 60..<70: return "hand.thumbsup"
        default: return "exclamationmark.triangle.fill"
        }
    }
    
    private var qualityLabel: String {
        switch rankedPhoto.score {
        case 90...100: return "EXCELLENT"
        case 80..<90: return "GREAT"
        case 70..<80: return "GOOD"
        case 60..<70: return "FAIR"
        default: return "IMPROVE"
        }
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
                    .frame(height: 180 * DeviceSizing.scale)
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
        .frame(height: 180 * DeviceSizing.scale)
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

enum QualityLevel {
    case excellent, great, good, fair, needsWork
    
    var label: String {
        switch self {
        case .excellent: return "★★★"
        case .great: return "★★☆"
        case .good: return "★☆☆"
        case .fair: return "△"
        case .needsWork: return "○"
        }
    }
    
    var color: Color {
        switch self {
        case .excellent: return .green
        case .great: return .blue
        case .good: return .purple
        case .fair: return .orange
        case .needsWork: return .red
        }
    }
}

struct QualityChip: View {
    let title: String
    let quality: QualityLevel
    let color: Color
    
    var body: some View {
        VStack(spacing: 1) {
            Text(quality.label)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(quality.color)
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
