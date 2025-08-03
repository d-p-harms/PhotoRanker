import Foundation

// View modes available for displaying photos in the gallery.
enum GalleryViewMode: String, CaseIterable {
    case grid
    case list
    case comparison
    case profile
}

// Sorting options for organizing photos.
enum GallerySortOption: String, CaseIterable {
    case dateAdded = "Date Added"
    case score = "Score"
}

