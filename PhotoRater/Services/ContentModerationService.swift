import UIKit

struct ContentModerationResult {
    let isAllowed: Bool
    let errorMessage: String?
}

class ContentModerationService {
    static let shared = ContentModerationService()
    private init() {}
    private let minSize: CGFloat = 100
    private let maxFileSize = 10 * 1024 * 1024 // 10MB

    func validateImageContent(image: UIImage) -> Bool {
        let result = detectInappropriateContent(image: image)
        return result.isAllowed
    }

    func detectInappropriateContent(image: UIImage) -> ContentModerationResult {
        let size = image.size
        if size.width < minSize || size.height < minSize {
            return ContentModerationResult(isAllowed: false,
                                           errorMessage: "Image dimensions must be at least 100x100 pixels")
        }

        guard image.pngData() != nil || image.jpegData(compressionQuality: 1.0) != nil else {
            return ContentModerationResult(isAllowed: false,
                                           errorMessage: "Unsupported image format")
        }

        if let data = image.jpegData(compressionQuality: 1.0), data.count > maxFileSize {
            return ContentModerationResult(isAllowed: false,
                                           errorMessage: "Image file size exceeds 10MB limit")
        }

        return ContentModerationResult(isAllowed: true, errorMessage: nil)
    }

    func blockSensitiveContent(images: [UIImage]) -> [UIImage] {
        return images.filter { detectInappropriateContent(image: $0).isAllowed }
    }
}

