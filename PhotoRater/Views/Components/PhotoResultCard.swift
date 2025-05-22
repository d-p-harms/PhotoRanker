//
//  PhotoResultCard.swift
//  PhotoRater
//
//  Created by David Harms on 4/18/25.
//

import SwiftUI

struct PhotoResultCard: View {
    let rankedPhoto: RankedPhoto
    @State private var isLoading = true
    @State private var loadedImage: UIImage?
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Photo display
            photoImageView
            
            // Info section
            VStack(alignment: .leading, spacing: 6) {
                // Score
                Text("Score: \(Int(rankedPhoto.score))")
                    .font(.headline)
                    .foregroundColor(.blue)
                
                // Tags
                if let tags = rankedPhoto.tags, !tags.isEmpty {
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
                }
                
                // Comment with proper truncation
                if let reason = rankedPhoto.reason, !reason.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isExpanded ? reason : truncatedReason(reason))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(isExpanded ? nil : 3)
                            .fixedSize(horizontal: false, vertical: true)
                            .animation(.easeInOut(duration: 0.2), value: isExpanded)
                        
                        if shouldShowReadMore(reason) {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isExpanded.toggle()
                                }
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
    }
    
    private func truncatedReason(_ reason: String) -> String {
        let maxLength = 100 // Increased from 80
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
        return reason.count > 100 // Match truncation threshold
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
        .frame(height: 180) // Slightly reduced height to give more space for text
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
