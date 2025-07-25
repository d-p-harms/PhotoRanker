//
//  ContentView.swift
//  PhotoRater
//
//  Fixed version with proper loading states and working clear button
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
                        
                        // Credits display with loading state
                        if pricingManager.isInitialized {
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
                        } else {
                            // Loading state
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Loading credits...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(10)
                        }
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
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: selectedImages[index])
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 80, height: 80)
                                            .cornerRadius(8)
                                        
                                        // Remove button
                                        Button(action: {
                                            selectedImages.remove(at: index)
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.red)
                                                .background(Color.white)
                                                .clipShape(Circle())
                                        }
                                        .padding(2)
                                    }
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
                    .disabled(selectedImages.isEmpty || isProcessing || !pricingManager.isInitialized)
                    .padding(.horizontal)
                    
                    // Error message
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                            .padding(.horizontal)
                    }
                    
                    // Ranked photos - Single column layout
                    if !rankedPhotos.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Your Top Photos")
                                    .font(.headline)
                                
                                Spacer()
                                
                                Button(action: {
                                    print("Clear Results button tapped") // Debug print
                                    // Force update on main thread
                                    DispatchQueue.main.async {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            rankedPhotos.removeAll()
                                        }
                                        selectedImages.removeAll()
                                        errorMessage = nil
                                    }
                                }) {
                                    Text("Clear Results")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(6)
                                }
                            }
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
                Button("OK") {
                    errorMessage = nil
                }
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
                Task {
                    await pricingManager.loadUserCredits()
                }
            }
        }
    }
    
    // Helper functions
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
                self.isProcessing = false
                
                switch result {
                case .success(let rankedPhotos):
                    self.rankedPhotos = rankedPhotos
                    // Deduct credits after successful analysis
                    self.pricingManager.deductCredits(count: photoCount)
                case .failure(let error):
                    if error.localizedDescription.contains("Insufficient credits") {
                        self.showingPricingView = true
                    } else if error.localizedDescription.contains("Maximum") && error.localizedDescription.contains("photos") {
                        self.alertMessage = "Please select fewer photos. Maximum 25 photos per session."
                        self.showingAlert = true
                    } else if error.localizedDescription.contains("network") || error.localizedDescription.contains("connection") {
                        self.alertMessage = "Network error. Please check your connection and try again."
                        self.showingAlert = true
                    } else {
                        self.alertMessage = "Error processing photos: \(error.localizedDescription)"
                        self.showingAlert = true
                    }
                }
            }
        }
    }
}
