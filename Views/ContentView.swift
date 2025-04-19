//
//  ContentView.swift
//  PhotoRater
//
//  Created by David Harms on 4/17/25.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedCriteria: RankingCriteria = .best  // Default selection
    @State private var selectedImages: [UIImage] = []
    @State private var rankedPhotos: [RankedPhoto] = []

    var body: some View {
        VStack {
            // Display buttons for each ranking criteria
            ForEach(RankingCriteria.allCases, id: \.self) { criteria in
                CriteriaButton(
                    title: criteria.title,
                    icon: criteria.icon,
                    isSelected: selectedCriteria == criteria
                ) {
                    selectedCriteria = criteria
                }
            }
            
            // Photo Picker
            PhotosPicker(selectedImages: $selectedImages)
            
            // Rank photos based on selected criteria
            Button("Rank Photos") {
                rankedPhotos = rankPhotosBasedOnCriteria(selectedImages, criteria: selectedCriteria)
            }
            
            // Display ranked photos
            ForEach(rankedPhotos) { rankedPhoto in
                PhotoResultCard(rankedPhoto: rankedPhoto)
            }
        }
    }
    
    func rankPhotosBasedOnCriteria(_ images: [UIImage], criteria: RankingCriteria) -> [RankedPhoto] {
        // For simplicity, we rank the photos randomly here.
        // Replace with your ranking logic based on the selected criteria.
        return images.map { image in
            RankedPhoto(image: image, score: Double.random(in: 1...10), tags: [PhotoTag.social]) // Example ranking logic
        }
    }
}
struct PhotoResultCard: View {
    let rankedPhoto: RankedPhoto
    
    var body: some View {
        VStack {
            photoImageView
            
            HStack {
                scoreAndTagsView
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .background(Color.white)
        .cornerRadius(12)
        .shadow(radius: 3)
    }
    
    @ViewBuilder
    private var photoImageView: some View {
        if let localImage = rankedPhoto.localImage {
            Image(uiImage: localImage)
                .resizable()
                .scaledToFill()
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else if let urlString = rankedPhoto.storageURL,
                  let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                case .failure:
                    placeholderView
                case .empty:
                    ProgressView()
                        .frame(height: 200)
                @unknown default:
                    placeholderView
                }
            }
        } else {
            placeholderView
        }
    }
    
    private var placeholderView: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                Image(systemName: "photo")
                    .foregroundColor(.gray)
                    .font(.largeTitle)
            )
    }
    
    private var scoreAndTagsView: some View {
        VStack(alignment: .leading) {
            Text("Score: \(Int(rankedPhoto.score))")
                .font(.headline)
                .foregroundColor(.blue)
            
            if let tags = rankedPhoto.tags, !tags.isEmpty {
                HStack {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag.emoji)
                            .font(.system(size: 14))
                    }
                }
            }
        }
    }
}

