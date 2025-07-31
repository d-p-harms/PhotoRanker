import UIKit
import Foundation
import Firebase
import FirebaseStorage
import FirebaseFunctions
import FirebaseAuth
import ImageIO
import ContentModerationService

class PhotoProcessor: ObservableObject {
    static let shared = PhotoProcessor()
    private let functions = Functions.functions()
    private let storage = Storage.storage()
    
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

        for (index, image) in images.enumerated() {
            let result = ContentModerationService.shared.detectInappropriateContent(image: image)
            if !result.isAllowed {
                let message = result.errorMessage ?? "Image \(index + 1) failed content moderation"
                let error = NSError(domain: "PhotoProcessor", code: 3,
                                   userInfo: [NSLocalizedDescriptionKey: message])
                completion(.failure(error))
                return
            }
        }

        // Upload photos with MINIMAL processing
        uploadOptimizedPhotos(images) { uploadResult in
            switch uploadResult {
            case .success(let photoUrls):
                self.processInBatches(photoUrls: photoUrls, criteria: criteria, originalImages: images, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
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
            
            // Check file size only
            if imageData.count > maxFileSize {
                print("🚨 Image \(index) file size too large: \(imageData.count) bytes")
                return false
            }
        }
        
        return true
    }
    
    private func uploadOptimizedPhotos(_ images: [UIImage], completion: @escaping (Result<[String], Error>) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "PhotoProcessor", code: 0,
                                       userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])))
            return
        }
        
        let dispatchGroup = DispatchGroup()
        var uploadedUrls: [String] = []
        var uploadError: Error?
        
        for (index, image) in images.enumerated() {
            dispatchGroup.enter()
            
            guard let optimizedData = optimizeImageForAI(image) else {
                uploadError = NSError(domain: "PhotoProcessor", code: 1,
                                    userInfo: [NSLocalizedDescriptionKey: "Failed to optimize image \(index + 1)"])
                dispatchGroup.leave()
                continue
            }
            
            // SECURITY: User-specific secure file path
            let timestamp = Int(Date().timeIntervalSince1970)
            let randomId = UUID().uuidString.prefix(8)
            let fileName = "ai-analysis/\(userId)/\(timestamp)_\(randomId)_\(index).jpg"
            let ref = storage.reference().child(fileName)
            
            // Upload optimized image
            ref.putData(optimizedData, metadata: nil) { _, error in
                if let error = error {
                    uploadError = error
                    dispatchGroup.leave()
                    return
                }
                
                ref.downloadURL { url, error in
                    if let error = error {
                        uploadError = error
                    } else if let url = url {
                        uploadedUrls.append(url.absoluteString)
                    }
                    dispatchGroup.leave()
                }
            }
        }
        
        dispatchGroup.notify(queue: DispatchQueue.main) {
            if let error = uploadError {
                completion(.failure(error))
            } else {
                print("Successfully uploaded \(uploadedUrls.count) optimized images")
                completion(.success(uploadedUrls))
            }
        }
    }
    
    // QUALITY-FOCUSED: Minimal processing, preserve original quality
    private func optimizeImageForAI(_ image: UIImage) -> Data? {
        let originalSize = image.size
        print("Optimizing image: original size \(originalSize)")
        
        // Calculate target size with minimal resizing
        let targetSize = calculateOptimalSize(from: originalSize)
        print("Target size: \(targetSize)")
        
        // Only resize if significantly larger than optimal
        let finalImage: UIImage
        if originalSize.width > maxAISize || originalSize.height > maxAISize {
            finalImage = resizeImage(image, to: targetSize) ?? image
            print("Resized image to \(finalImage.size)")
        } else {
            finalImage = image
            print("Using original size (within limits)")
        }
        
        // Use high-quality JPEG compression (0.9 quality)
        guard let imageData = finalImage.jpegData(compressionQuality: 0.9) else {
            print("🚨 Failed to convert image to JPEG data")
            return nil
        }
        
        print("Final image data: \(imageData.count) bytes (target: <\(maxFileSize))")
        return imageData
    }
    
    private func calculateOptimalSize(from originalSize: CGSize) -> CGSize {
        let maxDimension = max(originalSize.width, originalSize.height)
        
        // If already within optimal range, keep original
        if maxDimension <= optimalAISize {
            return originalSize
        }
        
        // If too large, scale down to optimal size
        let scaleFactor = optimalAISize / maxDimension
        return CGSize(
            width: originalSize.width * scaleFactor,
            height: originalSize.height * scaleFactor
        )
    }
    
    private func resizeImage(_ image: UIImage, to targetSize: CGSize) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    
    private func processInBatches(photoUrls: [String], criteria: RankingCriteria, originalImages: [UIImage], completion: @escaping (Result<[RankedPhoto], Error>) -> Void) {
        
        // Split into batches if needed
        let batches = photoUrls.chunked(into: maxBatchSize)
        
        if batches.count == 1 {
            // Single batch - process normally
            analyzeWithGemini(photoUrls: photoUrls, criteria: criteria, originalImages: originalImages, completion: completion)
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
            
            analyzeWithGemini(photoUrls: batch, criteria: criteria, originalImages: originalImages) { result in
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
    
    // ESSENTIAL SECURITY: Basic validation with quality preservation
    private func analyzeWithGemini(photoUrls: [String], criteria: RankingCriteria, originalImages: [UIImage], completion: @escaping (Result<[RankedPhoto], Error>) -> Void) {
        let data: [String: Any] = [
            "photoUrls": photoUrls,
            "criteria": criteria.rawValue
        ]
        
        print("Calling Firebase function with \(photoUrls.count) photos")
        
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
                
                // Parse dating insights (existing logic)
                var datingInsights: DatingInsights? = nil
                if let insights = result["datingInsights"] as? [String: Any] {
                    datingInsights = DatingInsights(
                        personalityProjected: insights["personalityProjected"] as? [String],
                        demographicAppeal: insights["demographicAppeal"] as? String,
                        profileRole: insights["profileRole"] as? String
                    )
                }
                
                // Get feedback arrays
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
                        reason = "⭐ \(bestQuality)"
                    } else if let primaryStrength = strengths?.first {
                        reason = "💪 \(primaryStrength)"
                    } else if let generalReason = result["reason"] as? String {
                        reason = generalReason
                    }
                }
                
                // Create RankedPhoto with complete data
                let rankedPhoto = RankedPhoto(
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
                
                rankedPhotos.append(rankedPhoto)
            }
            
            // Apply original images to ranked photos
            for (index, photo) in rankedPhotos.enumerated() {
                if index < originalImages.count {
                    rankedPhotos[index].localImage = originalImages[index]
                }
            }
            
            print("Successfully parsed \(rankedPhotos.count) ranked photos")
            completion(.success(rankedPhotos))
        }
    }
    
    // Apply criteria-specific logic for final selection and ordering
    private func applyCriteriaSpecificLogic(to photos: [RankedPhoto], criteria: RankingCriteria) -> [RankedPhoto] {
        let sortedPhotos = photos.sorted { $0.score > $1.score }
        
        switch criteria {
        case .best:
            // Return top photos by score
            return Array(sortedPhotos.prefix(min(sortedPhotos.count, 10)))
            
        case .balanced:
            // Create a balanced selection with different types
            return createBalancedSelection(from: sortedPhotos)
            
        case .profileOrder:
            // Sort by position logic (main photo first, etc.)
            return sortedPhotos
            
        case .conversationStarters:
            // Prioritize photos with conversation elements
            return sortedPhotos
            
        case .broadAppeal:
            // Sort by appeal breadth
            return sortedPhotos
            
        case .authenticity:
            // Prioritize authentic photos
            return sortedPhotos
        }
    }
    
    // Create a balanced selection with different photo types
    private func createBalancedSelection(from sortedPhotos: [RankedPhoto]) -> [RankedPhoto] {
        let targetCount = min(sortedPhotos.count, 10)
        var selected: [RankedPhoto] = []
        
        // Categories to balance
        let categories = ["social", "activity", "personality", "general"]
        let minPerCategory = max(1, targetCount / categories.count)
        
        print("Creating balanced selection: target \(targetCount) photos, \(minPerCategory) per category")
        
        // First pass: Ensure at least one photo from each category
        for category in categories {
            let categoryPhotos = sortedPhotos.filter { photo in
                getPhotoCategories(photo).contains(category)
            }
            
            let availablePhotos = categoryPhotos.filter { photo in
                !selected.contains { $0.id == photo.id }
            }
            
            for photo in availablePhotos.prefix(minPerCategory) {
                if selected.count < targetCount {
                    let originalReason = photo.reason ?? "Good quality photo"
                    let updatedReason = "\(originalReason)\n\n🎯 Balance: Represents \(category == "general" ? "general" : category) category (score: \(photo.score))"
                    let balancedPhoto = photo.withUpdatedReason(updatedReason)
                    selected.append(balancedPhoto)
                    
                    print("Added \(category == "general" ? "general" : category) category (score: \(photo.score))")
                }
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

// Helper extension for array chunking
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
