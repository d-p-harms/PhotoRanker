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
                Text("Score: \(Int(rankedPhoto.score))")
                    .font(.headline)
                    .foregroundColor(.blue)
                
                // Tags
                if let tags = rankedPhoto.tags, !tags.isEmpty {
                    HStack {
                        ForEach(tags, id: \.self) { tag in
                            HStack(spacing: 4) {
                                Text(tag.emoji)
                                    .font(.system(size: 14))
                                Text(tag.rawValue.capitalized)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(6)
                        }
                    }
                }
                
                // Reason from analysis
                Text(rankedPhoto.reason ?? "No reason provided")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .padding(.top, 4)
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
