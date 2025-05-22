//
//  ContentView.swift
//  PhotoRater
//
//  Created by David Harms on 4/17/25.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedCriteria: RankingCriteria = .best
    @State private var selectedImages: [UIImage] = []
    @State private var rankedPhotos: [RankedPhoto] = []
    @State private var isProcessing = false
    @State private var showingImagePicker = false
    @State private var errorMessage: String? = nil
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Title
                    Text("Photo Ranker")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Upload your photos to get AI-powered recommendations")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    // Photo picker button
                    Button(action: {
                        showingImagePicker = true
                    }) {
                        VStack {
                            Image(systemName: "photo.on.rectangle")
                                .font(.largeTitle)
                                .padding()
                            
                            Text(selectedImages.isEmpty ? "Upload Photos" : "\(selectedImages.count) Photos Selected")
                                .fontWeight(.medium)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)
                    
                    // Selected images preview
                    if !selectedImages.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(0..<selectedImages.count, id: \.self) { index in
                                    Image(uiImage: selectedImages[index])
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .cornerRadius(8)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    // Criteria selection
                    Text("Select Ranking Criteria")
                        .font(.headline)
                        .padding(.top)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(RankingCriteria.allCases, id: \.self) { criteria in
                                CriteriaButton(
                                    title: criteria.title,
                                    icon: criteria.icon,
                                    isSelected: selectedCriteria == criteria
                                ) {
                                    selectedCriteria = criteria
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Criteria description
                    Text(selectedCriteria.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    
                    // Rank photos button
                    Button(action: rankPhotos) {
                        Text("Rank Photos")
                            .fontWeight(.semibold)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(selectedImages.isEmpty ? Color.gray : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .disabled(selectedImages.isEmpty || isProcessing)
                    .padding(.horizontal)
                    
                    // Error message
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .padding()
                    }
                    
                    // Ranked photos
                    if !rankedPhotos.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Your Top Photos")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ], spacing: 16) {
                                ForEach(rankedPhotos) { photo in
                                    PhotoResultCard(rankedPhoto: photo)
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.bottom, 20) // Extra bottom padding
                    }
                }
                .padding(.bottom)
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingImagePicker) {
                PhotosPicker(selectedImages: $selectedImages)
            }
            .overlay(
                Group {
                    if isProcessing {
                        ProcessingOverlay(
                            message: "Processing your photos...",
                            progress: nil
                        )
                    }
                }
            )
        }
    }
    
    func rankPhotos() {
        guard !selectedImages.isEmpty else { return }
        
        isProcessing = true
        errorMessage = nil
        rankedPhotos = []
        
        // Call the PhotoProcessor to rank the photos
        PhotoProcessor.shared.rankPhotos(
            images: selectedImages,
            criteria: selectedCriteria
        ) { result in
            DispatchQueue.main.async {
                isProcessing = false
                
                switch result {
                case .success(let rankedPhotos):
                    self.rankedPhotos = rankedPhotos
                case .failure(let error):
                    errorMessage = "Error processing photos: \(error.localizedDescription)"
                    print("Error processing photos: \(error)")
                }
            }
        }
    }
}

