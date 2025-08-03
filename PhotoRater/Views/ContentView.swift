//
//  ContentView.swift
//  PhotoRater
//
//  Updated with promo code support and 2-week launch promotion display
//

import SwiftUI

struct ContentView: View {
    @State private var selectedCriteria: RankingCriteria = .best
    @State private var selectedImages: [UIImage] = []
    @State private var rankedPhotos: [RankedPhoto] = []
    @State private var isProcessing = false
    @State private var showingImagePicker = false
    @State private var showingPricingView = false
    @State private var showingPromoCodeView = false
    @State private var errorMessage: String? = nil
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var selectedPhotoForDetail: RankedPhoto?
    
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
                        
                        // Credits display with loading state and launch promo info
                        if pricingManager.isInitialized {
                            VStack(spacing: 6) {
                                HStack {
                                    Image(systemName: pricingManager.isUnlimited ? "infinity" : "bolt.fill")
                                        .foregroundColor(creditsColor)
                                    
                                    Text(pricingManager.isUnlimited ? "Unlimited" : "\(pricingManager.userCredits) credits")
                                        .fontWeight(.medium)
                                        .foregroundColor(creditsColor)
                                    
                                    HStack(spacing: 8) {
                                        Button("Get More") {
                                            showingPricingView = true
                                        }
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(8)
                                        
                                        Button("Promo Code") {
                                            showingPromoCodeView = true
                                        }
                                        .font(.caption)
                                        .foregroundColor(.green)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.green.opacity(0.1))
                                        .cornerRadius(8)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(creditsColor.opacity(0.05))
                                .cornerRadius(10)
                                
                                // Launch promotion indicator
                                if isLaunchPeriod && !pricingManager.isUnlimited {
                                    HStack {
                                        Image(systemName: "gift.fill")
                                            .foregroundColor(.green)
                                            .font(.caption)
                                        
                                        Text("Launch Special: New users get 15 free analyses!")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.green)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.1))
                                    .cornerRadius(8)
                                    
                                    Text("Ends August 24, 2025")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
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
                    
                    // Criteria selection - Updated to support more options
                    Text("Select Analysis Type")
                        .font(.headline)
                        .padding(.top)
                    
                    // Primary criteria (Most popular)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Popular Options")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            ForEach([RankingCriteria.best, .balanced], id: \.self) { criteria in
                                CriteriaCard(
                                    criteria: criteria,
                                    isSelected: selectedCriteria == criteria
                                ) {
                                    selectedCriteria = criteria
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Advanced criteria
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Advanced Analysis")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            ForEach([RankingCriteria.profileOrder, .conversationStarters, .broadAppeal, .authenticity], id: \.self) { criteria in
                                CriteriaCard(
                                    criteria: criteria,
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
                    
                    // Ranked photos - Updated header for new criteria (Clear Results button removed)
                    if !rankedPhotos.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text(getResultsTitle())
                                    .font(.headline)
                                
                                Spacer()
                            }
                            .padding(.horizontal)
                            
                            // Criteria-specific explanation
                            if let explanation = getCriteriaExplanation() {
                                Text(explanation)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding()
                                    .background(getCriteriaColor().opacity(0.1))
                                    .cornerRadius(8)
                                    .padding(.horizontal)
                            }
                            
                            // Single column of photo cards
                            VStack(spacing: 16) {
                                ForEach(rankedPhotos) { photo in
                                    PhotoResultCard(rankedPhoto: photo, onViewDetails: {
                                        selectedPhotoForDetail = photo
                                    })
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
            .sheet(isPresented: $showingPromoCodeView) {
                PromoCodeView()
            }
            .sheet(item: $selectedPhotoForDetail) { photo in
                PhotoDetailView(rankedPhoto: photo)
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
                            message: getProcessingMessage(),
                            progress: nil
                        )
                    }
                }
            )
            .onAppear {
                Task {
                    await pricingManager.loadUserCredits()
                }
            }
        }
        .navigationViewStyle(.stack)
        // Clear previous results when switching analysis criteria
        .onChange(of: selectedCriteria) { _ in
            rankedPhotos = []
        }
    }
    
