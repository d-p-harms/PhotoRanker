
import UIKit
import Foundation
import Firebase
import FirebaseFunctions
import FirebaseAuth
import ImageIO

class PhotoProcessor: ObservableObject {
    static let shared = PhotoProcessor()
    private let functions = Functions.functions()
    
    // BALANCED: Keep quality settings, add security limits
    private let optimalAISize: CGFloat = 1536
    private let maxAISize: CGFloat = 2048  // Allow up to 2048px without forced resize
    private let minAISize: CGFloat = 768
    private let maxBatchSize = 12
    private let maxPhotosPerSession = 25
    private let maxFileSize = 10 * 1024 * 1024 // 10MB - reasonable limit
    
    // SECURITY: Essential rate limiting only
    private var lastRequestTime: Date = Date.distantPast
    private var requestCount: Int = 0
    private let requestWindow: TimeInterval = 3600 // 1 hour
    private let maxRequestsPerHour = 50
    
    private init() {}
    
    func rankPhotos(images: [UIImage], criteria: RankingCriteria, completion: @escaping (Result<[RankedPhoto], Error>) -> Void) {
        AuthenticationService.shared.ensureAuthenticated { [weak self] authResult in
            guard let self = self else { return }

            switch authResult {
            case .success:
                self.performRankPhotos(images: images, criteria: criteria, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func performRankPhotos(images: [UIImage], criteria: RankingCriteria, completion: @escaping (Result<[RankedPhoto], Error>) -> Void) {

        // ESSENTIAL SECURITY: Rate limiting check
        guard checkRateLimit() else {
            let error = NSError(domain: "PhotoProcessor", code: 429,
                               userInfo: [NSLocalizedDescriptionKey: "Too many requests. Please wait before trying again."])
            completion(.failure(error))
            return
        }

        // ESSENTIAL SECURITY: Photo count validation
        guard images.count <= maxPhotosPerSession else {
            let error = NSError(domain: "PhotoProcessor", code: 1,
                               userInfo: [NSLocalizedDescriptionKey: "Maximum \(maxPhotosPerSession) photos allowed per session"])
            completion(.failure(error))
            return
        }

        // MINIMAL VALIDATION: Only check for obvious issues
        guard validateImagesBasic(images) else {
            let error = NSError(domain: "PhotoProcessor", code: 2,
                               userInfo: [NSLocalizedDescriptionKey: "One or more images failed validation"])
            completion(.failure(error))
            return
        }

        // Prepare base64 encoded images
        switch prepareImageData(images) {
        case .success(let photoData):
            self.processInBatches(photoData: photoData, criteria: criteria, originalImages: images, completion: completion)
        case .failure(let error):
            completion(.failure(error))
        }
    }
    
    private func checkRateLimit() -> Bool {
        let now = Date()
        
        // Reset counter if window has passed
        if now.timeIntervalSince(lastRequestTime) > requestWindow {
            requestCount = 0
            lastRequestTime = now
        }
        
        requestCount += 1
        
        if requestCount > maxRequestsPerHour {
            print("🚨 Rate limit exceeded: \(requestCount) requests in window")
            return false
        }
        
        return true
    }
    
    // MINIMAL VALIDATION: Only check for obvious problems
    private func validateImagesBasic(_ images: [UIImage]) -> Bool {
        for (index, image) in images.enumerated() {
            // Check image size (very basic)
            let imageSize = image.size
            if imageSize.width < 50 || imageSize.height < 50 {
                print("🚨 Image \(index) too small: \(imageSize)")
                return false
            }

            // Check for valid image data
            guard let imageData = image.jpegData(compressionQuality: 1.0) else {
                print("🚨 Image \(index) failed to convert to JPEG")
                return false
            }

            // If file is too large try optimizing before rejecting
            if imageData.count > maxFileSize {
                print("⚠️ Image \(index) initial size too large: \(imageData.count) bytes, attempting compression")
                if let reduced = optimizeImageForAI(image), reduced.count <= maxFileSize {
                    continue
                }
                print("🚨 Image \(index) still too large after compression")
                return false
            }
        }
        
        return true
    }


    private func processInBatches(photoData: [String], criteria: RankingCriteria, originalImages: [UIImage], completion: @escaping (Result<[RankedPhoto], Error>) -> Void) {
        
        // Split into batches if needed
        let batches = photoData.chunked(into: maxBatchSize)
        
        if batches.count == 1 {
            // Single batch - process normally
            analyzeWithGemini(photoData: photoData, criteria: criteria, originalImages: originalImages, completion: completion)
        } else {
            // Multiple batches - process sequentially
            processBatchesSequentially(batches: batches, criteria: criteria, originalImages: originalImages, completion: completion)
        }
    }
    
    private func processBatchesSequentially(batches: [[String]], criteria: RankingCriteria, originalImages: [UIImage], completion: @escaping (Result<[RankedPhoto], Error>) -> Void) {
        
        var allResults: [RankedPhoto] = []
        var currentBatch = 0
        
        func processNextBatch() {
            guard currentBatch < batches.count else {
                // All batches complete - apply final sorting and selection
                let finalResults = self.applyCriteriaSpecificLogic(to: allResults, criteria: criteria)
                completion(.success(finalResults))
                return
            }
            
            let batch = batches[currentBatch]
            print("Processing batch \(currentBatch + 1) of \(batches.count) (\(batch.count) photos)")
            
            analyzeWithGemini(photoData: batch, criteria: criteria, originalImages: originalImages) { result in
                switch result {
                case .success(let batchResults):
                    allResults.append(contentsOf: batchResults)
                    currentBatch += 1
                    
                    // Small delay before next batch
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        processNextBatch()
                    }
                    
                case .failure(let error):
                    print("Batch \(currentBatch + 1) failed: \(error)")
                    // Continue with next batch instead of failing entirely
                    currentBatch += 1
                    processNextBatch()
                }
            }
        }
        
        processNextBatch()
    }
    
    // QUALITY-FOCUSED: Minimal processing, preserve original quality
    private func optimizeImageForAI(_ image: UIImage) -> Data? {
        let originalSize = image.size
        let scale = image.scale
        
        // Calculate actual pixel dimensions
        let pixelWidth = originalSize.width * scale
        let pixelHeight = originalSize.height * scale
        let maxDimension = max(pixelWidth, pixelHeight)
        
        print("Original image: \(Int(pixelWidth))x\(Int(pixelHeight)) pixels")
        
        // QUALITY FIRST: Only resize if absolutely necessary
        let targetSize: CGFloat
        if maxDimension < minAISize {
            targetSize = minAISize
            print("Upscaling small image to \(Int(targetSize))px")
        } else if maxDimension > maxAISize {
            // Only resize if truly too large (over 2048px)
            targetSize = maxAISize
            print("Resizing oversized image to \(Int(targetSize))px")
        } else {
            // DON'T RESIZE - keep original dimensions for best quality
            targetSize = maxDimension
            print("Keeping original size: \(Int(targetSize))px (optimal quality)")
        }
        
        // Only resize if target size is different from original
        let resizedImage: UIImage
        if targetSize != maxDimension {
            // Calculate new dimensions maintaining aspect ratio
            let aspectRatio = pixelWidth / pixelHeight
            let newWidth: CGFloat
            let newHeight: CGFloat
            
            if aspectRatio > 1 {
                // Landscape
                newWidth = targetSize
                newHeight = targetSize / aspectRatio
            } else {
                // Portrait or square
                newHeight = targetSize
                newWidth = targetSize * aspectRatio
            }
            
            // High-quality resize
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1.0
            format.opaque = true
            
            let renderer = UIGraphicsImageRenderer(
                size: CGSize(width: newWidth, height: newHeight),
                format: format
            )
            
            resizedImage = renderer.image { context in
                context.cgContext.interpolationQuality = .high
                context.cgContext.setShouldAntialias(true)
                context.cgContext.setAllowsAntialiasing(true)
                
                image.draw(in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
            }
        } else {
            // No resize needed - use original image
            resizedImage = image
        }
        
        // QUALITY FIRST: High quality compression with adaptive fallback
        var quality: CGFloat = 0.95
        guard var jpegData = resizedImage.jpegData(compressionQuality: quality) else {
            print("❌ Failed to create JPEG data")
            return nil
        }

        var fileSizeKB = jpegData.count / 1024
        print("Final image: \(Int(resizedImage.size.width))x\(Int(resizedImage.size.height))px, \(fileSizeKB)KB")

        while jpegData.count > maxFileSize && quality > 0.6 {
            quality -= 0.05
            print("Compressing further to quality \(quality)")
            if let data = resizedImage.jpegData(compressionQuality: quality) {
                jpegData = data
                fileSizeKB = jpegData.count / 1024
            } else {
                break
            }
        }

        if jpegData.count > maxFileSize {
            print("🚨 Unable to compress below limit")
            return nil
        }

        return jpegData
    }
    
    // Convert optimized images to base64 strings
    private func prepareImageData(_ images: [UIImage]) -> Result<[String], Error> {
        var encoded: [String] = []

        for (index, image) in images.enumerated() {
            guard let optimizedData = optimizeImageForAI(image) else {
                return .failure(NSError(domain: "PhotoProcessor", code: 1,
                                        userInfo: [NSLocalizedDescriptionKey: "Failed to optimize image \(index + 1)"]))
            }

            encoded.append(optimizedData.base64EncodedString())
        }

        return .success(encoded)
    }
    
    // ESSENTIAL SECURITY: Basic validation with quality preservation
    private func analyzeWithGemini(photoData: [String], criteria: RankingCriteria, originalImages: [UIImage], completion: @escaping (Result<[RankedPhoto], Error>) -> Void) {
        let data: [String: Any] = [
            "photos": photoData,
            "criteria": criteria.rawValue
        ]

        print("Calling Firebase function with \(photoData.count) photos")
        
        functions.httpsCallable("analyzePhotos").call(data) { result, error in
            if let error = error {
                print("Firebase function error: \(error)")
                completion(.failure(error))
                return
            }
            
            guard let resultData = result?.data as? [String: Any] else {
                print("Invalid response format: \(String(describing: result?.data))")
                completion(.failure(NSError(domain: "PhotoProcessor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])))
                return
            }
            
            guard let success = resultData["success"] as? Bool, success else {
                print("Function returned failure: \(resultData)")
                completion(.failure(NSError(domain: "PhotoProcessor", code: 3, userInfo: [NSLocalizedDescriptionKey: "Function returned failure"])))
                return
            }
            
            guard let results = resultData["results"] as? [[String: Any]] else {
                print("Missing results in response: \(resultData)")
                completion(.failure(NSError(domain: "PhotoProcessor", code: 4, userInfo: [NSLocalizedDescriptionKey: "Missing results in response"])))
                return
            }
            
            print("Received \(results.count) results from Firebase function")
            
            // Parse the results into RankedPhoto objects with full data
            var rankedPhotos: [RankedPhoto] = []

            for result in results {
                guard let fileName = result["fileName"] as? String,
                      let storageURL = result["storageURL"] as? String,
                      let score = result["score"] as? Double else {
                    print("Missing required fields in result: \(result)")
                    continue
                }
                
                // Parse tags (existing logic)
                let tagStrings = result["tags"] as? [String] ?? []
                let tags = tagStrings.compactMap { PhotoTag(rawValue: $0) }
                
                // Parse detailed scores (enhanced for new criteria)
                let detailedScores = DetailedScores(
                    overall: score,
                    visualQuality: result["visualQuality"] as? Double ?? result["faceClarity"] as? Double ?? score,
                    attractiveness: result["attractivenessScore"] as? Double ?? result["massAppeal"] as? Double ?? score,
                    datingAppeal: result["datingAppealScore"] as? Double ?? result["conversationValue"] as? Double ?? score,
                    swipeWorthiness: result["swipeWorthiness"] as? Double ?? result["authenticityLevel"] as? Double ?? score
                )
                
                // Parse technical feedback (existing logic)
                var technicalFeedback: TechnicalFeedback? = nil
                if let techFeedback = result["technicalFeedback"] as? [String: Any] {
                    technicalFeedback = TechnicalFeedback(
                        lighting: techFeedback["lighting"] as? String,
                        composition: techFeedback["composition"] as? String,
                        styling: techFeedback["styling"] as? String
                    )
                }
                
                // Parse dating insights (enhanced for new criteria)
                var datingInsights: DatingInsights? = nil
                
                // Handle different response formats based on criteria
                var personalityTraits: [String]? = nil
                var demographicAppeal: String? = nil
                var profileRole: String? = nil
                
                if let insights = result["datingInsights"] as? [String: Any] {
                    personalityTraits = insights["personalityProjected"] as? [String]
                    demographicAppeal = insights["demographicAppeal"] as? String
                    profileRole = insights["profileRole"] as? String
                } else {
                    // Handle new criteria response formats
                    personalityTraits = result["personalityTraits"] as? [String] ?? result["naturalElements"] as? [String]
                    demographicAppeal = result["targetDemographics"] as? String ?? result["appealBreadth"] as? String
                    profileRole = result["positioningAdvice"] as? String ?? result["conversationAdvice"] as? String ?? result["profileRole"] as? String
                }
                
                if personalityTraits != nil || demographicAppeal != nil || profileRole != nil {
                    datingInsights = DatingInsights(
                        personalityProjected: personalityTraits,
                        demographicAppeal: demographicAppeal,
                        profileRole: profileRole
                    )
                }
                
                // Get feedback arrays (enhanced for new criteria)
                var strengths: [String]? = result["strengths"] as? [String]
                var improvements: [String]? = result["improvements"] as? [String] ?? result["suggestions"] as? [String]
                var nextPhotoSuggestions: [String]? = result["nextPhotoSuggestions"] as? [String]
                
                // Handle new criteria specific fields
                if let conversationElements = result["conversationElements"] as? [String] {
                    strengths = conversationElements
                }
                if let messageHooks = result["messageHooks"] as? [String] {
                    nextPhotoSuggestions = messageHooks.map { "Take a photo that highlights: \($0)" }
                }
                if let positionReason = result["positionReason"] as? String {
                    if improvements == nil { improvements = [] }
                    improvements?.append(positionReason)
                }
                
                // Build primary reason (criteria-specific)
                var reason = "Analysis completed"
                
                switch criteria {
                case .profileOrder:
                    if let position = result["position"] as? String,
                       let positionReason = result["positionReason"] as? String {
                        reason = "📍 Position: \(position == "1" ? "Main Photo" : position == "skip" ? "Consider skipping" : "Photo #\(position)")\n\n\(positionReason)"
                    }
                    
                case .conversationStarters:
                    if let hooks = result["messageHooks"] as? [String], !hooks.isEmpty {
                        reason = "💬 Conversation starter: \(hooks.first ?? "Interesting elements")"
                        if hooks.count > 1 {
                            reason += "\n\nOther talking points: \(hooks.dropFirst().joined(separator: ", "))"
                        }
                    }
                    
                case .broadAppeal:
                    if let appealType = result["appealBreadth"] as? String,
                       let demographics = result["targetDemographics"] as? [String] {
                        reason = "🎯 Appeal: \(appealType.capitalized)\n\nAttracts: \(demographics.joined(separator: ", "))"
                    }
                    
                case .authenticity:
                    if let authenticityLevel = result["authenticityLevel"] as? String,
                       let genuinenessFactors = result["genuinenessFactors"] as? String {
                        reason = "✨ Authenticity: \(authenticityLevel.replacingOccurrences(of: "_", with: " ").capitalized)\n\n\(genuinenessFactors)"
                    }
                    
                default:
                    // Use existing logic for other criteria
                    if let bestQuality = result["bestQuality"] as? String {
                        reason = bestQuality
                        if let suggestions = improvements, !suggestions.isEmpty {
                            reason = "\(bestQuality)\n\n💡 Tip: \(suggestions[0])"
                        }
                    } else if let directReason = result["reason"] as? String {
                        reason = directReason
                    }
                }
                
                var rankedPhoto = RankedPhoto(
                    id: UUID(),
                    fileName: fileName,
                    storageURL: storageURL,
                    score: score,
                    tags: tags,
                    reason: reason,
                    detailedScores: detailedScores,
                    technicalFeedback: technicalFeedback,
                    datingInsights: datingInsights,
                    improvements: improvements,
                    strengths: strengths,
                    nextPhotoSuggestions: nextPhotoSuggestions
                )

                // Attach the originally selected image so the UI can display it
                if let indexString = fileName.split(separator: "_").last,
                   let index = Int(indexString),
                   index < originalImages.count {
                    rankedPhoto.localImage = originalImages[index]
                }

                rankedPhotos.append(rankedPhoto)
            }
            
            print("Successfully created \(rankedPhotos.count) ranked photos")
            
            // Apply criteria-specific logic
            let finalResults = self.applyCriteriaSpecificLogic(to: rankedPhotos, criteria: criteria)
            completion(.success(finalResults))
        }
    }
    
    // MARK: - Criteria-Specific Logic (unchanged)
    
    private func applyCriteriaSpecificLogic(to photos: [RankedPhoto], criteria: RankingCriteria) -> [RankedPhoto] {
        switch criteria {
        case .balanced:
            return createBalancedSelection(from: photos, targetCount: 6)
            
        case .profileOrder:
            // Sort by score (positioning value) and group by recommended position
            return photos.sorted { photo1, photo2 in
                // Extract position from reason if available
                let position1 = extractPosition(from: photo1.reason)
                let position2 = extractPosition(from: photo2.reason)
                
                if position1 != position2 {
                    return position1 < position2
                }
                return photo1.score > photo2.score
            }
            
        case .conversationStarters:
            // Sort by conversation potential score
            return photos.sorted { $0.score > $1.score }
            
        case .broadAppeal:
            // Sort by appeal score but group broad vs niche
            return photos.sorted { photo1, photo2 in
                // Check if one is broad appeal and other is niche
                let appeal1 = extractAppealType(from: photo1.reason)
                let appeal2 = extractAppealType(from: photo2.reason)
                
                if appeal1 == "broad" && appeal2 != "broad" {
                    return true
                }
                if appeal2 == "broad" && appeal1 != "broad" {
                    return false
                }
                return photo1.score > photo2.score
            }
            
        case .authenticity:
            // Sort by authenticity score
            return photos.sorted { $0.score > $1.score }
            
        default:
            // Default sorting by score for other criteria
            return photos.sorted { $0.score > $1.score }
        }
    }
    
    // MARK: - Helper functions for sorting (unchanged)
    
    private func extractPosition(from reason: String?) -> Int {
        guard let reason = reason else { return 999 }
        
        if reason.contains("Main Photo") || reason.contains("Photo #1") {
            return 1
        } else if reason.contains("Photo #2") {
            return 2
        } else if reason.contains("Photo #3") {
            return 3
        } else if reason.contains("Photo #4") {
            return 4
        } else if reason.contains("Photo #5") {
            return 5
        } else if reason.contains("Photo #6") {
            return 6
        } else if reason.contains("skip") {
            return 999
        }
        
        return 99 // Supporting photos
    }
    
    private func extractAppealType(from reason: String?) -> String {
        guard let reason = reason else { return "unknown" }
        
        if reason.lowercased().contains("broad") {
            return "broad"
        } else if reason.lowercased().contains("niche") {
            return "niche"
        } else if reason.lowercased().contains("moderate") {
            return "moderate"
        }
        
        return "unknown"
    }
    
    // MARK: - Balanced Selection Logic (unchanged)
    
    private func createBalancedSelection(from rankedPhotos: [RankedPhoto], targetCount: Int = 6) -> [RankedPhoto] {
        // Define ideal distribution for a balanced dating profile
        let targetDistribution: [String: Int] = [
            "social": 2,      // 2 social photos max
            "activity": 2,    // 2 activity photos max
            "personality": 2, // 2 personality photos max
            "general": 2      // 2 general/other photos max
        ]
        
        var selected: [RankedPhoto] = []
        var categoryCount: [String: Int] = [:]
        
        // First pass: Select highest scoring photo from each major category
        let sortedPhotos = rankedPhotos.sorted { $0.score > $1.score }
        
        print("Creating balanced selection from \(rankedPhotos.count) photos...")
        
        for photo in sortedPhotos {
            if selected.count >= targetCount { break }
            
            let photoCategories = getPhotoCategories(photo)
            var canAdd = false
            var addReason = ""
            
            // Check if we need this category type
            for category in photoCategories {
                let currentCount = categoryCount[category, default: 0]
                let maxForCategory = targetDistribution[category, default: 1]
                
                if currentCount < maxForCategory {
                    canAdd = true
                    addReason = "Fills \(category) spot (\(currentCount + 1)/\(maxForCategory)) in your balanced profile"
                    categoryCount[category] = currentCount + 1
                    break
                }
            }
            
            if canAdd {
                // Add balance explanation to the photo
                let originalReason = photo.reason ?? "Good quality photo"
                let updatedReason = "\(originalReason)\n\n🎯 Balance: \(addReason)"
                let balancedPhoto = photo.withUpdatedReason(updatedReason)
                selected.append(balancedPhoto)
                
                print("Selected photo for \(photoCategories.first ?? "general") category (score: \(photo.score))")
            }
        }
        
        // Second pass: Fill remaining slots with highest scoring remaining photos
        let remaining = sortedPhotos.filter { photo in
            !selected.contains { $0.id == photo.id }
        }
        
        for photo in remaining {
            if selected.count >= targetCount { break }
            
            let originalReason = photo.reason ?? "Good quality photo"
            let updatedReason = "\(originalReason)\n\n🎯 Balance: Rounds out your profile variety"
            let balancedPhoto = photo.withUpdatedReason(updatedReason)
            selected.append(balancedPhoto)
            
            print("Added remaining photo to fill balance (score: \(photo.score))")
        }
        
        print("Final balanced selection: \(selected.count) photos")
        return selected
    }
    
    private func getPhotoCategories(_ photo: RankedPhoto) -> [String] {
        var categories: [String] = []
        
        if let tags = photo.tags {
            for tag in tags {
                switch tag {
                case .social:
                    categories.append("social")
                case .activity:
                    categories.append("activity")
                case .personality:
                    categories.append("personality")
                }
            }
        }
        
        // If no specific categories, it's a general photo
        if categories.isEmpty {
            categories.append("general")
        }
        
        return categories
    }
}

// Helper extension for array chunking (unchanged)
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
