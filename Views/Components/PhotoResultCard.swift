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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Photo display
            photoImageView
            
            // Info section
            VStack(alignment: .leading, spacing: 4) {
                // Score
                Text("Score: \(Int(rankedPhoto.score))%")
                    .font(.headline)
                    .foregroundColor(.blue)
                
                // Tags
                if let tags = rankedPhoto.tags, !tags.isEmpty {
                    HStack {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag.emoji)
                                .font(.system(size: 16))
                                .padding(4)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(6)
                        }
                    }
                }
                
                // Analysis details (if available)
                if let analysis = rankedPhoto.analysis {
                    if let composition = analysis.composition {
                        Text(composition)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    if let suggestions = analysis.suggestions, !suggestions.isEmpty {
                        Text("Suggestions:")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.top, 4)
                        
                        ForEach(Array(suggestions.prefix(2).enumerated()), id: \.offset) { _, suggestion in
                            Text("• \(suggestion)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 5)
        .onAppear {
            loadImageFromURL()
        }
    }
    
    private var photoImageView: some View {
        Group {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if isLoading {
                ProgressView()
                    .frame(height: 200)
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
        .frame(height: 200)
        .clipped()
        .cornerRadius(12)
    }
    
    private func loadImageFromURL() {
        isLoading = true
        
        guard let urlString = rankedPhoto.storageURL,
              let url = URL(string: urlString) else {
            isLoading = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if let data = data, let image = UIImage(data: data) {
                    self.loadedImage = image
                }
            }
        }.resume()
    }
}