    // MARK: - Computed Properties
    
    private var creditsColor: Color {
        if pricingManager.isUnlimited {
            return .green
        } else if pricingManager.userCredits >= 10 {
            return .blue
        } else if pricingManager.userCredits >= 3 {
            return .orange
        } else {
            return .red
        }
    }
    
    private var isLaunchPeriod: Bool {
        let launchDate = Calendar.current.date(from: DateComponents(year: 2025, month: 8, day: 10))!
        let promotionEnd = Calendar.current.date(byAdding: .day, value: 14, to: launchDate)!
        return Date() >= launchDate && Date() < promotionEnd
    }
    
    // MARK: - Helper Functions
    
    private func getButtonText() -> String {
        let photoCount = selectedImages.count
        if photoCount == 0 {
            return "Select Photos First"
        } else if pricingManager.canAnalyzePhotos(count: photoCount) {
            return "Analyze \(photoCount) Photo\(photoCount == 1 ? "" : "s")"
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
    
    private func getResultsTitle() -> String {
        switch selectedCriteria {
        case .best:
            return "Your Top Photos"
        case .balanced:
            return "Your Balanced Profile Selection"
        case .profileOrder:
            return "Profile Order Recommendations"
        case .conversationStarters:
            return "Conversation Starter Photos"
        case .broadAppeal:
            return "Appeal Analysis Results"
        case .authenticity:
            return "Authenticity Assessment"
        default:
            return "Analysis Results"
        }
    }
    
    private func getCriteriaExplanation() -> String? {
        switch selectedCriteria {
        case .balanced:
            return "Perfect mix for dating success: We selected \(rankedPhotos.count) photos to give you the ideal combination of social connection, personality showcase, and activity highlights."
        case .profileOrder:
            return "Optimal positioning: Photos ranked by where they should appear in your dating profile, from main photo to supporting images."
        case .conversationStarters:
            return "Message magnets: These photos give others specific things to ask you about, making it easier for matches to start conversations."
        case .broadAppeal:
            return "Appeal strategy: Understanding which photos attract the widest audience vs those that appeal to specific types of people."
        case .authenticity:
            return "Genuine connection: Photos ranked by how natural and authentic they appear, prioritizing genuine moments over posed shots."
        default:
            return nil
        }
    }
    
    private func getCriteriaColor() -> Color {
        switch selectedCriteria {
        case .best: return .yellow
        case .balanced: return .blue
        case .profileOrder: return .purple
        case .conversationStarters: return .green
        case .broadAppeal: return .orange
        case .authenticity: return .pink
        default: return .blue
        }
    }
    
    private func getProcessingMessage() -> String {
        switch selectedCriteria {
        case .profileOrder:
            return "Analyzing photo positioning..."
        case .conversationStarters:
            return "Finding conversation elements..."
        case .broadAppeal:
            return "Evaluating demographic appeal..."
        case .authenticity:
            return "Assessing authenticity..."
        default:
            return "Processing your photos..."
        }
    }
    
    func rankPhotos() {
        let photoCount = selectedImages.count
        
        guard pricingManager.canAnalyzePhotos(count: photoCount) else {
            showingPricingView = true
            return
        }
        
        isProcessing = true
        errorMessage = nil
        rankedPhotos = []
        
        PhotoProcessor.shared.rankPhotos(
            images: selectedImages,
            criteria: selectedCriteria
        ) { result in
            DispatchQueue.main.async {
                self.isProcessing = false
                
                switch result {
                case .success(let rankedPhotos):
                    self.rankedPhotos = rankedPhotos
                    // Automatically save analyzed photos to the gallery
                    for photo in rankedPhotos {
                        GalleryManager.shared.addPhoto(photo)
                    }
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

// MARK: - CriteriaCard Component
struct CriteriaCard: View {
    let criteria: RankingCriteria
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: criteria.icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .blue)
                
                Text(criteria.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.blue : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
