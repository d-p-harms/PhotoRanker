import SwiftUI

/// Scales the contained view based on screen width for better phone and iPad support.
struct ResponsiveModifier: ViewModifier {
    func body(content: Content) -> some View {
        GeometryReader { geometry in
            // Use iPhone 15 Pro width as baseline (390pt)
            let scale = max(min(geometry.size.width / 390, 1.4), 0.8)
            content
                .scaleEffect(scale)
                .frame(width: geometry.size.width,
                       height: geometry.size.height,
                       alignment: .top)
        }
    }
}

extension View {
    /// Apply a scaling effect that adjusts automatically according to the
    /// available horizontal screen size.
    func responsive() -> some View {
        modifier(ResponsiveModifier())
    }
}
