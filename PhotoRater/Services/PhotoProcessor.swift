import UIKit
import Firebase
import FirebaseStorage
import FirebaseFunctions

class PhotoProcessor {
    static let shared = PhotoProcessor()
    private let functions = Functions.functions()
    private let storage = Storage.storage()
    
    private init() {}
    
    func rankPhotos(images: [UIImage], criteria: RankingCriteria, completion: @escaping (Result<[RankedPhoto], Error>) -> Void) {
        // First upload photos
        uploadPhotos(images) { uploadResult in
            switch uploadResult {
            case .success(let photoUrls):
                // Then analyze them
                self.analyzeWithGemini(photoUrls: photoUrls, criteria: criteria, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    private func uploadPhotos(_ images: [UIImage], completion: @escaping (Result<[String], Error>) -> Void) {
        let dispatchGroup = DispatchGroup()
        var uploadedUrls: [String] = []
        var uploadError: Error?
        
        for (index, image) in images.enumerated() {
            dispatchGroup.enter()
            
            guard let data = image.jpegData(compressionQuality: 0.8) else {
                uploadError = NSError(domain: "PhotoProcessor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to data"])
                dispatchGroup.leave()
                continue
            }
            
            let fileName = "photo_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(8))_\(index).jpg"
            let ref = storage.reference().child("uploads/\(fileName)")
            
            ref.putData(data, metadata: nil) { metadata, error in
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
        
        dispatchGroup.notify(queue: .main) {
            if let error = uploadError {
                completion(.failure(error))
            } else {
                completion(.success(uploadedUrls))
            }
        }
    }
    
    private func analyzeWithGemini(photoUrls: [String], criteria: RankingCriteria, completion: @escaping (Result<[RankedPhoto], Error>) -> Void) {
        let data: [String: Any] = [
            "photoUrls": photoUrls,
            "criteria": criteria.rawValue
        ]
        
        functions.httpsCallable("analyzePhotos").call(data) { result, error in
            if let error = error {
                print("Firebase Function Error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let resultData = result?.data as? [String: Any] else {
                print("Invalid response format - not a dictionary")
                completion(.failure(NSError(domain: "PhotoProcessor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])))
                return
            }
            
            print("Firebase Function Response: \(resultData)")
            
            guard let success = resultData["success"] as? Bool, success else {
                print("Function returned success: false")
                completion(.failure(NSError(domain: "PhotoProcessor", code: 3, userInfo: [NSLocalizedDescriptionKey: "Function returned failure"])))
                return
            }
            
            guard let results = resultData["results"] as? [[String: Any]] else {
                print("Missing results in response")
                completion(.failure(NSError(domain: "PhotoProcessor", code: 4, userInfo: [NSLocalizedDescriptionKey: "Missing results in response"])))
                return
            }
            
            print("Processing \(results.count) photo results")
            
            // Parse the results
            var rankedPhotos: [RankedPhoto] = []

            for (index, result) in results.enumerated() {
                print("Processing result \(index): \(result)")
                
                guard let fileName = result["fileName"] as? String,
                      let storageURL = result["storageURL"] as? String,
                      let score = result["score"] as? Double else {
                    print("Missing required fields in result \(index)")
                    continue
                }
                
                // Parse tags - handle both string array and individual tag parsing
                var tags: [PhotoTag] = []
                if let tagStrings = result["tags"] as? [String] {
                    tags = tagStrings.compactMap { PhotoTag(rawValue: $0) }
                }
                
                // Parse reason with better fallback
                let reason = result["reason"] as? String ?? "Analysis completed successfully"
                
                print("Creating RankedPhoto - fileName: \(fileName), score: \(score), reason: \(reason)")
                
                let rankedPhoto = RankedPhoto(
                    id: UUID(),
                    fileName: fileName,
                    storageURL: storageURL,
                    score: score,
                    tags: tags,
                    reason: reason
                )
                
                rankedPhotos.append(rankedPhoto)
            }
            
            print("Successfully created \(rankedPhotos.count) ranked photos")
            completion(.success(rankedPhotos))
        }
    }
}
