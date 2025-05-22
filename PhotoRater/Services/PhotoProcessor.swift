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
                self.analyzeWithGemini(photoUrls: photoUrls, criteria: criteria, originalImages: images, completion: completion)
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
            
            let fileName = "uploads/photo_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(8))_\(index).jpg"
            let ref = storage.reference().child(fileName)
            
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
    
    private func analyzeWithGemini(photoUrls: [String], criteria: RankingCriteria, originalImages: [UIImage], completion: @escaping (Result<[RankedPhoto], Error>) -> Void) {
        let data: [String: Any] = [
            "photoUrls": photoUrls,
            "criteria": criteria.rawValue
        ]
        
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
            
            print("Received results: \(results)")
            
            // Parse the results
            var rankedPhotos: [RankedPhoto] = []
            
            for (index, result) in results.enumerated() {
                guard let fileName = result["fileName"] as? String,
                      let storageURL = result["storageURL"] as? String,
                      let score = result["score"] as? Double else {
                    print("Missing required fields in result: \(result)")
                    continue
                }
                
                // Parse tags - convert strings to PhotoTag enum
                let tagStrings = result["tags"] as? [String] ?? []
                let tags = tagStrings.compactMap { tagString -> PhotoTag? in
                    return PhotoTag(rawValue: tagString)
                }
                
                // Get reason - handle both 'reason' and 'bestQuality' fields
                let reason = (result["reason"] as? String) ??
                           (result["bestQuality"] as? String) ??
                           "Analysis completed"
                
                print("Creating RankedPhoto: fileName=\(fileName), score=\(score), reason=\(reason), tags=\(tags)")
                
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
            
            print("Created \(rankedPhotos.count) ranked photos")
            completion(.success(rankedPhotos))
        }
    }
}
