import UIKit
import Foundation
import Firebase
import FirebaseStorage
import FirebaseFunctions
import ImageIO

class PhotoProcessor: ObservableObject {
    static let shared = PhotoProcessor()
    private let functions = Functions.functions()
    private let storage = Storage.storage()
    
    // Optimal settings for AI analysis
    private let optimalAISize: CGFloat = 1536
    private let maxAISize: CGFloat = 2048
    private let minAISize: CGFloat = 768
    private let maxBatchSize = 12
    private let maxPhotosPerSession = 25
    
    private init() {
        // Configure functions region if needed
        // functions.region = "us-central1"
    }
    
    func rankPhotos(images: [UIImage], criteria: RankingCriteria, completion: @escaping (Result<[RankedPhoto], Error>) -> Void) {
        
        // Validate photo count
        guard images.count <= maxPhotosPerSession else {
            let error = NSError(domain: "PhotoProcessor", code: 1,
                               userInfo: [NSLocalizedDescriptionKey: "Maximum \(maxPhotosPerSession) photos allowed per session"])
            completion(.failure(error))
            return
        }
        
        // Upload optimized photos first
        uploadOptimizedPhotos(images) { uploadResult in
            switch uploadResult {
            case .success(let photoUrls):
                self.processInBatches(photoUrls: photoUrls, criteria: criteria, originalImages: images, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
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
                // All batches complete - return sorted results
                allResults.sort { $0.score > $1.score }
                completion(.success(allResults))
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
    
    private func optimizeImageForAI(_ image: UIImage) -> Data? {
        let originalSize = image.size
        let scale = image.scale
        
        // Calculate actual pixel dimensions
        let pixelWidth = originalSize.width * scale
        let pixelHeight = originalSize.height * scale
        let maxDimension = max(pixelWidth, pixelHeight)
        
        print("Original image: \(Int(pixelWidth))x\(Int(pixelHeight)) pixels")
        
        // Determine optimal target size
        let targetSize: CGFloat
        if maxDimension < minAISize {
            targetSize = minAISize
            print("Upscaling small image to \(Int(targetSize))px")
        } else if maxDimension > maxAISize {
            targetSize = optimalAISize
            print("Downscaling large image to \(Int(targetSize))px")
        } else if maxDimension < optimalAISize {
            targetSize = optimalAISize
            print("Optimizing image to \(Int(targetSize))px")
        } else {
            targetSize = maxDimension
            print("Image already optimal at \(Int(targetSize))px")
        }
        
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
        
        // High-quality resize using Core Graphics
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: newWidth, height: newHeight),
            format: format
        )
        
        let resizedImage = renderer.image { context in
            context.cgContext.interpolationQuality = .high
            context.cgContext.setShouldAntialias(true)
            context.cgContext.setAllowsAntialiasing(true)
            
            image.draw(in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        }
        
        // High-quality JPEG compression for AI analysis
        let jpegData = resizedImage.jpegData(compressionQuality: 0.92)
        
        if let data = jpegData {
            let fileSizeKB = data.count / 1024
            print("Optimized image: \(Int(newWidth))x\(Int(newHeight))px, \(fileSizeKB)KB")
            
            // Validate file size (5MB safety threshold)
            if fileSizeKB > 5000 {
                print("Warning: Large file size, reducing quality")
                return resizedImage.jpegData(compressionQuality: 0.85)
            }
        }
        
        return jpegData
    }
    
    private func uploadOptimizedPhotos(_ images: [UIImage], completion: @escaping (Result<[String], Error>) -> Void) {
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
            
            let fileName = "ai-analysis/\(UUID().uuidString)_\(Int(Date().timeIntervalSince1970))_\(index).jpg"
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
                
                // Parse tags
                let tagStrings = result["tags"] as? [String] ?? []
                let tags = tagStrings.compactMap { PhotoTag(rawValue: $0) }
                
                // Parse detailed scores
                let detailedScores = DetailedScores(
                    overall: score,
                    visualQuality: result["visualQuality"] as? Double ?? score,
                    attractiveness: result["attractivenessScore"] as? Double ?? score,
                    datingAppeal: result["datingAppealScore"] as? Double ?? score,
                    swipeWorthiness: result["swipeWorthiness"] as? Double ?? score
                )
                
                // Parse technical feedback
                var technicalFeedback: TechnicalFeedback? = nil
                if let techFeedback = result["technicalFeedback"] as? [String: Any] {
                    technicalFeedback = TechnicalFeedback(
                        lighting: techFeedback["lighting"] as? String,
                        composition: techFeedback["composition"] as? String,
                        styling: techFeedback["styling"] as? String
                    )
                }
                
                // Parse dating insights
                var datingInsights: DatingInsights? = nil
                if let insights = result["datingInsights"] as? [String: Any] {
                    datingInsights = DatingInsights(
                        personalityProjected: insights["personalityProjected"] as? [String],
                        demographicAppeal: insights["demographicAppeal"] as? String,
                        profileRole: insights["profileRole"] as? String
                    )
                }
                
                // Get all the detailed feedback
                let strengths = result["strengths"] as? [String]
                let improvements = result["improvements"] as? [String] ?? result["suggestions"] as? [String]
                let nextPhotoSuggestions = result["nextPhotoSuggestions"] as? [String]
                
                // Build primary reason (keep existing logic for main display)
                var reason = "Analysis completed"
                if let bestQuality = result["bestQuality"] as? String {
                    reason = bestQuality
                    if let suggestions = improvements, !suggestions.isEmpty {
                        reason = "\(bestQuality) \n\n💡 Tip: \(suggestions[0])"
                    }
                } else if let directReason = result["reason"] as? String {
                    reason = directReason
                }
                
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
            
            print("Successfully created \(rankedPhotos.count) ranked photos")
            
            // Apply balanced selection if criteria is .balanced
            if criteria == .balanced {
                let balancedPhotos = self.createBalancedSelection(from: rankedPhotos, targetCount: 6)
                completion(.success(balancedPhotos))
            } else {
                completion(.success(rankedPhotos))
            }
        }
    }
    
    // MARK: - Balanced Selection Logic
    
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

// Helper extension for array chunking
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
