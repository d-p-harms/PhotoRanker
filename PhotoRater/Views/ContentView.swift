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
    @State private var showingPricingView = false
    @State private var errorMessage: String? = nil
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    @StateObject private var pricingManager = PricingManager.shared
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Title and credits display
                    VStack(spacing: 8) {
                        Text("Photo Ranker")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Upload your photos to get AI-powered recommendations")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        // Credits display
                        HStack {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.blue)
                            Text("\(pricingManager.userCredits) credits")
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
                            
                            Button("Get More") {
                                showingPricingView = true
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.05))
                        .cornerRadius(10)
                    }
                    
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
                        Text(getButtonText())
                            .fontWeight(.semibold)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(getButtonColor())
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
                    
                    // Ranked photos - Single column layout
                    if !rankedPhotos.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Your Top Photos")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            // Single column of photo cards
                            VStack(spacing: 16) {
                                ForEach(rankedPhotos) { photo in
                                    PhotoResultCard(rankedPhoto: photo)
                                        .padding(.horizontal)
                                }
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
                .padding(.bottom)
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingImagePicker) {
                PhotosPicker(selectedImages: $selectedImages)
            }
            .sheet(isPresented: $showingPricingView) {
                PricingView()
            }
            .alert("Error", isPresented: $showingAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
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
            .onAppear {
                // Load user credits when view appears
                pricingManager.loadUserCredits()
            }
        }
    }
    
    private func getButtonText() -> String {
        let photoCount = selectedImages.count
        if photoCount == 0 {
            return "Select Photos First"
        } else if pricingManager.canAnalyzePhotos(count: photoCount) {
            return "Rank \(photoCount) Photo\(photoCount == 1 ? "" : "s")"
        } else {
            return "Need More Credits (\(photoCount) required)"
        }
    }
    
    private func getButtonColor() -> Color {
        let photoCount = selectedImages.count
        if photoCount == 0 {
            return .gray
        } else if pricingManager.canAnalyzePhotos(count: photoCount) {
            return .blue
        } else {
            return .orange
        }
    }
    
    func rankPhotos() {
        let photoCount = selectedImages.count
        
        // Check if user has enough credits
        guard pricingManager.canAnalyzePhotos(count: photoCount) else {
            showingPricingView = true
            return
        }
        
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
                    // Deduct credits after successful analysis
                    pricingManager.deductCredits(count: photoCount)
                case .failure(let error):
                    if error.localizedDescription.contains("Insufficient credits") {
                        showingPricingView = true
                    } else {
                        alertMessage = "Error processing photos: \(error.localizedDescription)"
                        showingAlert = true
                    }
                }
            }
        }
    }
}
