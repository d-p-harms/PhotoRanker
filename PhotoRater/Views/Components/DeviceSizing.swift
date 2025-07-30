import SwiftUI

/// Utility for scaling UI elements relative to the device's screen width.
struct DeviceSizing {
    /// Returns a scale factor based on the current screen width
    /// compared to a reference width of 390pt (iPhone 14 Pro).
    static var scale: CGFloat {
        let width = UIScreen.main.bounds.width
        return max(0.8, min(width / 390, 1.5))
    }
}
