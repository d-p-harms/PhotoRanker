//
//  ContentView.swift
//  PhotoRater
//
//  Updated with promo code support and 2-week launch promotion display
//  Fixed iPad button spacing issues
//  Optimized for faster compilation by breaking down complex view hierarchy
//  COMPLETE VERSION - includes ALL original functionality
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
    
    @StateObject private var pricingManager = PricingManager.shared
    
    var body: some View {
        let scale = DeviceSizing.scale
        return NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    titleAndCreditsSection
                    photoPickerButton
                    criteriaSelectionSection
                    analysisButtonSection
                    errorMessageSection
                    resultsSection
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
            .alert("Error", isPresented: $showingAlert) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                Text(alertMessage)
            }
            .overlay(processingOverlay)
            .onAppear {
                Task {
                    await pricingManager.loadUserCredits()
                }
            }
        }
    }
    
    // MARK: - View Components
    
    private var titleAndCreditsSection: some View {
        VStack(spacing: 8) {
            titleSection
            creditsDisplaySection
        }
    }
    
    private var titleSection: some View {
        VStack(spacing: 8) {
            Text("Photo Ranker")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Upload your photos to get AI-powered recommendations")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
    
    @ViewBuilder
    private var creditsDisplaySection: some View {
        if pricingManager.isInitialized {
            VStack(spacing: 6) {
                mainCreditsRow
                launchPromotionDisplay
                creditsButtonsRow
                launchPromotionIndicator
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(creditsColor.opacity(0.05))
            .cornerRadius(10)
        } else {
            loadingCreditsView
        }
    }
    
    private var mainCreditsRow: some View {
        HStack {
            Image(systemName: pricingManager.isUnlimited ? "infinity" : "bolt.fill")
                .foregroundColor(creditsColor)
            
            Text(creditsDisplayText)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(creditsColor)
            
            Spacer()
            
            if !pricingManager.isUnlimited {
                Button("Get More") {
                    showingPricingView = true
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(6)
            }
        }
    }
    
    @ViewBuilder
    private var launchPromotionDisplay: some View {
        if isLaunchPeriod && !pricingManager.isUnlimited {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text("🎉 Launch Special: 50% off all credits!")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                    
                    Button("Enter Promo Code") {
                        showingPromoCodeView = true
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
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
    }
    
    @ViewBuilder
    private var creditsButtonsRow: some View {
        if !pricingManager.isUnlimited {
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
                .frame(minWidth: 80, maxWidth: .infinity)
                
                Button("Promo Code") {
                    showingPromoCodeView = true
                }
                .font(.caption)
                .foregroundColor(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
                .frame(minWidth: 80, maxWidth: .infinity)
            }
        }
    }
    
    @ViewBuilder
    private var launchPromotionIndicator: some View {
        if isLaunchPeriod && !pricingManager.isUnlimited {
            HStack {
                Image(systemName: "gift.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                
                Text("Launch Special: New users get 15 free analyses!")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.green)
                
                Text("Ends August 24, 2025")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    private var loadingCreditsView: some View {
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
    
    private var photoPickerButton: some View {
        Button(action: { showingImagePicker = true }) {
            VStack {
                Image(systemName: "photo.on.rectangle")
                    .font(.largeTitle)
                    .padding()
                
                Text(photoPickerButtonText)
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.blue)
            .frame(maxWidth: .infinity)
            .frame(height: 120 * DeviceSizing.scale)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [5]))
            )
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var criteriaSelectionSection: some View {
        if !selectedImages.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Analysis Type")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .padding(.horizontal)
                
                criteriaGrid
            }
        }
    }
    
    private var criteriaGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            ForEach(RankingCriteria.allCases, id: \.self) { criteria in
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
    
    @ViewBuilder
    private var analysisButtonSection: some View {
        if !selectedImages.isEmpty {
            Button(action: analyzePhotos) {
                HStack {
                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                    
                    Text(getButtonText())
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: getButtonColors()),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
            }
            .disabled(isAnalysisDisabled)
            .padding(.horizontal)
        }
    }
    
    @ViewBuilder
    private var errorMessageSection: some View {
        if let errorMessage = errorMessage {
            Text(errorMessage)
                .foregroundColor(.red)
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
        }
    }
    
    @ViewBuilder
    private var resultsSection: some View {
        if !rankedPhotos.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                resultsHeader
                criteriaExplanationSection
                resultsPhotoCards
            }
            .padding(.bottom, 20)
        }
    }
    
    private var resultsHeader: some View {
        HStack {
            Text(getResultsTitle())
                .font(.headline)
            
            Spacer()
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var criteriaExplanationSection: some View {
        if let explanation = getCriteriaExplanation() {
            Text(explanation)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding()
                .background(getCriteriaColor().opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
        }
    }
    
    private var resultsPhotoCards: some View {
        VStack(spacing: 16) {
            ForEach(rankedPhotos) { photo in
                PhotoResultCard(rankedPhoto: photo)
            }
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var processingOverlay: some View {
        if isProcessing {
            ProcessingOverlay(
                message: getProcessingMessage(),
                progress: nil
            )
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
    
    private var creditsDisplayText: String {
        pricingManager.isUnlimited ?
        "Unlimited Credits" :
        "\(pricingManager.userCredits) Credits"
    }
    
    private var photoPickerButtonText: String {
        selectedImages.isEmpty ?
        "Select Photos to Analyze" :
        "Selected \(selectedImages.count) Photo\(selectedImages.count == 1 ? "" : "s")"
    }
    
    private var isLaunchPeriod: Bool {
        let launchDate = Calendar.current.date(from: DateComponents(year: 2025, month: 8, day: 10))!
        let promotionEnd = Calendar.current.date(byAdding: .day, value: 14, to: launchDate)!
        return Date() >= launchDate && Date() < promotionEnd
    }
    
    private var isAnalysisDisabled: Bool {
        isProcessing || selectedImages.isEmpty || !pricingManager.canAnalyzePhotos(count: selectedImages.count)
    }
    
    // MARK: - Helper Functions
    
    private func getButtonText() -> String {
        let photoCount = selectedImages.count
        if photoCount == 0 {
            return "Select Photos First"
        } else if pricingManager.canAnalyzePhotos(count: photoCount) {
            return "Analyze \(photoCount) Photo\(photoCount == 1 ? "" : "s")"
        } else {
            let needed = photoCount - pricingManager.userCredits
            return "Need \(needed) More Credit\(needed == 1 ? "" : "s")"
        }
    }
    
    private func getButtonColors() -> [Color] {
        if pricingManager.canAnalyzePhotos(count: selectedImages.count) {
            return [Color.blue, Color.blue.opacity(0.8)]
        } else {
            return [Color.gray, Color.gray.opacity(0.8)]
        }
    }
    
    private func getProcessingMessage() -> String {
        switch selectedCriteria {
        case .best:
            return "Analyzing photo quality and appeal..."
        case .profileOrder:
            return "Determining optimal profile order..."
        case .conversationStarters:
            return "Finding conversation opportunities..."
        case .broadAppeal:
            return "Analyzing demographic appeal..."
        case .balanced:
            return "Creating balanced photo selection..."
        case .authenticity:
            return "Evaluating photo authenticity..."
        }
    }
    
    // MARK: - MISSING FUNCTIONS FROM ORIGINAL
    
    private func getResultsTitle() -> String {
        switch selectedCriteria {
        case .best:
            return "Best Overall Photos"
        case .profileOrder:
            return "Optimal Profile Order"
        case .conversationStarters:
            return "Conversation Starter Photos"
        case .broadAppeal:
            return "Broad Appeal Analysis"
        case .balanced:
            return "Balanced Photo Selection"
        case .authenticity:
            return "Authenticity Analysis"
        }
    }
    
    private func getCriteriaExplanation() -> String? {
        switch selectedCriteria {
        case .best:
            return "Ranked by overall dating profile effectiveness - quality, appeal, and swipe-worthiness."
        case .profileOrder:
            return "Optimized order for your dating profile - from main photo to supporting images."
        case .conversationStarters:
            return "Photos that give matches something specific to message you about."
        case .broadAppeal:
            return "Analysis of which photos appeal to the widest vs. most specific audiences."
        case .balanced:
            return "A diverse mix showing different aspects of your personality and lifestyle."
        case .authenticity:
            return "Photos ranked by how genuine and natural they appear."
        }
    }
    
    private func getCriteriaColor() -> Color {
        switch selectedCriteria {
        case .best:
            return .blue
        case .profileOrder:
            return .purple
        case .conversationStarters:
            return .green
        case .broadAppeal:
            return .orange
        case .balanced:
            return .cyan
        case .authenticity:
            return .pink
        }
    }
    
    private func analyzePhotos() {
        guard !selectedImages.isEmpty,
              pricingManager.canAnalyzePhotos(count: selectedImages.count) else {
            alertMessage = "You need more credits to analyze these photos."
            showingAlert = true
            return
        }
        
        isProcessing = true
        rankedPhotos.removeAll()
        
        PhotoProcessor.shared.rankPhotos(
            images: selectedImages,
            criteria: selectedCriteria
        ) { result in
            switch result {
            case .success(let rankedPhotos):
                Task { @MainActor in
                    self.rankedPhotos = rankedPhotos
                    self.isProcessing = false
                    pricingManager.deductCredits(count: selectedImages.count)
                }
            case .failure(let error):
                Task { @MainActor in
                    self.isProcessing = false
                    self.errorMessage = error.localizedDescription
                    self.alertMessage = "Analysis failed: \(error.localizedDescription)"
                    self.showingAlert = true
                }
            }
        }
    }
}

// MARK: - Supporting Views

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
            .frame(height: 80 * DeviceSizing.scale)
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

#Preview {
    ContentView()
}
