import SwiftUI

struct GalleryPhotoCard: View {
    let rankedPhoto: RankedPhoto
    @State private var loadedImage: UIImage?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                photoImageView

                Text(String(format: "%.0f", rankedPhoto.score))
                    .font(.headline)
                    .fontWeight(.bold)
                    .padding(8)
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(8)
            }

            HStack(spacing: 8) {
                QualityChip(
                    title: "Visual",
                    quality: getQualityLevel(rankedPhoto.detailedScores?.visualQuality ?? rankedPhoto.score),
                    color: .blue
                )
                QualityChip(
                    title: "Appeal",
                    quality: getQualityLevel(rankedPhoto.detailedScores?.attractiveness ?? rankedPhoto.score),
                    color: .pink
                )
                QualityChip(
                    title: "Profile Fit",
                    quality: getQualityLevel(rankedPhoto.detailedScores?.swipeWorthiness ?? rankedPhoto.score),
                    color: .green
                )
                Spacer()
            }
            if let tags = rankedPhoto.tags, !tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(tags.prefix(3), id: \.self) { tag in
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

            if let reason = rankedPhoto.reason, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.bottom, 12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
        .onAppear { loadImage() }
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

    private func loadImage() {
        if rankedPhoto.localImage != nil { return }
        guard !isLoading, let urlString = rankedPhoto.storageURL, let url = URL(string: urlString) else { return }
        isLoading = true
        URLSession.shared.dataTask(with: url) { data, _, _ in
            DispatchQueue.main.async {
                if let data = data, let image = UIImage(data: data) {
                    self.loadedImage = image
                }
                self.isLoading = false
            }
        }.resume()
    }

    private func getQualityLevel(_ score: Double) -> QualityLevel {
        switch score {
        case 90...100: return .excellent
        case 80..<90: return .great
        case 70..<80: return .good
        case 60..<70: return .fair
        default: return .needsWork
        }
    }
}
